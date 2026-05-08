// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {
    MERAWalletUniswapV2OracleSlippageCheckerFactory
} from "../src/factories/checkers/MERAWalletUniswapV2OracleSlippageCheckerFactory.sol";

/// @notice Deploys `MERAWalletUniswapV2OracleSlippageCheckerFactory`.
contract DeployMERAWalletUniswapV2OracleSlippageCheckerFactory is Script {
    function run() external returns (MERAWalletUniswapV2OracleSlippageCheckerFactory factory) {
        vm.startBroadcast();
        console2.log("Deployer:", msg.sender);
        factory = new MERAWalletUniswapV2OracleSlippageCheckerFactory();
        vm.stopBroadcast();

        console2.log("MERAWalletUniswapV2OracleSlippageCheckerFactory deployed at:", address(factory));
    }
}
