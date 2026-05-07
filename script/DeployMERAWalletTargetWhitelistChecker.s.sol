// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletTargetWhitelistChecker} from "../src/checkers/MERAWalletTargetWhitelistChecker.sol";

/// @notice Deploys `MERAWalletTargetWhitelistChecker`. Set `CHECKER_INITIAL_OWNER` or it defaults to the broadcaster.
contract DeployMERAWalletTargetWhitelistChecker is Script {
    function run() external returns (MERAWalletTargetWhitelistChecker checker) {
        vm.startBroadcast();
        address owner = vm.envOr("CHECKER_INITIAL_OWNER", address(0));
        if (owner == address(0)) {
            owner = msg.sender;
        }
        console2.log("Deployer:", msg.sender);
        console2.log("Initial owner:", owner);
        checker = new MERAWalletTargetWhitelistChecker(owner);
        vm.stopBroadcast();

        console2.log("MERAWalletTargetWhitelistChecker deployed at:", address(checker));
    }
}
