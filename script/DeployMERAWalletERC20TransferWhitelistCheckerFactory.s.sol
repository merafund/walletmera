// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {
    MERAWalletERC20TransferWhitelistCheckerFactory
} from "../src/factories/checkers/MERAWalletERC20TransferWhitelistCheckerFactory.sol";

/// @notice Deploys `MERAWalletERC20TransferWhitelistCheckerFactory`.
contract DeployMERAWalletERC20TransferWhitelistCheckerFactory is Script {
    function run() external returns (MERAWalletERC20TransferWhitelistCheckerFactory factory) {
        vm.startBroadcast();
        console2.log("Deployer:", msg.sender);
        factory = new MERAWalletERC20TransferWhitelistCheckerFactory();
        vm.stopBroadcast();

        console2.log("MERAWalletERC20TransferWhitelistCheckerFactory deployed at:", address(factory));
    }
}
