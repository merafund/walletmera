// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {
    MERAWalletERC20RecipientWhitelistFactory
} from "../src/factories/checkers/MERAWalletERC20RecipientWhitelistFactory.sol";

/// @notice Deploys `MERAWalletERC20RecipientWhitelistFactory`.
contract DeployMERAWalletERC20RecipientWhitelistFactory is Script {
    function run() external returns (MERAWalletERC20RecipientWhitelistFactory factory) {
        vm.startBroadcast();
        console2.log("Deployer:", msg.sender);
        factory = new MERAWalletERC20RecipientWhitelistFactory();
        vm.stopBroadcast();

        console2.log("MERAWalletERC20RecipientWhitelistFactory deployed at:", address(factory));
    }
}
