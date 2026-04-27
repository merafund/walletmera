// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletERC20TransferWhitelistChecker} from "../src/checkers/MERAWalletERC20TransferWhitelistChecker.sol";

/// @notice Deploys `MERAWalletERC20TransferWhitelistChecker`. Set `CHECKER_INITIAL_OWNER` or it defaults to the broadcaster.
contract DeployMERAWalletERC20TransferWhitelistChecker is Script {
    function run() external returns (MERAWalletERC20TransferWhitelistChecker checker) {
        vm.startBroadcast();
        address owner = vm.envOr("CHECKER_INITIAL_OWNER", address(0));
        if (owner == address(0)) {
            owner = msg.sender;
        }
        console2.log("Deployer:", msg.sender);
        console2.log("Initial owner:", owner);
        checker = new MERAWalletERC20TransferWhitelistChecker(owner);
        vm.stopBroadcast();

        console2.log("MERAWalletERC20TransferWhitelistChecker deployed at:", address(checker));
    }
}
