// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletUniswapV2OracleSlippageChecker} from "../src/checkers/MERAWalletUniswapV2OracleSlippageChecker.sol";
import {MERAWalletUniswapV2AssetWhitelist} from "../src/checkers/MERAWalletUniswapV2AssetWhitelist.sol";
import {MERAWalletUniswapV2SlippageTypes} from "../src/checkers/types/MERAWalletUniswapV2SlippageTypes.sol";
import {IMERAWalletUniswapV2SlippageErrors} from "../src/checkers/errors/IMERAWalletUniswapV2SlippageErrors.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {MockUniV2Router02} from "./mocks/MockUniV2Router02.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

contract MERAWalletUniswapV2OracleSlippageCheckerTest is Test {
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
        wallet.setOptionalCheckers(_mkWl(address(0), true, ""));
        wallet.setOptionalCheckers(_mkWl(address(checker), true, ""));
        address[] memory routers = new address[](1);
        routers[0] = address(router);
        bool[] memory routerAllowed = new bool[](1);
        routerAllowed[0] = true;
        checker.setAllowedRouters(routers, routerAllowed);

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        address[] memory feeds = new address[](2);
        feeds[0] = address(feedA);
        feeds[1] = address(feedB);
        checker.setTokenPriceFeeds(tokens, feeds);

        address[] memory agents = new address[](1);
        agents[0] = pauseAgent;
        bool[] memory agentAllowed = new bool[](1);
        agentAllowed[0] = true;
        checker.setPauseAgents(agents, agentAllowed);
        vm.stopPrank();

        tokenA.mint(address(wallet), 10 ether);
        tokenB.mint(address(router), 1000 ether);
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
        MERAWalletUniswapV2AssetWhitelist aw = new MERAWalletUniswapV2AssetWhitelist(emergency);
        address[] memory assets = new address[](1);
        assets[0] = address(tokenA);
        bool[] memory allowed = new bool[](1);
        allowed[0] = true;
        vm.prank(emergency);
        aw.setAllowedAssets(assets, allowed);

        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg =
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({assetWhitelist: address(aw)});
        vm.prank(emergency);
        wallet.setOptionalCheckers(_mkWl(address(checker), true, abi.encode(cfg)));

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
        MERAWalletUniswapV2AssetWhitelist aw = new MERAWalletUniswapV2AssetWhitelist(emergency);
        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);
        bool[] memory allowed = new bool[](2);
        allowed[0] = true;
        allowed[1] = true;
        vm.startPrank(emergency);
        aw.setAllowedAssets(assets, allowed);
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
