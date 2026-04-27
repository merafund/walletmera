// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletERC20ApproveWhitelistChecker} from "../src/checkers/MERAWalletERC20ApproveWhitelistChecker.sol";

/// @notice Deploys `MERAWalletERC20ApproveWhitelistChecker`. Set `CHECKER_INITIAL_OWNER` or it defaults to the broadcaster.
contract DeployMERAWalletERC20ApproveWhitelistChecker is Script {
    function run() external returns (MERAWalletERC20ApproveWhitelistChecker checker) {
        vm.startBroadcast();
        address owner = vm.envOr("CHECKER_INITIAL_OWNER", address(0));
        if (owner == address(0)) {
            owner = msg.sender;
        }
        console2.log("Deployer:", msg.sender);
        console2.log("Initial owner:", owner);
        checker = new MERAWalletERC20ApproveWhitelistChecker(owner);
        vm.stopBroadcast();

        console2.log("MERAWalletERC20ApproveWhitelistChecker deployed at:", address(checker));
    }
}
