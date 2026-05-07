// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletUniswapV2OracleSlippageChecker} from "../src/checkers/MERAWalletUniswapV2OracleSlippageChecker.sol";
import {MERAWalletAssetWhiteList} from "../src/checkers/whitelists/MERAWalletAssetWhiteList.sol";
import {MERAWalletUniswapV2SlippageTypes} from "../src/checkers/types/MERAWalletUniswapV2SlippageTypes.sol";
import {IMERAWalletUniswapV2SlippageErrors} from "../src/checkers/errors/IMERAWalletUniswapV2SlippageErrors.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {MockUniV2Router02} from "./mocks/MockUniV2Router02.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

contract MERAWalletUniswapV2OracleSlippageCheckerTest is Test {
    uint256 private _optCfgSalt = 10_000;

    uint256 internal primaryPk = 0xA11CE;
    address internal primary = vm.addr(primaryPk);
    address internal emergency = vm.addr(0xE911);
    address internal pauseAgent = address(0xBEEF);
    address internal outsider = address(0xCAFE);

    BaseMERAWallet internal wallet;
    MERAWalletUniswapV2OracleSlippageChecker internal checker;
    ERC20Mock internal tokenA;
    ERC20Mock internal tokenB;
    ERC20Mock internal weth;
    MockUniV2Router02 internal router;
    MockAggregatorV3 internal feedA;
    MockAggregatorV3 internal feedB;

    function _mkWl(address checkerAddr, bool allowed, bytes memory config)
        internal
        pure
        returns (MERAWalletTypes.OptionalCheckerUpdate[] memory u)
    {
        u = new MERAWalletTypes.OptionalCheckerUpdate[](1);
        u[0] = MERAWalletTypes.OptionalCheckerUpdate({checker: checkerAddr, allowed: allowed, config: config});
    }

    function setUp() public {
        vm.warp(1_000_000);

        wallet = new BaseMERAWallet(primary, vm.addr(0xB0B), emergency, address(0), address(0));
        checker = new MERAWalletUniswapV2OracleSlippageChecker(emergency, 100, 3600);
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
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

        address[] memory agents = new address[](1);
        agents[0] = pauseAgent;
        bool[] memory agentAllowed = new bool[](1);
        agentAllowed[0] = true;
        checker.setPauseAgents(agents, agentAllowed);
        vm.stopPrank();

        tokenA.mint(address(wallet), 10 ether);
        tokenB.mint(address(router), 1000 ether);
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
        bytes32 opId = wallet.proposeTransaction(_singleCall(address(wallet), 0, data), salt);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(opId);
        vm.warp(executeAfter);
        wallet.executePending(_singleCall(address(wallet), 0, data), salt);
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

    function _approveAndSwapCalls() internal view returns (MERAWalletTypes.Call[] memory calls) {
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
            checker: address(checker),
            checkerData: ""
        });
    }

    function _swapCallData(uint256 amountIn, uint256 amountOutMin) internal view returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        return abi.encodeWithSelector(
            MockUniV2Router02.swapExactTokensForTokens.selector,
            amountIn,
            amountOutMin,
            path,
            address(wallet),
            block.timestamp + 1
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

        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg =
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({assetWhitelist: address(aw)});
        _setOptionalCheckers(_mkWl(address(checker), true, abi.encode(cfg)));

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
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({assetWhitelist: address(aw)});
        _setOptionalCheckers(_mkWl(address(checker), true, abi.encode(cfg)));

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
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({assetWhitelist: address(aw)});
        _setOptionalCheckers(_mkWl(address(checker), true, abi.encode(cfg)));

        router.setBadRate(false);

        vm.prank(primary);
        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SwapWorseThanOracle.selector);
        wallet.executeTransaction(_approveAndSwapCalls(), 45);
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

    function test_UnsupportedSelector_Reverts() public {
        bytes4 badSel = 0xdeadbeef;
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: address(router),
            value: 0,
            data: abi.encodeWithSelector(badSel),
            checker: address(checker),
            checkerData: ""
        });

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

    function test_Owner_Unpause_AfterAgentPause_SwapSucceeds() public {
        vm.prank(pauseAgent);
        checker.pause();

        vm.prank(emergency);
        checker.unpause();

        router.setBadRate(false);
        vm.prank(primary);
        wallet.executeTransaction(_approveAndSwapCalls(), 42);
    }
}
