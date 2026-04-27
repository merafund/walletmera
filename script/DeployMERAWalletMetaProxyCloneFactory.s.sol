// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {MERAWalletLoginRegistry} from "../src/MERAWalletLoginRegistry.sol";
import {MERAWalletMetaProxyCloneFactory} from "../src/MERAWalletMetaProxyCloneFactory.sol";

/// @notice Deploys the `BaseMERAWallet` implementation and `MERAWalletMetaProxyCloneFactory`.
contract DeployMERAWalletMetaProxyCloneFactory is Script {
    function run()
        external
        returns (
            BaseMERAWallet implementation,
            MERAWalletLoginRegistry registry,
            MERAWalletMetaProxyCloneFactory factory
        )
    {
        vm.startBroadcast();
        address deployer = msg.sender;
        console2.log("Deployer:", deployer);

        implementation = new BaseMERAWallet(address(1), address(2), address(3), address(0), address(0));
        registry = new MERAWalletLoginRegistry(deployer);
        factory = new MERAWalletMetaProxyCloneFactory(address(implementation), address(registry));
        registry.setFactory(address(factory), true);

        vm.stopBroadcast();

        console2.log("BaseMERAWallet implementation deployed at:", address(implementation));
        console2.log("MERAWalletLoginRegistry deployed at:", address(registry));
        console2.log("MERAWalletMetaProxyCloneFactory deployed at:", address(factory));
    }
}
