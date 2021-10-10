// Traditional Truffle test
const { ether, expectRevert } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');

const axios = require('axios');
const hre = require('hardhat');

const TokenMock = artifacts.require('TokenMock');

const { bufferToHex } = require('ethereumjs-util');
const ethSigUtil = require('eth-sig-util');
const Wallet = require('ethereumjs-wallet').default;

const LimitOrderProtocol = artifacts.require('LimitOrderProtocol');
const ChainlinkCalculator = artifacts.require('ChainlinkCalculator');
const AggregatorV3Mock = artifacts.require('AggregatorV3Mock');

const DAI_ABI = require('../abis/DAI');
const GUSD_ABI = require('../abis/GUSD');
const UNI_ABI = require('../abis/UNI');
const WETH_ABI = require('../abis/WETH');

const { buildOrderData, ABIOrder } = require('../test/helpers/orderUtils');
const { cutLastArg, toBN } = require('../test/helpers/utils');
const { web3 } = require('@openzeppelin/test-helpers/src/setup');

contract('LimitOrderProtocol', async function ([_, wallet]) {
	const privatekey =
		'59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';

	const account = Wallet.fromPrivateKey(Buffer.from(privatekey, 'hex'));
	const aaveProtocolDataProvider = '0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d';
	const aaveLendingPoolAddressProvider = '0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5';
	const zeroAddress = '0x0000000000000000000000000000000000000000';

	const ASSET_ADDRESSES = {
		DAI: '0x6b175474e89094c44da98b954eedeac495271d0f',
		WETH: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2',
		GUSD: '0x056fd409e1d7a124bd7017459dfea2f387b6d5cd',
		UNI: '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984',
	};

	function buildOrder (
		exchange,
		makerAsset,
		takerAsset,
		makerAmount,
		takerAmount,
		maker = zeroAddress,
		taker = zeroAddress,
		predicate = '0x',
		permit = '0x',
		interaction = '0x',
	) {
		return buildOrderWithSalt(
			exchange,
			'1',
			makerAsset,
			takerAsset,
			makerAmount,
			takerAmount,
			maker,
			taker,
			predicate,
			permit,
			interaction,
		);
	}

	function buildOrderWithSalt (
		exchange,
		salt,
		makerAsset,
		takerAsset,
		makerAmount,
		takerAmount,
		maker = zeroAddress,
		taker = zeroAddress,
		predicate = '0x',
		permit = '0x',
		interaction = '0x',
	) {
		return {
			salt: salt,
			makerAsset: makerAsset.address,
			takerAsset: takerAsset.address,
			makerAssetData: makerAsset.contract.methods
				.transferFrom(wallet, taker, makerAmount)
				.encodeABI(),
			takerAssetData: takerAsset.contract.methods
				.transferFrom(taker, wallet, takerAmount)
				.encodeABI(),
			getMakerAmount: cutLastArg(
				exchange.contract.methods
					.getMakerAmount(makerAmount, takerAmount, 0)
					.encodeABI(),
			),
			getTakerAmount: cutLastArg(
				exchange.contract.methods
					.getTakerAmount(makerAmount, takerAmount, 0)
					.encodeABI(),
			),
			predicate: predicate,
			permit: permit,
			interaction: interaction,
		};
	}

	beforeEach(async function () {
		const GUSDAccountToImpersonate = "0xA3d513544b45CDe9e22dF4d7a6A1fE5029A407b1";
		const UNIAccountToImpersonate = "0x47173b170c64d16393a52e6c480b3ad8c302ba1e";

		await hre.network.provider.send("hardhat_impersonateAccount", [GUSDAccountToImpersonate]);
		await hre.network.provider.send("hardhat_impersonateAccount", [UNIAccountToImpersonate]);
		await web3.eth.sendTransaction({to: GUSDAccountToImpersonate, from: wallet, value: ether('4')});
		await web3.eth.sendTransaction({to: UNIAccountToImpersonate, from: wallet, value: ether('4')});


		this.swap = await LimitOrderProtocol.new();
		// this.calculator = await ChainlinkCalculator.new();
		// this.solarisMargin = await SolarisMargin.new(this.swap.address, oneInchExchangeAddress, aaveLendingPoolAddressProvider, aaveProtocolDataProvider);

		this.usdc = await TokenMock.new('USDC', 'USDC');
		// this.dai = await TokenMock.new('DAI', 'DAI');
		// this.weth = await TokenMock.new('WETH', 'WETH');

		this.dai = new web3.eth.Contract(DAI_ABI, ASSET_ADDRESSES.DAI);
		this.dai.address = ASSET_ADDRESSES.DAI;
		this.gusd = new web3.eth.Contract(GUSD_ABI, ASSET_ADDRESSES.GUSD);
		this.gusd.address = ASSET_ADDRESSES.GUSD;
		this.uni = new web3.eth.Contract(UNI_ABI, ASSET_ADDRESSES.UNI);
		this.uni.address = ASSET_ADDRESSES.UNI;

		this.dai.contract = {methods: this.dai.methods};
		this.gusd.contract = {methods: this.gusd.methods};
		this.uni.contract = {methods: this.uni.methods};

		// We get the chain id from the contract because Ganache (used for coverage) does not return the same chain id
		// from within the EVM as from the JSON RPC interface.
		// See https://github.com/trufflesuite/ganache-core/issues/515
		this.chainId = await this.usdc.getChainId()

		await this.gusd.methods.transfer(_, '1000000').send({from: GUSDAccountToImpersonate});
		await this.uni.methods.transfer(wallet, '1000000').send({from: UNIAccountToImpersonate});

		await this.uni.methods.approve(this.swap.address, '1000000').send({ from: wallet });
		await this.gusd.methods.approve(this.swap.address, '1000000').send({ from: _ });
	});

	describe('My test', function () {
		it('should swap uni', async function () {
			// Order: 1 UNI => 1 GUSD
			// Swap:  1 UNI => 1 GUSD
			const order = buildOrder(this.swap, this.uni, this.gusd, 1, 1);
			const data = buildOrderData(this.chainId, this.swap.address, order);
			const signature = ethSigUtil.signTypedMessage(account.getPrivateKey(), { data });
			const makerUNI = await this.uni.methods.balanceOf(wallet).call();
			console.log(`###: makerUNI`, makerUNI)
			const takerUNI = await this.uni.methods.balanceOf(_).call();
			const makerGUSD = await this.gusd.methods.balanceOf(wallet).call();
			const takerGUSD = await this.gusd.methods.balanceOf(_).call();
			const receipt = await this.swap.fillOrder(order, signature, 1, 0, 1);
			const makerUNIAfter = await this.uni.methods.balanceOf(wallet).call();
			console.log(`###: makerUNIAfter`, makerUNIAfter)
			// expect((await this.uni.methods.balanceOf(wallet)).call()).to.be.bignumber.equal(makerUNI.subn(1));
			// expect((await this.uni.methods.balanceOf(_)).call()).to.be.bignumber.equal(takerUNI.addn(1));
			// expect((await this.cgt.methods.balanceOf(wallet)).call()).to.be.bignumber.equal(makerGUSD.addn(1));
			// expect((await this.cgt.methods.balanceOf(_)).call()).to.be.bignumber.equal(takerGUSD.subn(1));
			return true;
		});
	});
});
