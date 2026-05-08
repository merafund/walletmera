// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {
    MERAWalletCheckerDataOracleSlippageCheckerFactory
} from "../src/factories/checkers/MERAWalletCheckerDataOracleSlippageCheckerFactory.sol";

/// @notice Deploys `MERAWalletCheckerDataOracleSlippageCheckerFactory`.
contract DeployMERAWalletCheckerDataOracleSlippageCheckerFactory is Script {
    function run() external returns (MERAWalletCheckerDataOracleSlippageCheckerFactory factory) {
        vm.startBroadcast();
        console2.log("Deployer:", msg.sender);
        factory = new MERAWalletCheckerDataOracleSlippageCheckerFactory();
        vm.stopBroadcast();

        console2.log("MERAWalletCheckerDataOracleSlippageCheckerFactory deployed at:", address(factory));
    }
}
