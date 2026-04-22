// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletCreate2Factory} from "../src/MERAWalletCreate2Factory.sol";

/// @notice Deploys `MERAWalletCreate2Factory` (no constructor args). Use Makefile targets and `.env` for RPC and key.
contract DeployMERAWalletCreate2Factory is Script {
    function run() external returns (MERAWalletCreate2Factory factory) {
        vm.startBroadcast();
        factory = new MERAWalletCreate2Factory();
        vm.stopBroadcast();

        console2.log("MERAWalletCreate2Factory deployed at:", address(factory));
    }
}
