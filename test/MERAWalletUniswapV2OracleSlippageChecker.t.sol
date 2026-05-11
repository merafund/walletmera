// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletUniswapV2OracleSlippageChecker} from "../src/checkers/MERAWalletUniswapV2OracleSlippageChecker.sol";
import {MERAWalletAssetWhiteList} from "../src/checkers/whitelists/MERAWalletAssetWhiteList.sol";
import {MERAWalletWhitelistRouter} from "../src/checkers/whitelists/MERAWalletWhitelistRouter.sol";
import {MERAWalletUniswapV2SlippageTypes} from "../src/checkers/types/MERAWalletUniswapV2SlippageTypes.sol";
import {IMERAWalletUniswapV2SlippageErrors} from "../src/checkers/errors/IMERAWalletUniswapV2SlippageErrors.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {MockUniV2Router02} from "./mocks/MockUniV2Router02.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";
import {MERAWalletSlippageFixture} from "./helpers/MERAWalletSlippageFixture.sol";

contract SlippageSnapshotHarness {
    using MERAWalletUniswapV2SlippageTypes for bytes32;

    function load(bytes32 key) external view returns (MERAWalletUniswapV2SlippageTypes.Snapshot memory) {
        return key.loadSnapshot();
    }

    function storeAndLoad(bytes32 key, MERAWalletUniswapV2SlippageTypes.Snapshot memory snapshot)
        external
        returns (MERAWalletUniswapV2SlippageTypes.Snapshot memory)
    {
        key.storeSnapshot(snapshot);
        return key.loadSnapshot();
    }
}

contract MERAWalletUniswapV2OracleSlippageCheckerTest is MERAWalletSlippageFixture {
    function setUp() public {
        _setUpSlippageFixture(
            new MERAWalletUniswapV2OracleSlippageChecker(
                emergency,
                DEFAULT_MAX_ORACLE_NEGATIVE_DEVIATION_BPS,
                DEFAULT_MAX_ORACLE_STALE_SECONDS,
                DEFAULT_REQUIRE_ROUTER_ALLOWLIST
            )
        );
    }

    function test_AssetWhitelist_RevertsWhenPathTokenNotAllowed() public {
        MERAWalletAssetWhiteList aw = new MERAWalletAssetWhiteList(emergency);
        address[] memory assets = new address[](1);
        assets[0] = address(tokenA);
        bool[] memory allowed = new bool[](1);
        allowed[0] = true;
        vm.prank(emergency);
        aw.setAllowedAssets(assets, allowed);

        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg = _slippageConfig(address(aw), 0, 0);
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), true, abi.encode(cfg)));

        router.setBadRate(false);

        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](2);
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
            checker: address(checker),
            checkerData: ""
        });

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletUniswapV2SlippageErrors.AssetNotWhitelisted.selector, address(tokenB), uint256(1)
            )
        );
        wallet.executeTransaction(calls, 42);
    }

    /// @dev Intermediate `tokenC` is not on the default whitelist; only path endpoints are validated.
    function test_AssetWhitelist_AllowsMultiHopWhenIntermediateNotWhitelisted() public {
        router.setBadRate(false);

        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](2);
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
            data: _swapCallDataThreeHop(1 ether, 0),
            checker: address(checker),
            checkerData: ""
        });

        vm.prank(primary);
        wallet.executeTransaction(calls, 46);
    }

    function test_DefaultAssetWhitelist_AllowsSwapWhenWalletSlotUnset() public {
        MERAWalletAssetWhiteList aw = new MERAWalletAssetWhiteList(emergency);
        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);
        bool[] memory allowed = new bool[](2);
        allowed[0] = true;
        allowed[1] = true;
        address[] memory srcAssets = new address[](2);
        srcAssets[0] = address(tokenA);
        srcAssets[1] = address(tokenB);
        address[] memory srcFeeds = new address[](2);
        srcFeeds[0] = address(feedA);
        srcFeeds[1] = address(feedB);

        vm.startPrank(emergency);
        aw.setAllowedAssets(assets, allowed);
        aw.setAssetSources(srcAssets, srcFeeds);
        checker.setDefaultAssetWhitelist(address(aw));
        vm.stopPrank();

        router.setBadRate(false);

        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](2);
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
            checker: address(checker),
            checkerData: ""
        });

        vm.prank(primary);
        wallet.executeTransaction(calls, 43);
    }

    function test_AssetWhitelist_CustomSourceOverridesBaseFeed() public {
        MERAWalletAssetWhiteList aw = new MERAWalletAssetWhiteList(emergency);
        MockAggregatorV3 customFeedA = new MockAggregatorV3(1e8, 8);
        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);
        bool[] memory allowed = new bool[](2);
        allowed[0] = true;
        allowed[1] = true;
        address[] memory sourceAssets = new address[](2);
        sourceAssets[0] = address(tokenA);
        sourceAssets[1] = address(tokenB);
        address[] memory sources = new address[](2);
        sources[0] = address(customFeedA);
        sources[1] = address(feedB);

        vm.startPrank(emergency);
        aw.setAllowedAssets(assets, allowed);
        aw.setAssetSources(sourceAssets, sources);
        feedA.setAnswer(2e8);
        vm.stopPrank();

        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg =
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({
                assetWhitelist: address(aw),
                maxOracleNegativeDeviationBps: 0,
                maxOracleStaleSeconds: 0,
                whitelistRouter: address(0)
            });
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), true, abi.encode(cfg)));

        router.setBadRate(false);

        vm.prank(primary);
        wallet.executeTransaction(_approveAndSwapCalls(), 44);
    }

    // Feeds for endpoints resolve through fallback whitelist when local sources are unset.
    function test_AssetWhitelist_UsesFallbackFeedsWhenLocalSourceUnset() public {
        MERAWalletAssetWhiteList baseFeeds = new MERAWalletAssetWhiteList(emergency);
        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);
        bool[] memory allowed = new bool[](2);
        allowed[0] = true;
        allowed[1] = true;
        address[] memory srcAssets = new address[](2);
        srcAssets[0] = address(tokenA);
        srcAssets[1] = address(tokenB);
        address[] memory srcFeeds = new address[](2);
        srcFeeds[0] = address(feedA);
        srcFeeds[1] = address(feedB);

        vm.startPrank(emergency);
        baseFeeds.setAllowedAssets(assets, allowed);
        baseFeeds.setAssetSources(srcAssets, srcFeeds);

        MERAWalletAssetWhiteList aw = new MERAWalletAssetWhiteList(emergency);
        aw.setAllowedAssets(assets, allowed);
        aw.setFallbackWhitelist(address(baseFeeds));
        feedA.setAnswer(2e8);
        vm.stopPrank();

        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg =
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({
                assetWhitelist: address(aw),
                maxOracleNegativeDeviationBps: 0,
                maxOracleStaleSeconds: 0,
                whitelistRouter: address(0)
            });
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), true, abi.encode(cfg)));

        router.setBadRate(false);

        vm.prank(primary);
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SwapWorseThanOracle.selector);
        wallet.executeTransaction(_approveAndSwapCalls(), 45);
    }

    function test_AssetWhitelist_UsesRouterWhenExplicitConfigZero() public {
        MERAWalletAssetWhiteList aw = _assetWhitelist(true);
        bytes32 assetKey = whitelistRouter.ASSET_WHITELIST_KEY();

        vm.prank(emergency);
        whitelistRouter.setWhitelist(assetKey, address(aw));
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), true, abi.encode(_routerCfg())));

        router.setBadRate(false);
        vm.prank(primary);
        wallet.executeTransaction(_approveAndSwapCalls(), 47);
    }

    function test_AssetWhitelist_ExplicitWinsOverRouter() public {
        MERAWalletAssetWhiteList explicitWl = _assetWhitelist(true);
        MERAWalletAssetWhiteList blockedRouterWl = _assetWhitelist(false);
        bytes32 assetKey = whitelistRouter.ASSET_WHITELIST_KEY();

        vm.prank(emergency);
        whitelistRouter.setWhitelist(assetKey, address(blockedRouterWl));

        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg =
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({
                assetWhitelist: address(explicitWl),
                maxOracleNegativeDeviationBps: 0,
                maxOracleStaleSeconds: 0,
                whitelistRouter: address(whitelistRouter)
            });
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), true, abi.encode(cfg)));

        router.setBadRate(false);
        vm.prank(primary);
        wallet.executeTransaction(_approveAndSwapCalls(), 48);
    }

    function test_AssetWhitelist_DefaultUsedWhenRouterRouteMissing() public {
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), true, abi.encode(_routerCfg())));

        router.setBadRate(false);
        vm.prank(primary);
        wallet.executeTransaction(_approveAndSwapCalls(), 49);
    }

    function test_AssetWhitelist_RouterRouteChangeAppliesWithoutReapplyingCheckerConfig() public {
        MERAWalletAssetWhiteList goodWl = _assetWhitelist(true);
        MERAWalletAssetWhiteList blockedWl = _assetWhitelist(false);
        bytes32 assetKey = whitelistRouter.ASSET_WHITELIST_KEY();

        vm.prank(emergency);
        whitelistRouter.setWhitelist(assetKey, address(goodWl));
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), true, abi.encode(_routerCfg())));

        router.setBadRate(false);
        vm.prank(primary);
        wallet.executeTransaction(_approveAndSwapCalls(), 50);

        vm.prank(emergency);
        whitelistRouter.setWhitelist(assetKey, address(blockedWl));

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletUniswapV2SlippageErrors.AssetNotWhitelisted.selector, address(tokenB), uint256(1)
            )
        );
        wallet.executeTransaction(_approveAndSwapCalls(), 51);
    }

    function test_SwapWithinOracleTolerance_Succeeds() public {
        router.setBadRate(false);

        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](2);
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
            checker: address(checker),
            checkerData: ""
        });

        vm.prank(primary);
        wallet.executeTransaction(calls, 1);
    }

    function test_SwapWorseThanOracle_Reverts() public {
        router.setBadRate(true);

        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](2);
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
            checker: address(checker),
            checkerData: ""
        });

        vm.prank(primary);
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SwapWorseThanOracle.selector);
        wallet.executeTransaction(calls, 1);
    }

    function test_RouterNotAllowed_Reverts() public {
        address[] memory routers = new address[](1);
        routers[0] = address(router);
        bool[] memory allowed = new bool[](1);
        allowed[0] = false;
        vm.prank(emergency);
        checker.setAllowedRouters(routers, allowed);

        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: address(router),
            value: 0,
            data: _swapCallData(1 ether, 0),
            checker: address(checker),
            checkerData: ""
        });

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletUniswapV2SlippageErrors.RouterNotAllowed.selector, address(router), uint256(0)
            )
        );
        wallet.executeTransaction(calls, 1);
    }

    /// @dev Router allowlist disabled at deploy: swap succeeds even when router is not in `allowedRouter`.
    function test_RequireRouterAllowlistFalse_SkipsRouterGate() public {
        MERAWalletUniswapV2OracleSlippageChecker looseChecker = new MERAWalletUniswapV2OracleSlippageChecker(
            emergency, DEFAULT_MAX_ORACLE_NEGATIVE_DEVIATION_BPS, DEFAULT_MAX_ORACLE_STALE_SECONDS, false
        );
        assertFalse(looseChecker.REQUIRE_ROUTER_ALLOWLIST());

        vm.startPrank(emergency);
        looseChecker.setDefaultAssetWhitelist(checker.defaultAssetWhitelist());
        vm.stopPrank();

        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), false, ""));
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(looseChecker), true, ""));

        router.setBadRate(false);
        vm.prank(primary);
        wallet.executeTransaction(_approveAndSwapCallsWith(address(looseChecker)), 77_001);
    }

    function test_UnsupportedSelector_Reverts() public {
        bytes4 badSel = UNSUPPORTED_SELECTOR;
        MERAWalletTypes.Call[] memory calls =
            _singleCallWithChecker(address(router), 0, abi.encodeWithSelector(badSel), address(checker), "");

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(IMERAWalletUniswapV2SlippageErrors.UnsupportedRouterCall.selector, badSel)
        );
        wallet.executeTransaction(calls, 1);
    }

    function test_StaleOracle_Reverts() public {
        router.setBadRate(false);
        vm.prank(emergency);
        feedA.setUpdatedAt(block.timestamp - 4000);

        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](2);
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
            checker: address(checker),
            checkerData: ""
        });

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletUniswapV2SlippageErrors.StaleOraclePrice.selector, address(tokenA), block.timestamp - 4000
            )
        );
        wallet.executeTransaction(calls, 1);
    }

    function test_PauseAgent_Pause_BlocksHooksWithEnforcedPause() public {
        vm.prank(pauseAgent);
        checker.pause();

        vm.prank(primary);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        wallet.executeTransaction(_approveAndSwapCalls(), 42);
    }

    function test_Outsider_CannotPause() public {
        vm.prank(outsider);
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SlippageNotPauseAuthorized.selector);
        checker.pause();
    }

    function test_PauseAgent_CannotUnpause() public {
        vm.prank(pauseAgent);
        checker.pause();

        vm.prank(pauseAgent);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, pauseAgent));
        checker.unpause();
    }

    function test_Constructor_InvalidBpsReverts() public {
        uint256 bps = checker.BPS();
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SlippageInvalidDeviationBps.selector);
        new MERAWalletUniswapV2OracleSlippageChecker(
            emergency, bps, DEFAULT_MAX_ORACLE_STALE_SECONDS, DEFAULT_REQUIRE_ROUTER_ALLOWLIST
        );
    }

    function test_Owner_Unpause_AfterAgentPause_SwapSucceeds() public {
        vm.prank(pauseAgent);
        checker.pause();

        vm.prank(emergency);
        checker.unpause();

        router.setBadRate(false);
        vm.prank(primary);
        wallet.executeTransaction(_approveAndSwapCalls(), 42);
    }

    function test_Constructor_InvalidStaleReverts() public {
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SlippageInvalidStaleSeconds.selector);
        new MERAWalletUniswapV2OracleSlippageChecker(emergency, 100, 0, true);
    }

    function test_SetAllowedRouters_LengthMismatch_Reverts() public {
        address[] memory routers = new address[](2);
        routers[0] = address(0x1);
        routers[1] = address(0x2);
        bool[] memory allowed = new bool[](1);
        allowed[0] = true;
        vm.prank(emergency);
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SlippageArrayLengthMismatch.selector);
        checker.setAllowedRouters(routers, allowed);
    }

    function test_SetPauseAgents_LengthMismatch_Reverts() public {
        address[] memory agents = new address[](2);
        agents[0] = address(0x1);
        agents[1] = address(0x2);
        bool[] memory allowed = new bool[](1);
        allowed[0] = true;
        vm.prank(emergency);
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SlippageArrayLengthMismatch.selector);
        checker.setPauseAgents(agents, allowed);
    }

    function test_SetPauseAgents_ZeroAgent_Reverts() public {
        address[] memory agents = new address[](1);
        agents[0] = address(0);
        bool[] memory allowed = new bool[](1);
        allowed[0] = true;
        vm.prank(emergency);
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SlippageInvalidAddress.selector);
        checker.setPauseAgents(agents, allowed);
    }

    function test_ApplyConfig_NonZeroBpsAndStale_UsedInSwap() public {
        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg =
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({
                assetWhitelist: address(0),
                maxOracleNegativeDeviationBps: 200,
                maxOracleStaleSeconds: 7200,
                whitelistRouter: address(0)
            });
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), true, abi.encode(cfg)));
        router.setBadRate(false);
        vm.prank(primary);
        wallet.executeTransaction(_approveAndSwapCalls(), 98001);
    }

    function test_ApplyConfig_BpsTooHigh_Reverts() public {
        uint256 bps = checker.BPS();
        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg =
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({
                assetWhitelist: address(0),
                maxOracleNegativeDeviationBps: bps,
                maxOracleStaleSeconds: 0,
                whitelistRouter: address(0)
            });
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SlippageInvalidDeviationBps.selector);
        checker.applyConfig(abi.encode(cfg));
    }

    function test_CheckAfter_InactiveSnapshot_ReturnsEarly() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        MERAWalletTypes.Call memory call = MERAWalletTypes.Call({
            target: address(router),
            value: 0,
            data: _swapCallData(1 ether, 0),
            checker: address(checker),
            checkerData: ""
        });
        checker.checkAfter(call, bytes32(uint256(9999)), 0);
    }

    function test_SnapshotLoad_Inactive_ReturnsEmptySnapshot() public {
        SlippageSnapshotHarness h = new SlippageSnapshotHarness();

        MERAWalletUniswapV2SlippageTypes.Snapshot memory snapshot = h.load(bytes32(uint256(77)));

        assertFalse(snapshot.active);
        assertEq(snapshot.tokenIn, address(0));
    }

    function test_SnapshotLoad_NonEth_LoadsBothErc20Balances() public {
        SlippageSnapshotHarness h = new SlippageSnapshotHarness();
        MERAWalletUniswapV2SlippageTypes.Snapshot memory stored = MERAWalletUniswapV2SlippageTypes.Snapshot({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            priceFeedTokenIn: address(feedA),
            priceFeedTokenOut: address(feedB),
            erc20BalanceTokenInBefore: 11,
            erc20BalanceTokenOutBefore: 22,
            nativeEthBalanceBefore: 0,
            ethIn: false,
            ethOut: false,
            active: true
        });

        MERAWalletUniswapV2SlippageTypes.Snapshot memory loaded = h.storeAndLoad(bytes32(uint256(78)), stored);

        assertTrue(loaded.active);
        assertFalse(loaded.ethIn);
        assertFalse(loaded.ethOut);
        assertEq(loaded.erc20BalanceTokenInBefore, 11);
        assertEq(loaded.erc20BalanceTokenOutBefore, 22);
    }

    function test_SnapshotLoad_EthIn_SkipsInputErc20AndLoadsEthBalance() public {
        SlippageSnapshotHarness h = new SlippageSnapshotHarness();
        MERAWalletUniswapV2SlippageTypes.Snapshot memory stored = MERAWalletUniswapV2SlippageTypes.Snapshot({
            tokenIn: address(weth),
            tokenOut: address(tokenB),
            priceFeedTokenIn: address(feedA),
            priceFeedTokenOut: address(feedB),
            erc20BalanceTokenInBefore: 11,
            erc20BalanceTokenOutBefore: 22,
            nativeEthBalanceBefore: 33,
            ethIn: true,
            ethOut: false,
            active: true
        });

        MERAWalletUniswapV2SlippageTypes.Snapshot memory loaded = h.storeAndLoad(bytes32(uint256(79)), stored);

        assertTrue(loaded.ethIn);
        assertFalse(loaded.ethOut);
        assertEq(loaded.erc20BalanceTokenInBefore, 0);
        assertEq(loaded.erc20BalanceTokenOutBefore, 22);
        assertEq(loaded.nativeEthBalanceBefore, 33);
    }

    function test_SnapshotLoad_EthOut_SkipsOutputErc20AndLoadsEthBalance() public {
        SlippageSnapshotHarness h = new SlippageSnapshotHarness();
        MERAWalletUniswapV2SlippageTypes.Snapshot memory stored = MERAWalletUniswapV2SlippageTypes.Snapshot({
            tokenIn: address(tokenA),
            tokenOut: address(weth),
            priceFeedTokenIn: address(feedA),
            priceFeedTokenOut: address(feedB),
            erc20BalanceTokenInBefore: 11,
            erc20BalanceTokenOutBefore: 22,
            nativeEthBalanceBefore: 44,
            ethIn: false,
            ethOut: true,
            active: true
        });

        MERAWalletUniswapV2SlippageTypes.Snapshot memory loaded = h.storeAndLoad(bytes32(uint256(80)), stored);

        assertFalse(loaded.ethIn);
        assertTrue(loaded.ethOut);
        assertEq(loaded.erc20BalanceTokenInBefore, 11);
        assertEq(loaded.erc20BalanceTokenOutBefore, 0);
        assertEq(loaded.nativeEthBalanceBefore, 44);
    }

    function test_CheckBefore_ZeroTokenIn_Reverts() public {
        address[] memory path = new address[](2);
        path[0] = address(0);
        path[1] = address(tokenB);
        bytes memory swapData = abi.encodeWithSelector(
            MockUniV2Router02.swapExactTokensForTokens.selector, 1 ether, 0, path, address(wallet), block.timestamp + 1
        );
        MERAWalletTypes.Call memory call = MERAWalletTypes.Call({
            target: address(router), value: 0, data: swapData, checker: address(checker), checkerData: ""
        });
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SlippageInvalidAddress.selector);
        checker.checkBefore(call, bytes32(0), 0);
    }

    function test_AssetWhitelist_TokenInNotAllowed_Reverts() public {
        MERAWalletAssetWhiteList wl = new MERAWalletAssetWhiteList(emergency);
        address[] memory assets = new address[](1);
        assets[0] = address(tokenB);
        bool[] memory allowed = new bool[](1);
        allowed[0] = true;
        address[] memory srcAssets = new address[](1);
        srcAssets[0] = address(tokenB);
        address[] memory srcFeeds = new address[](1);
        srcFeeds[0] = address(feedB);
        vm.startPrank(emergency);
        wl.setAllowedAssets(assets, allowed);
        wl.setAssetSources(srcAssets, srcFeeds);
        vm.stopPrank();

        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg =
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({
                assetWhitelist: address(wl),
                maxOracleNegativeDeviationBps: 0,
                maxOracleStaleSeconds: 0,
                whitelistRouter: address(0)
            });
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), true, abi.encode(cfg)));

        // tokenA is not in wl → tokenIn not allowed
        tokenA.mint(address(wallet), 1 ether);
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(IMERAWalletUniswapV2SlippageErrors.AssetNotWhitelisted.selector, address(tokenA), 1)
        );
        wallet.executeTransaction(_approveAndSwapCalls(), 98002);
    }

    function test_NoAssetWhitelist_PriceFeedNotSet_Reverts() public {
        vm.prank(emergency);
        checker.setDefaultAssetWhitelist(address(0));
        // wallet has no per-wallet whitelist and no default → _effectiveAssetWhitelist returns address(0)
        // → _requireAssetsAllowed skips, but _effectivePriceFeed(address(0), tokenIn) reverts
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(IMERAWalletUniswapV2SlippageErrors.PriceFeedNotSet.selector, address(tokenA))
        );
        wallet.executeTransaction(_approveAndSwapCalls(), 98005);
    }

    function test_AssetWhitelistWithNoFeed_PriceFeedNotSet_Reverts() public {
        MERAWalletAssetWhiteList wl = new MERAWalletAssetWhiteList(emergency);
        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);
        bool[] memory allowed = new bool[](2);
        allowed[0] = true;
        allowed[1] = true;
        vm.prank(emergency);
        wl.setAllowedAssets(assets, allowed);
        // No assetSources set → feedAddr = address(0) → PriceFeedNotSet

        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg =
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({
                assetWhitelist: address(wl),
                maxOracleNegativeDeviationBps: 0,
                maxOracleStaleSeconds: 0,
                whitelistRouter: address(0)
            });
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), true, abi.encode(cfg)));

        tokenA.mint(address(wallet), 1 ether);
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(IMERAWalletUniswapV2SlippageErrors.PriceFeedNotSet.selector, address(tokenA))
        );
        wallet.executeTransaction(_approveAndSwapCalls(), 98003);
    }

    function test_OracleAnswerInvalid_Reverts() public {
        feedA.setAnswer(-1);
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(IMERAWalletUniswapV2SlippageErrors.OracleAnswerInvalid.selector, address(tokenA))
        );
        wallet.executeTransaction(_approveAndSwapCalls(), 98004);
    }

    function test_CheckBefore_DataTooShort_Reverts() public {
        MERAWalletTypes.Call memory call = MERAWalletTypes.Call({
            target: address(router), value: 0, data: hex"ab", checker: address(checker), checkerData: ""
        });
        vm.expectRevert(
            abi.encodeWithSelector(IMERAWalletUniswapV2SlippageErrors.UnsupportedRouterCall.selector, bytes4(0))
        );
        checker.checkBefore(call, bytes32(0), 0);
    }

    function test_CheckBefore_PathTooShort_Reverts() public {
        address[] memory path = new address[](1);
        path[0] = address(tokenA);
        bytes memory swapData = abi.encodeWithSelector(
            MockUniV2Router02.swapExactTokensForTokens.selector, 1 ether, 0, path, address(wallet), block.timestamp + 1
        );
        MERAWalletTypes.Call memory call = MERAWalletTypes.Call({
            target: address(router), value: 0, data: swapData, checker: address(checker), checkerData: ""
        });
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.PathTooShort.selector);
        checker.checkBefore(call, bytes32(0), 0);
    }

    function test_CheckBefore_EthInWethMismatch_Reverts() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        bytes4 sel = bytes4(keccak256("swapExactETHForTokens(uint256,address[],address,uint256)"));
        bytes memory swapData = abi.encodeWithSelector(sel, uint256(0), path, address(wallet), block.timestamp + 1);
        MERAWalletTypes.Call memory call = MERAWalletTypes.Call({
            target: address(router), value: 0, data: swapData, checker: address(checker), checkerData: ""
        });
        vm.expectRevert(abi.encodeWithSelector(IMERAWalletUniswapV2SlippageErrors.UnsupportedRouterCall.selector, sel));
        checker.checkBefore(call, bytes32(0), 0);
    }

    function test_CheckBefore_EthOutWethMismatch_Reverts() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        bytes4 sel = bytes4(keccak256("swapExactTokensForETH(uint256,uint256,address[],address,uint256)"));
        bytes memory swapData =
            abi.encodeWithSelector(sel, uint256(1 ether), uint256(0), path, address(wallet), block.timestamp + 1);
        MERAWalletTypes.Call memory call = MERAWalletTypes.Call({
            target: address(router), value: 0, data: swapData, checker: address(checker), checkerData: ""
        });
        vm.expectRevert(abi.encodeWithSelector(IMERAWalletUniswapV2SlippageErrors.UnsupportedRouterCall.selector, sel));
        checker.checkBefore(call, bytes32(0), 0);
    }

    function test_EthInSwap_CheckBefore_StoresEthInputSnapshot() public {
        _allowWethInDefaultWhitelist();

        MERAWalletTypes.Call memory call = _ethInSwapCall();

        vm.deal(address(this), 5 ether);
        checker.checkBefore(call, bytes32(uint256(9996)), 0);
    }

    function test_EthInSwap_CheckAfter_UsesEthInputDelta() public {
        _allowWethInDefaultWhitelist();

        MERAWalletTypes.Call memory call = _ethInSwapCall();
        bytes32 opId = bytes32(uint256(9997));

        vm.deal(address(this), 5 ether);
        checker.checkBefore(call, opId, 0);
        payable(address(0xE71)).transfer(1 ether);
        tokenB.mint(address(this), 1 ether);

        checker.checkAfter(call, opId, 0);
    }

    function test_EthOutSwap_CheckBeforeAfter_CoversSnapshotEthPaths() public {
        // Add weth to default asset whitelist so the ethOut path passes asset checks
        _allowWethInDefaultWhitelist();

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth); // correct WETH at end → ethOut=TRUE, WETH check passes
        bytes4 sel = bytes4(keccak256("swapExactTokensForETH(uint256,uint256,address[],address,uint256)"));
        bytes memory swapData =
            abi.encodeWithSelector(sel, uint256(1 ether), uint256(0), path, address(this), block.timestamp + 1);
        MERAWalletTypes.Call memory call = MERAWalletTypes.Call({
            target: address(router), value: 0, data: swapData, checker: address(checker), checkerData: ""
        });
        bytes32 opId = bytes32(uint256(9995));
        // checkBefore: stores snapshot with ethOut=TRUE, nativeEthBalanceBefore stored (covers storeSnapshot ethIn||ethOut branch)
        checker.checkBefore(call, opId, 0);
        // checkAfter: loads snapshot with ethOut=TRUE (covers loadAndClearSnapshot ethIn||ethOut branch),
        // then amountIn=0 and amountOut=0 since no actual swap happened → InvalidMeasuredAmounts
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.InvalidMeasuredAmounts.selector);
        checker.checkAfter(call, opId, 0);
    }

    function _allowWethInDefaultWhitelist() internal {
        MERAWalletAssetWhiteList dwl = MERAWalletAssetWhiteList(checker.defaultAssetWhitelist());
        address[] memory newAssets = new address[](1);
        newAssets[0] = address(weth);
        bool[] memory newAllowed = new bool[](1);
        newAllowed[0] = true;
        address[] memory newSrcAssets = new address[](1);
        newSrcAssets[0] = address(weth);
        address[] memory newSrcFeeds = new address[](1);
        newSrcFeeds[0] = address(feedA);
        vm.startPrank(emergency);
        dwl.setAllowedAssets(newAssets, newAllowed);
        dwl.setAssetSources(newSrcAssets, newSrcFeeds);
        vm.stopPrank();
    }

    function _ethInSwapCall() internal view returns (MERAWalletTypes.Call memory) {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenB);
        bytes4 sel = bytes4(keccak256("swapExactETHForTokens(uint256,address[],address,uint256)"));
        bytes memory swapData = abi.encodeWithSelector(sel, uint256(0), path, address(this), block.timestamp + 1);
        return MERAWalletTypes.Call({
            target: address(router), value: 1 ether, data: swapData, checker: address(checker), checkerData: ""
        });
    }
}
