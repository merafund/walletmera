// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {MERAWalletThresholdGuardian} from "../src/guardian/MERAWalletThresholdGuardian.sol";

/// @notice Deploys threshold guardian contract. Use its address as WALLET_GUARDIAN for wallet deploy.
contract DeployMERAWalletThresholdGuardian is Script {
    function run() external returns (MERAWalletThresholdGuardian guardian) {
        address initialWallet = vm.envOr("GUARDIAN_INITIAL_WALLET", address(0));
        uint256 threshold = vm.envUint("GUARDIAN_THRESHOLD");
        string memory membersCsv = vm.envString("GUARDIAN_MEMBERS");
        address[] memory members = _parseMembers(membersCsv);

        vm.startBroadcast();
        guardian = new MERAWalletThresholdGuardian(initialWallet, threshold, members);
        vm.stopBroadcast();

        console2.log("MERAWalletThresholdGuardian deployed at:", address(guardian));
    }

    /// @dev Parse comma-separated addresses, e.g. "0xabc...,0xdef...,0x123...".
    function _parseMembers(string memory csv) internal pure returns (address[] memory members) {
        bytes memory data = bytes(csv);
        require(data.length > 0, "empty members");

        uint256 count = 1;
        for (uint256 i = 0; i < data.length; ++i) {
            if (data[i] == ",") {
                count += 1;
            }
        }

        members = new address[](count);
        uint256 start = 0;
        uint256 index = 0;

        for (uint256 i = 0; i <= data.length; ++i) {
            if (i == data.length || data[i] == ",") {
                bytes memory part = new bytes(i - start);
                for (uint256 j = start; j < i; ++j) {
                    part[j - start] = data[j];
                }
                members[index] = vm.parseAddress(string(part));
                index += 1;
                start = i + 1;
            }
        }
    }
}
