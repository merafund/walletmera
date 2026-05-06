// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletAssetWhiteList} from "../src/checkers/whitelists/MERAWalletAssetWhiteList.sol";

/// @notice Deploys `MERAWalletAssetWhiteList`. Set `CHECKER_INITIAL_OWNER` or it defaults to the broadcaster.
contract DeployMERAWalletAssetWhiteList is Script {
    function run() external returns (MERAWalletAssetWhiteList whitelist) {
        vm.startBroadcast();
        address owner = vm.envOr("CHECKER_INITIAL_OWNER", address(0));
        if (owner == address(0)) {
            owner = msg.sender;
        }
        console2.log("Deployer:", msg.sender);
        console2.log("Initial owner:", owner);
        whitelist = new MERAWalletAssetWhiteList(owner);
        vm.stopBroadcast();

        console2.log("MERAWalletAssetWhiteList deployed at:", address(whitelist));
    }
}
