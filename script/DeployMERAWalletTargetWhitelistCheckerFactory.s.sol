// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {
    MERAWalletTargetWhitelistCheckerFactory
} from "../src/factories/checkers/MERAWalletTargetWhitelistCheckerFactory.sol";

/// @notice Deploys `MERAWalletTargetWhitelistCheckerFactory`.
contract DeployMERAWalletTargetWhitelistCheckerFactory is Script {
    function run() external returns (MERAWalletTargetWhitelistCheckerFactory factory) {
        vm.startBroadcast();
        console2.log("Deployer:", msg.sender);
        factory = new MERAWalletTargetWhitelistCheckerFactory();
        vm.stopBroadcast();

        console2.log("MERAWalletTargetWhitelistCheckerFactory deployed at:", address(factory));
    }
}
