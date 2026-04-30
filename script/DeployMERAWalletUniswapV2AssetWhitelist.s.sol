// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletUniswapV2AssetWhitelist} from "../src/checkers/whitelists/MERAWalletUniswapV2AssetWhitelist.sol";

/// @notice Deploys `MERAWalletUniswapV2AssetWhitelist`. Set `CHECKER_INITIAL_OWNER` or it defaults to the broadcaster.
contract DeployMERAWalletUniswapV2AssetWhitelist is Script {
    function run() external returns (MERAWalletUniswapV2AssetWhitelist whitelist) {
        vm.startBroadcast();
        address owner = vm.envOr("CHECKER_INITIAL_OWNER", address(0));
        if (owner == address(0)) {
            owner = msg.sender;
        }
        console2.log("Deployer:", msg.sender);
        console2.log("Initial owner:", owner);
        whitelist = new MERAWalletUniswapV2AssetWhitelist(owner);
        vm.stopBroadcast();

        console2.log("MERAWalletUniswapV2AssetWhitelist deployed at:", address(whitelist));
    }
}
