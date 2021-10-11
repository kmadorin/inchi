Zero-cost Aave liquidations and liquidation protection using 1inch limit order protocol

Liquidations Contract - Liquidator.sol
Liquidation protection contract - Defender.sol

How to run:
1. `yarn install`
2. Set your infura or alchemy api endpoint in hardhat.config.js to run mainnet fork when testing
3. `yarn test` - to run tests, which are in `mytests/to_test/index.js` folder

TODO:
1. Implement getTakerAmount and getMakerAmount to take compounded interest into account on order fill
2. Implement smart wallet contract to allow Defender to work not only for it's owner
3. Add UI
