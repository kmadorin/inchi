pragma solidity ^0.8.0;

interface ILendingPool {
  function liquidationCall ( address _collateral, address _reserve, address _user, uint256 _purchaseAmount, bool _receiveAToken ) external payable;
  /**
  * @dev Returns the user account data across all the reserves
  * @param user The address of the user
  * @return totalCollateralETH the total collateral in ETH of the user
  * @return totalDebtETH the total debt in ETH of the user
  * @return availableBorrowsETH the borrowing power left of the user
  * @return currentLiquidationThreshold the liquidation threshold of the user
  * @return ltv the loan to value of the user
  * @return healthFactor the current health factor of the user
  **/
  function getUserAccountData(address user)
  external
  view
  returns (
    uint256 totalCollateralETH,
    uint256 totalDebtETH,
    uint256 availableBorrowsETH,
    uint256 currentLiquidationThreshold,
    uint256 ltv,
    uint256 healthFactor
  );
  function repay(
    address asset,
    uint256 amount,
    uint256 rateMode,
    address onBehalfOf
  ) external returns (uint256);

  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external returns (uint256);

  function deposit(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode
  ) external;

  function borrow(
    address asset,
    uint256 amount,
    uint256 interestRateMode,
    uint16 referralCode,
    address onBehalfOf
  ) external;
}
