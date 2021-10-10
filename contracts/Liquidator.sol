// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./LimitOrderProtocol.sol";
import "./EIP712Alien.sol";
import "./libraries/ArgumentsDecoder.sol";
import { ILendingPoolAddressesProvider } from "./interfaces/ILendingPoolAddressesProvider.sol";
import "./interfaces/ILendingPool.sol";
import "hardhat/console.sol";


contract Liquidator is Ownable, EIP712Alien {
    using SafeERC20 for IERC20;
    using ArgumentsDecoder for bytes;
    using SafeMath for uint256;

    bytes32 constant public LIMIT_ORDER_TYPEHASH = keccak256(
        "Order(uint256 salt,address makerAsset,address takerAsset,bytes makerAssetData,bytes takerAssetData,bytes getMakerAmount,bytes getTakerAmount,bytes predicate,bytes permit,bytes interaction)"
    );

    uint256 constant private _FROM_INDEX = 0;
    uint256 constant private _TO_INDEX = 1;
    uint256 constant private _AMOUNT_INDEX = 2;

    address private immutable _limitOrderProtocol;
    ILendingPoolAddressesProvider private immutable _lendingPoolAddressProvider;

    IERC20 immutable public _token0;

    constructor(address limitOrderProtocol, IERC20 token0, ILendingPoolAddressesProvider lendingPoolAddressProvider)
    EIP712Alien(limitOrderProtocol, "1inch Limit Order Protocol", "1")
    {
        _limitOrderProtocol = limitOrderProtocol;
        _token0 = token0;
        token0.approve(limitOrderProtocol, type(uint256).max);
        _lendingPoolAddressProvider = lendingPoolAddressProvider;
    }

    function _toUint256(bytes memory _bytes) internal pure returns (uint256 value) {
        assembly {
            value := mload(add(_bytes, 0x20))
        }
    }

    function getUserAccountData(address _user)
    external
    view
    returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        ILendingPool lendingPool = ILendingPool(_lendingPoolAddressProvider.getLendingPool());
        (totalCollateralETH, totalDebtETH, availableBorrowsETH, currentLiquidationThreshold, ltv, healthFactor) = lendingPool.getUserAccountData(_user);
    }

    function isHFBelowThreshold(address _user, uint256 _threshold) external view returns(bool) {
        ILendingPool lendingPool = ILendingPool(_lendingPoolAddressProvider.getLendingPool());
        uint256 _healthFactor;
        (, , , , , _healthFactor) = lendingPool.getUserAccountData(_user);
        return _healthFactor < _threshold;
    }

    function getHealthFactor(address _user) external view returns(uint256) {
        ILendingPool lendingPool = ILendingPool(_lendingPoolAddressProvider.getLendingPool());
        uint256 _healthFactor;
        (, , , , , _healthFactor) = lendingPool.getUserAccountData(_user);
        return _healthFactor;
    }


    function _liquidate(
        address _collateral,
        address _reserve,
        address _user,
        uint256 _purchaseAmount,
        bool _receiveaToken
    )
    internal
    {
        ILendingPool lendingPool = ILendingPool(_lendingPoolAddressProvider.getLendingPool());
        require(IERC20(_reserve).approve(address(lendingPool), _purchaseAmount), "Approval error");
        lendingPool.liquidationCall(_collateral, _reserve, _user, _purchaseAmount, _receiveaToken);
    }

    /// @notice callback from limit order protocol, executes on order fill
    function notifyFillOrder(
        address makerAsset,
        address takerAsset,
        uint256 makingAmount,
        uint256 takingAmount,
        bytes memory interactiveData // abi.encode(orderHash)
    ) external {
        require(msg.sender == _limitOrderProtocol, "only LOP can exec callback");
        makerAsset;
        takingAmount;
        address collateral;
        address reserve;
        address user;
        uint256 purchaseAmount;
        bool receiveaToken;

        (collateral, reserve, user, purchaseAmount, receiveaToken) = abi.decode(interactiveData, (address, address, address, uint256, bool));
        _liquidate(collateral, reserve, user, purchaseAmount, receiveaToken);
        IERC20(makerAsset).approve(msg.sender, makingAmount);
    }

    /// @notice validate signature from Limit Order Protocol, checks also asset and amount consistency
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns(bytes4) {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        bytes memory makerAssetData;
        bytes memory takerAssetData;
        bytes memory getMakerAmount;
        bytes memory getTakerAmount;
        bytes memory predicate;
        bytes memory permit;
        bytes memory interaction;

        assembly {  // solhint-disable-line no-inline-assembly
            salt := mload(add(signature, 0x40))
            makerAsset := mload(add(signature, 0x60))
            takerAsset := mload(add(signature, 0x80))
            makerAssetData := add(add(signature, 0x40), mload(add(signature, 0xA0)))
            takerAssetData := add(add(signature, 0x40), mload(add(signature, 0xC0)))
            getMakerAmount := add(add(signature, 0x40), mload(add(signature, 0xE0)))
            getTakerAmount := add(add(signature, 0x40), mload(add(signature, 0x100)))
            predicate := add(add(signature, 0x40), mload(add(signature, 0x120)))
            permit := add(add(signature, 0x40), mload(add(signature, 0x140)))
            interaction := add(add(signature, 0x40), mload(add(signature, 0x160)))
        }

        require(
            makerAssetData.decodeAddress(_FROM_INDEX) == address(this) &&
            _hash(salt, makerAsset, takerAsset, makerAssetData, takerAssetData, getMakerAmount, getTakerAmount, predicate, permit, interaction) == hash,
            "bad order"
        );


        return this.isValidSignature.selector;
    }

    function _hash(
        uint256 salt,
        address makerAsset,
        address takerAsset,
        bytes memory makerAssetData,
        bytes memory takerAssetData,
        bytes memory getMakerAmount,
        bytes memory getTakerAmount,
        bytes memory predicate,
        bytes memory permit,
        bytes memory interaction
    ) internal view returns(bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    LIMIT_ORDER_TYPEHASH,
                    salt,
                    makerAsset,
                    takerAsset,
                    keccak256(makerAssetData),
                    keccak256(takerAssetData),
                    keccak256(getMakerAmount),
                    keccak256(getTakerAmount),
                    keccak256(predicate),
                    keccak256(permit),
                    keccak256(interaction)
                )
            )
        );
    }
}
