// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {
    MERAWalletCheckerDataOracleSlippageChecker
} from "../src/checkers/MERAWalletCheckerDataOracleSlippageChecker.sol";
import {MERAWalletAssetWhiteList} from "../src/checkers/whitelists/MERAWalletAssetWhiteList.sol";
import {MERAWalletUniswapV2SlippageTypes} from "../src/checkers/types/MERAWalletUniswapV2SlippageTypes.sol";
import {IMERAWalletUniswapV2SlippageErrors} from "../src/checkers/errors/IMERAWalletUniswapV2SlippageErrors.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {MockUniV2Router02} from "./mocks/MockUniV2Router02.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

contract MERAWalletCheckerDataOracleSlippageCheckerTest is Test {
    uint256 private _optCfgSalt = 20_000;

    uint256 internal primaryPk = 0xA11CE;
    address internal primary = vm.addr(primaryPk);
    address internal emergency = vm.addr(0xE911);

    BaseMERAWallet internal wallet;
    MERAWalletCheckerDataOracleSlippageChecker internal checker;
    ERC20Mock internal tokenA;
    ERC20Mock internal tokenB;
    ERC20Mock internal tokenC;
    ERC20Mock internal weth;
    MockUniV2Router02 internal router;
    MockAggregatorV3 internal feedA;
    MockAggregatorV3 internal feedB;

    function setUp() public {
        vm.warp(1_000_000);

        wallet = new BaseMERAWallet(primary, vm.addr(0xB0B), emergency, address(0), address(0));
        checker = new MERAWalletCheckerDataOracleSlippageChecker(emergency, 100, 3600, true);
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();
        weth = new ERC20Mock();
        router = new MockUniV2Router02(address(weth));
        feedA = new MockAggregatorV3(1e8, 8);
        feedB = new MockAggregatorV3(1e8, 8);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(0);
        vm.stopPrank();
        _setOptionalCheckers(_mkWl(address(0), true, ""));
        _setOptionalCheckers(_mkWl(address(checker), true, ""));

        vm.startPrank(emergency);
        address[] memory routers = new address[](1);
        routers[0] = address(router);
        bool[] memory routerAllowed = new bool[](1);
        routerAllowed[0] = true;
        checker.setAllowedRouters(routers, routerAllowed);

        MERAWalletAssetWhiteList defaultWl = new MERAWalletAssetWhiteList(emergency);
        address[] memory wlAssets = new address[](2);
        wlAssets[0] = address(tokenA);
        wlAssets[1] = address(tokenB);
        bool[] memory wlAllowed = new bool[](2);
        wlAllowed[0] = true;
        wlAllowed[1] = true;
        address[] memory wlSrcAssets = new address[](2);
        wlSrcAssets[0] = address(tokenA);
        wlSrcAssets[1] = address(tokenB);
        address[] memory wlSrcFeeds = new address[](2);
        wlSrcFeeds[0] = address(feedA);
        wlSrcFeeds[1] = address(feedB);
        defaultWl.setAllowedAssets(wlAssets, wlAllowed);
        defaultWl.setAssetSources(wlSrcAssets, wlSrcFeeds);
        checker.setDefaultAssetWhitelist(address(defaultWl));
        vm.stopPrank();

        tokenA.mint(address(wallet), 10 ether);
        tokenB.mint(address(router), 1000 ether);
        tokenC.mint(address(router), 1000 ether);
    }

    function _mkWl(address checkerAddr, bool allowed, bytes memory config)
        internal
        pure
        returns (MERAWalletTypes.OptionalCheckerUpdate[] memory u)
    {
        u = new MERAWalletTypes.OptionalCheckerUpdate[](1);
        u[0] = MERAWalletTypes.OptionalCheckerUpdate({checker: checkerAddr, allowed: allowed, config: config});
    }

    function _setAllRoleTimelocks(uint256 delay) internal {
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Primary, delay), 7101
        );
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Backup, delay), 7102
        );
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Emergency, delay), 7103
        );
    }

    function _setOptionalCheckers(MERAWalletTypes.OptionalCheckerUpdate[] memory updates) internal {
        vm.startPrank(emergency);
        _executeEmergencyWalletSelfCallTimelocked(
            abi.encodeWithSelector(wallet.setOptionalCheckers.selector, updates), ++_optCfgSalt
        );
        vm.stopPrank();
    }

    function _executeEmergencyWalletSelfCallTimelocked(bytes memory data, uint256 salt) internal {
        MERAWalletTypes.Call[] memory calls = _singleCall(address(wallet), 0, data);
        if (wallet.getRequiredDelay(calls) == 0) {
            wallet.executeTransaction(calls, salt);
            return;
        }
        bytes32 opId = wallet.proposeTransaction(calls, salt);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(opId);
        vm.warp(executeAfter);
        wallet.executePending(calls, salt);
    }

    function _executeWalletSelfCall(bytes memory data, uint256 salt) internal {
        wallet.executeTransaction(_singleCall(address(wallet), 0, data), salt);
    }

    function _singleCall(address target, uint256 value, bytes memory data)
        internal
        pure
        returns (MERAWalletTypes.Call[] memory calls)
    {
        calls = new MERAWalletTypes.Call[](1);
        calls[0] =
            MERAWalletTypes.Call({target: target, value: value, data: data, checker: address(0), checkerData: ""});
    }

    function _swapCallData(uint256 amountIn, uint256 amountOutMin, address tokenIn, address tokenOut)
        internal
        view
        returns (bytes memory)
    {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        return abi.encodeWithSelector(
            MockUniV2Router02.swapExactTokensForTokens.selector,
            amountIn,
            amountOutMin,
            path,
            address(wallet),
            block.timestamp + 1
        );
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
            data: _swapCallData(1 ether, 0, address(tokenA), address(tokenB)),
            checker: slippageChecker,
            checkerData: checkerData
        });
    }

    function test_CheckerDataSwapWithinOracleTolerance_Succeeds() public {
        router.setBadRate(false);

        vm.prank(primary);
        wallet.executeTransaction(_approveAndSwapCalls(_checkerData(address(tokenA), address(tokenB), false, false)), 1);
    }

    function test_CheckerDataSwapWorseThanOracle_Reverts() public {
        router.setBadRate(true);

        vm.prank(primary);
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SwapWorseThanOracle.selector);
        wallet.executeTransaction(_approveAndSwapCalls(_checkerData(address(tokenA), address(tokenB), false, false)), 2);
    }

    function test_CheckerDataStaleOracle_Reverts() public {
        router.setBadRate(false);
        vm.prank(emergency);
        feedA.setUpdatedAt(block.timestamp - 4000);

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletUniswapV2SlippageErrors.StaleOraclePrice.selector, address(tokenA), block.timestamp - 4000
            )
        );
        wallet.executeTransaction(_approveAndSwapCalls(_checkerData(address(tokenA), address(tokenB), false, false)), 3);
    }

    function test_CheckerDataBeforeHook_DoesNotDecodeCallData() public {
        MERAWalletTypes.Call memory call = MERAWalletTypes.Call({
            target: address(router),
            value: 0,
            data: abi.encodeWithSelector(bytes4(0xdeadbeef)),
            checker: address(checker),
            checkerData: _checkerData(address(tokenA), address(tokenB), false, false)
        });

        vm.prank(address(wallet));
        checker.checkBefore(call, keccak256("unsupported-calldata"), 0);
    }

    function test_CheckerDataBeforeHook_DoesNotCheckCallDataDeadline() public {
        MERAWalletTypes.Call memory call = MERAWalletTypes.Call({
            target: address(router),
            value: 0,
            data: _swapCallData(1 ether, 0, address(tokenA), address(tokenB)),
            checker: address(checker),
            checkerData: _checkerData(address(tokenA), address(tokenB), false, false)
        });

        vm.warp(block.timestamp + 2);

        vm.prank(address(wallet));
        checker.checkBefore(call, keccak256("expired-calldata-deadline"), 0);
    }

    function test_CheckerDataZeroTokenIn_Reverts() public {
        MERAWalletTypes.Call memory call = MERAWalletTypes.Call({
            target: address(router),
            value: 0,
            data: "",
            checker: address(checker),
            checkerData: _checkerData(address(0), address(tokenB), false, false)
        });

        vm.prank(address(wallet));
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SlippageInvalidAddress.selector);
        checker.checkBefore(call, keccak256("zero-token-in"), 0);
    }

    function test_CheckerDataEthInAndEthOut_Reverts() public {
        MERAWalletTypes.Call memory call = MERAWalletTypes.Call({
            target: address(router),
            value: 0,
            data: "",
            checker: address(checker),
            checkerData: _checkerData(address(tokenA), address(tokenB), true, true)
        });

        vm.prank(address(wallet));
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.InvalidCheckerData.selector);
        checker.checkBefore(call, keccak256("both-eth-flags"), 0);
    }

    function test_CheckerDataAssetWhitelist_RevertsWhenTokenOutNotAllowed() public {
        MERAWalletAssetWhiteList aw = new MERAWalletAssetWhiteList(emergency);
        address[] memory assets = new address[](1);
        assets[0] = address(tokenA);
        bool[] memory allowed = new bool[](1);
        allowed[0] = true;
        vm.prank(emergency);
        aw.setAllowedAssets(assets, allowed);

        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg =
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({
                assetWhitelist: address(aw),
                maxOracleNegativeDeviationBps: 0,
                maxOracleStaleSeconds: 0,
                whitelistRouter: address(0)
            });
        _setOptionalCheckers(_mkWl(address(checker), true, abi.encode(cfg)));

        router.setBadRate(false);

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletUniswapV2SlippageErrors.AssetNotWhitelisted.selector, address(tokenB), uint256(1)
            )
        );
        wallet.executeTransaction(_approveAndSwapCalls(_checkerData(address(tokenA), address(tokenB), false, false)), 4);
    }

    function test_CheckerDataRouterNotAllowed_Reverts() public {
        address[] memory routers = new address[](1);
        routers[0] = address(router);
        bool[] memory allowed = new bool[](1);
        allowed[0] = false;
        vm.prank(emergency);
        checker.setAllowedRouters(routers, allowed);

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletUniswapV2SlippageErrors.RouterNotAllowed.selector, address(router), uint256(1)
            )
        );
        wallet.executeTransaction(_approveAndSwapCalls(_checkerData(address(tokenA), address(tokenB), false, false)), 5);
    }

    /// @dev Router allowlist disabled at deploy: swap succeeds even when router is not in `allowedRouter`.
    function test_CheckerDataRequireRouterAllowlistFalse_SkipsRouterGate() public {
        MERAWalletCheckerDataOracleSlippageChecker looseChecker =
            new MERAWalletCheckerDataOracleSlippageChecker(emergency, 100, 3600, false);
        assertFalse(looseChecker.REQUIRE_ROUTER_ALLOWLIST());

        vm.startPrank(emergency);
        looseChecker.setDefaultAssetWhitelist(checker.defaultAssetWhitelist());
        vm.stopPrank();

        _setOptionalCheckers(_mkWl(address(checker), false, ""));
        _setOptionalCheckers(_mkWl(address(looseChecker), true, ""));

        bytes memory cd = _checkerData(address(tokenA), address(tokenB), false, false);
        router.setBadRate(false);
        vm.prank(primary);
        wallet.executeTransaction(_approveAndSwapCallsWith(address(looseChecker), cd), 55_001);
    }
}
