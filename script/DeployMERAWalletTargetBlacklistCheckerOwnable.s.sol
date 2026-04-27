// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletTargetBlacklistCheckerOwnable} from "../src/checkers/MERAWalletTargetBlacklistCheckerOwnable.sol";

/// @notice Deploys `MERAWalletTargetBlacklistCheckerOwnable`. Set `CHECKER_INITIAL_OWNER` or it defaults to the broadcaster.
contract DeployMERAWalletTargetBlacklistCheckerOwnable is Script {
    function run() external returns (MERAWalletTargetBlacklistCheckerOwnable checker) {
        vm.startBroadcast();
        address owner = vm.envOr("CHECKER_INITIAL_OWNER", address(0));
        if (owner == address(0)) {
            owner = msg.sender;
        }
        console2.log("Deployer:", msg.sender);
        console2.log("Initial owner:", owner);
        checker = new MERAWalletTargetBlacklistCheckerOwnable(owner);
        vm.stopBroadcast();

        console2.log("MERAWalletTargetBlacklistCheckerOwnable deployed at:", address(checker));
    }
}
