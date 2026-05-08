// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {
    MERAWalletTargetBlacklistCheckerFactory
} from "../src/factories/checkers/MERAWalletTargetBlacklistCheckerFactory.sol";

/// @notice Deploys `MERAWalletTargetBlacklistCheckerFactory`.
contract DeployMERAWalletTargetBlacklistCheckerFactory is Script {
    function run() external returns (MERAWalletTargetBlacklistCheckerFactory factory) {
        vm.startBroadcast();
        console2.log("Deployer:", msg.sender);
        factory = new MERAWalletTargetBlacklistCheckerFactory();
        vm.stopBroadcast();

        console2.log("MERAWalletTargetBlacklistCheckerFactory deployed at:", address(factory));
    }
}
