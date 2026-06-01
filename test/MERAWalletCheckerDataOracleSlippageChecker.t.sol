// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {
    MERAWalletCheckerDataOracleSlippageChecker
} from "../src/checkers/MERAWalletCheckerDataOracleSlippageChecker.sol";
import {MERAWalletAssetWhiteList} from "../src/checkers/whitelists/MERAWalletAssetWhiteList.sol";
import {MERAWalletUniswapV2SlippageTypes} from "../src/checkers/types/MERAWalletUniswapV2SlippageTypes.sol";
import {IMERAWalletUniswapV2SlippageErrors} from "../src/checkers/errors/IMERAWalletUniswapV2SlippageErrors.sol";
import {MockUniV2Router02} from "./mocks/MockUniV2Router02.sol";
import {MERAWalletSlippageFixture} from "./helpers/MERAWalletSlippageFixture.sol";

contract MERAWalletCheckerDataOracleSlippageCheckerTest is MERAWalletSlippageFixture {
    function setUp() public {
        _setUpSlippageFixture(
            new MERAWalletCheckerDataOracleSlippageChecker(
                emergency,
                DEFAULT_MAX_ORACLE_NEGATIVE_DEVIATION_BPS,
                DEFAULT_MAX_ORACLE_STALE_SECONDS,
                DEFAULT_SEQUENCER_UPTIME_FEED,
                DEFAULT_SEQUENCER_GRACE_PERIOD_SECONDS,
                DEFAULT_REQUIRE_ROUTER_ALLOWLIST
            )
        );

        tokenC.mint(address(router), 1000 ether);
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
            data: abi.encodeWithSelector(UNSUPPORTED_SELECTOR),
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
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), true, abi.encode(cfg)));

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
        MERAWalletCheckerDataOracleSlippageChecker looseChecker = new MERAWalletCheckerDataOracleSlippageChecker(
            emergency,
            DEFAULT_MAX_ORACLE_NEGATIVE_DEVIATION_BPS,
            DEFAULT_MAX_ORACLE_STALE_SECONDS,
            DEFAULT_SEQUENCER_UPTIME_FEED,
            DEFAULT_SEQUENCER_GRACE_PERIOD_SECONDS,
            false
        );
        assertFalse(looseChecker.REQUIRE_ROUTER_ALLOWLIST());

        vm.startPrank(emergency);
        looseChecker.setDefaultAssetWhitelist(checker.defaultAssetWhitelist());
        vm.stopPrank();

        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(checker), false, ""));
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(looseChecker), true, ""));

        bytes memory cd = _checkerData(address(tokenA), address(tokenB), false, false);
        router.setBadRate(false);
        vm.prank(primary);
        wallet.executeTransaction(_approveAndSwapCallsWith(address(looseChecker), cd), 55_001);
    }
}
