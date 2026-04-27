// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletCreate2Factory} from "../src/MERAWalletCreate2Factory.sol";
import {MERAWalletLoginRegistry} from "../src/MERAWalletLoginRegistry.sol";

/// @notice Deploys `MERAWalletCreate2Factory`. Use Makefile targets and `.env` for RPC and key.
contract DeployMERAWalletCreate2Factory is Script {
    function run() external returns (MERAWalletLoginRegistry registry, MERAWalletCreate2Factory factory) {
        vm.startBroadcast();
        address deployer = msg.sender;
        console2.log("Deployer:", deployer);
        registry = new MERAWalletLoginRegistry(deployer);
        factory = new MERAWalletCreate2Factory(address(registry));
        registry.setFactory(address(factory), true);
        vm.stopBroadcast();

        console2.log("MERAWalletLoginRegistry deployed at:", address(registry));
        console2.log("MERAWalletCreate2Factory deployed at:", address(factory));
    }
}
