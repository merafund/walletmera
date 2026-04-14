// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletFull} from "../src/extensions/MERAWalletFull.sol";

/// @notice Deploys MERAWalletFull. Set env vars before running (see README).
contract DeployMERAWallet is Script {
    function run() external returns (MERAWalletFull wallet) {
        address primary = vm.envAddress("WALLET_PRIMARY");
        address backup = vm.envAddress("WALLET_BACKUP");
        address emergency = vm.envAddress("WALLET_EMERGENCY");
        address eip1271Signer = vm.envOr("WALLET_EIP1271_SIGNER", address(0));

        vm.startBroadcast();
        wallet = new MERAWalletFull(primary, backup, emergency, eip1271Signer);
        vm.stopBroadcast();

        console2.log("MERAWalletFull deployed at:", address(wallet));
    }
}
