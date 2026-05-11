// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {BaseMERAWallet} from "../../src/BaseMERAWallet.sol";
import {MERAWalletTypes} from "../../src/types/MERAWalletTypes.sol";
import {MERAWalletOracleSlippageCheckerBase} from "../../src/checkers/MERAWalletOracleSlippageCheckerBase.sol";
import {MERAWalletAssetWhiteList} from "../../src/checkers/whitelists/MERAWalletAssetWhiteList.sol";
import {MERAWalletWhitelistRouter} from "../../src/checkers/whitelists/MERAWalletWhitelistRouter.sol";
import {MERAWalletUniswapV2SlippageTypes} from "../../src/checkers/types/MERAWalletUniswapV2SlippageTypes.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockUniV2Router02} from "../mocks/MockUniV2Router02.sol";
import {MockAggregatorV3} from "../mocks/MockAggregatorV3.sol";
import {MERAWalletTestBase} from "./MERAWalletTestBase.sol";

abstract contract MERAWalletSlippageFixture is MERAWalletTestBase {
    uint256 internal _optCfgSalt = 10_000;

    uint256 internal primaryPk = PRIMARY_PK;
    address internal primary = vm.addr(PRIMARY_PK);
    address internal backup = vm.addr(BACKUP_PK);
    address internal emergency = vm.addr(EMERGENCY_PK);
    address internal pauseAgent = PAUSE_AGENT;
    address internal outsider = OUTSIDER_ADDRESS;

    BaseMERAWallet internal wallet;
    MERAWalletOracleSlippageCheckerBase internal checker;
    ERC20Mock internal tokenA;
    ERC20Mock internal tokenB;
    ERC20Mock internal tokenC;
    ERC20Mock internal weth;
    MockUniV2Router02 internal router;
    MockAggregatorV3 internal feedA;
    MockAggregatorV3 internal feedB;
    MERAWalletWhitelistRouter internal whitelistRouter;

    function _setUpSlippageFixture(MERAWalletOracleSlippageCheckerBase checker_) internal {
        vm.warp(DEFAULT_TEST_TIMESTAMP);

        wallet = new BaseMERAWallet(primary, backup, emergency, address(0), address(0));
        checker = checker_;
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();
        weth = new ERC20Mock();
        router = new MockUniV2Router02(address(weth));
        feedA = new MockAggregatorV3(1e8, 8);
        feedB = new MockAggregatorV3(1e8, 8);
        whitelistRouter = new MERAWalletWhitelistRouter(emergency);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(wallet, 0);
        vm.stopPrank();
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(0), true, ""));
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), true, ""));

        vm.startPrank(emergency);
        checker.setAllowedRouters(_oneAddress(address(router)), _oneBool(true));
        vm.stopPrank();

        MERAWalletAssetWhiteList defaultWl = _assetWhitelist(true);

        vm.startPrank(emergency);
        checker.setDefaultAssetWhitelist(address(defaultWl));

        checker.setPauseAgents(_oneAddress(pauseAgent), _oneBool(true));
        vm.stopPrank();

        tokenA.mint(address(wallet), 10 ether);
        tokenB.mint(address(router), 1000 ether);
    }

    function _setOptionalCheckers(MERAWalletTypes.OptionalCheckerUpdate[] memory updates) internal {
        vm.startPrank(emergency);
        _executeEmergencyWalletSelfCallTimelocked(
            wallet, abi.encodeWithSelector(wallet.setOptionalCheckers.selector, updates), ++_optCfgSalt
        );
        vm.stopPrank();
    }

    function _approveAndSwapCalls() internal view returns (MERAWalletTypes.Call[] memory calls) {
        return _approveAndSwapCallsWith(address(checker));
    }

    function _approveAndSwapCallsWith(address slippageChecker)
        internal
        view
        returns (MERAWalletTypes.Call[] memory calls)
    {
        return _approveAndSwapCallsWith(slippageChecker, "");
    }

    function _approveAndSwapCalls(bytes memory checkerData)
        internal
        view
        returns (MERAWalletTypes.Call[] memory calls)
    {
        return _approveAndSwapCallsWith(address(checker), checkerData);
    }

    function _approveAndSwapCallsWith(address slippageChecker, bytes memory checkerData)
        internal
        view
        returns (MERAWalletTypes.Call[] memory calls)
    {
        calls = new MERAWalletTypes.Call[](2);
        calls[0] = MERAWalletTypes.Call({
            target: address(tokenA),
            value: 0,
            data: abi.encodeWithSelector(ERC20Mock.approve.selector, address(router), type(uint256).max),
            checker: address(0),
            checkerData: ""
        });
        calls[1] = MERAWalletTypes.Call({
            target: address(router),
            value: 0,
            data: _swapCallData(1 ether, 0),
            checker: slippageChecker,
            checkerData: checkerData
        });
    }

    function _swapCallData(uint256 amountIn, uint256 amountOutMin) internal view returns (bytes memory) {
        return _swapCallData(amountIn, amountOutMin, address(tokenA), address(tokenB));
    }

    function _swapCallData(uint256 amountIn, uint256 amountOutMin, address tokenIn, address tokenOut)
        internal
        view
        returns (bytes memory)
    {
        address[] memory path = _twoAddresses(tokenIn, tokenOut);
        return abi.encodeWithSelector(
            MockUniV2Router02.swapExactTokensForTokens.selector,
            amountIn,
            amountOutMin,
            path,
            address(wallet),
            block.timestamp + 1
        );
    }

    function _swapCallDataThreeHop(uint256 amountIn, uint256 amountOutMin) internal view returns (bytes memory) {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenC);
        path[2] = address(tokenB);
        return abi.encodeWithSelector(
            MockUniV2Router02.swapExactTokensForTokens.selector,
            amountIn,
            amountOutMin,
            path,
            address(wallet),
            block.timestamp + 1
        );
    }

    function _assetWhitelist(bool allowTokenB) internal returns (MERAWalletAssetWhiteList aw) {
        aw = new MERAWalletAssetWhiteList(emergency);
        vm.startPrank(emergency);
        aw.setAllowedAssets(_twoAddresses(address(tokenA), address(tokenB)), _twoBools(true, allowTokenB));
        aw.setAssetSources(
            _twoAddresses(address(tokenA), address(tokenB)), _twoAddresses(address(feedA), address(feedB))
        );
        vm.stopPrank();
    }

    function _routerCfg()
        internal
        view
        returns (MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory)
    {
        return _slippageConfig(address(0), 0, 0, address(whitelistRouter));
    }

    function _slippageConfig(address assetWhitelist, uint256 maxNegativeDeviationBps, uint256 maxStaleSeconds)
        internal
        pure
        returns (MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory)
    {
        return _slippageConfig(assetWhitelist, maxNegativeDeviationBps, maxStaleSeconds, address(0));
    }

    function _slippageConfig(
        address assetWhitelist,
        uint256 maxNegativeDeviationBps,
        uint256 maxStaleSeconds,
        address router_
    ) internal pure returns (MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory) {
        return MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({
            assetWhitelist: assetWhitelist,
            maxOracleNegativeDeviationBps: maxNegativeDeviationBps,
            maxOracleStaleSeconds: maxStaleSeconds,
            whitelistRouter: router_
        });
    }

    function _checkerData(address tokenIn, address tokenOut, bool ethIn, bool ethOut)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            MERAWalletUniswapV2SlippageTypes.CheckerDataSlippageCheckData({
                tokenIn: tokenIn, tokenOut: tokenOut, ethIn: ethIn, ethOut: ethOut
            })
        );
    }
}
