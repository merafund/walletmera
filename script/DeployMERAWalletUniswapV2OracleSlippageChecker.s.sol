// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletUniswapV2OracleSlippageChecker} from "../src/checkers/MERAWalletUniswapV2OracleSlippageChecker.sol";

/// @notice Deploys `MERAWalletUniswapV2OracleSlippageChecker`.
/// @dev Env: `CHECKER_INITIAL_OWNER` (optional, defaults to broadcaster), `SLIPPAGE_MAX_NEGATIVE_DEVIATION_BPS` (default 100),
///      `SLIPPAGE_MAX_ORACLE_STALE_SECONDS` (default 3600), `SLIPPAGE_SEQUENCER_UPTIME_FEED` (default address(0)),
///      `SLIPPAGE_SEQUENCER_GRACE_PERIOD_SECONDS` (default 3600), `SLIPPAGE_REQUIRE_ROUTER_ALLOWLIST` (default true).
contract DeployMERAWalletUniswapV2OracleSlippageChecker is Script {
    function run() external returns (MERAWalletUniswapV2OracleSlippageChecker checker) {
        uint256 maxNegBps = vm.envOr("SLIPPAGE_MAX_NEGATIVE_DEVIATION_BPS", uint256(100));
        uint256 maxStale = vm.envOr("SLIPPAGE_MAX_ORACLE_STALE_SECONDS", uint256(3600));
        address sequencerUptimeFeed = vm.envOr("SLIPPAGE_SEQUENCER_UPTIME_FEED", address(0));
        uint256 sequencerGracePeriod = vm.envOr("SLIPPAGE_SEQUENCER_GRACE_PERIOD_SECONDS", uint256(3600));
        bool requireRouterAllowlist = vm.envOr("SLIPPAGE_REQUIRE_ROUTER_ALLOWLIST", true);
        require(maxStale != 0, "SLIPPAGE_MAX_ORACLE_STALE_SECONDS must be non-zero");
        require(
            sequencerUptimeFeed == address(0) || sequencerGracePeriod != 0,
            "SLIPPAGE_SEQUENCER_GRACE_PERIOD_SECONDS must be non-zero when feed is set"
        );

        vm.startBroadcast();
        address owner = vm.envOr("CHECKER_INITIAL_OWNER", address(0));
        if (owner == address(0)) {
            owner = msg.sender;
        }
        console2.log("Deployer:", msg.sender);
        console2.log("Initial owner:", owner);
        console2.log("maxOracleNegativeDeviationBps:", maxNegBps);
        console2.log("maxOracleStaleSeconds:", maxStale);
        console2.log("sequencerUptimeFeed:", sequencerUptimeFeed);
        console2.log("sequencerGracePeriodSeconds:", sequencerGracePeriod);
        console2.log("requireRouterAllowlist:", requireRouterAllowlist);
        checker = new MERAWalletUniswapV2OracleSlippageChecker(
            owner, maxNegBps, maxStale, sequencerUptimeFeed, sequencerGracePeriod, requireRouterAllowlist
        );
        vm.stopBroadcast();

        console2.log("MERAWalletUniswapV2OracleSlippageChecker deployed at:", address(checker));
    }
}
