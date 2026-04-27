// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletTargetBlacklistChecker} from "../src/checkers/MERAWalletTargetBlacklistChecker.sol";

/// @notice Deploys `MERAWalletTargetBlacklistChecker`. Requires `TARGET_CHECKER_EMERGENCY`; optional `TARGET_CHECKER_MERA_WALLET`.
contract DeployMERAWalletTargetBlacklistChecker is Script {
    function run() external returns (MERAWalletTargetBlacklistChecker checker) {
        address emergency = vm.envAddress("TARGET_CHECKER_EMERGENCY");
        address meraWallet = vm.envOr("TARGET_CHECKER_MERA_WALLET", address(0));

        vm.startBroadcast();
        console2.log("Deployer:", msg.sender);
        console2.log("Emergency:", emergency);
        console2.log("MERA_WALLET:", meraWallet);
        checker = new MERAWalletTargetBlacklistChecker(emergency, meraWallet);
        vm.stopBroadcast();

        console2.log("MERAWalletTargetBlacklistChecker deployed at:", address(checker));
    }
}
