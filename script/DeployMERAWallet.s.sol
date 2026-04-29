// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";

/// @notice Deploys BaseMERAWallet. Set env vars before running (see README).
contract DeployMERAWallet is Script {
    function run() external returns (BaseMERAWallet wallet) {
        address primary = vm.envAddress("WALLET_PRIMARY");
        address backup = vm.envAddress("WALLET_BACKUP");
        address emergency = vm.envAddress("WALLET_EMERGENCY");
        address eip1271Signer = vm.envOr("WALLET_EIP1271_SIGNER", address(0));
        address guardianAddr = vm.envOr("WALLET_GUARDIAN", address(0));

        vm.startBroadcast();
        wallet = new BaseMERAWallet(primary, backup, emergency, eip1271Signer, guardianAddr);
        vm.stopBroadcast();

        console2.log("BaseMERAWallet deployed at:", address(wallet));
    }
}
