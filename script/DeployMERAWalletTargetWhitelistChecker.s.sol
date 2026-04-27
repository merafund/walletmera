// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletTargetWhitelistChecker} from "../src/checkers/MERAWalletTargetWhitelistChecker.sol";

/// @notice Deploys `MERAWalletTargetWhitelistChecker`. Requires `TARGET_CHECKER_EMERGENCY`.
contract DeployMERAWalletTargetWhitelistChecker is Script {
    function run() external returns (MERAWalletTargetWhitelistChecker checker) {
        address emergency = vm.envAddress("TARGET_CHECKER_EMERGENCY");

        vm.startBroadcast();
        console2.log("Deployer:", msg.sender);
        console2.log("Emergency:", emergency);
        checker = new MERAWalletTargetWhitelistChecker(emergency);
        vm.stopBroadcast();

        console2.log("MERAWalletTargetWhitelistChecker deployed at:", address(checker));
    }
}
