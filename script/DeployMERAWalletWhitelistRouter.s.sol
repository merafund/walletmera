// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletWhitelistRouter} from "../src/checkers/whitelists/MERAWalletWhitelistRouter.sol";

/// @notice Deploys `MERAWalletWhitelistRouter`. Set `CHECKER_INITIAL_OWNER` or it defaults to the broadcaster.
contract DeployMERAWalletWhitelistRouter is Script {
    function run() external returns (MERAWalletWhitelistRouter router) {
        vm.startBroadcast();
        address owner = vm.envOr("CHECKER_INITIAL_OWNER", address(0));
        if (owner == address(0)) {
            owner = msg.sender;
        }
        console2.log("Deployer:", msg.sender);
        console2.log("Initial owner:", owner);
        router = new MERAWalletWhitelistRouter(owner);
        vm.stopBroadcast();

        console2.log("MERAWalletWhitelistRouter deployed at:", address(router));
    }
}
