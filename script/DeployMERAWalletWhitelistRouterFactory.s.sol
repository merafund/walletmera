// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletWhitelistRouterFactory} from "../src/factories/checkers/MERAWalletWhitelistRouterFactory.sol";

/// @notice Deploys `MERAWalletWhitelistRouterFactory`.
contract DeployMERAWalletWhitelistRouterFactory is Script {
    function run() external returns (MERAWalletWhitelistRouterFactory factory) {
        vm.startBroadcast();
        console2.log("Deployer:", msg.sender);
        factory = new MERAWalletWhitelistRouterFactory();
        vm.stopBroadcast();

        console2.log("MERAWalletWhitelistRouterFactory deployed at:", address(factory));
    }
}
