// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletAssetWhiteListFactory} from "../src/factories/checkers/MERAWalletAssetWhiteListFactory.sol";

/// @notice Deploys `MERAWalletAssetWhiteListFactory`.
contract DeployMERAWalletAssetWhiteListFactory is Script {
    function run() external returns (MERAWalletAssetWhiteListFactory factory) {
        vm.startBroadcast();
        console2.log("Deployer:", msg.sender);
        factory = new MERAWalletAssetWhiteListFactory();
        vm.stopBroadcast();

        console2.log("MERAWalletAssetWhiteListFactory deployed at:", address(factory));
    }
}
