// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {
    MERAWalletERC20ApproveWhitelistCheckerFactory
} from "../src/factories/checkers/MERAWalletERC20ApproveWhitelistCheckerFactory.sol";

/// @notice Deploys `MERAWalletERC20ApproveWhitelistCheckerFactory`.
contract DeployMERAWalletERC20ApproveWhitelistCheckerFactory is Script {
    function run() external returns (MERAWalletERC20ApproveWhitelistCheckerFactory factory) {
        vm.startBroadcast();
        console2.log("Deployer:", msg.sender);
        factory = new MERAWalletERC20ApproveWhitelistCheckerFactory();
        vm.stopBroadcast();

        console2.log("MERAWalletERC20ApproveWhitelistCheckerFactory deployed at:", address(factory));
    }
}
