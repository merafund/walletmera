// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../../types/MERAWalletTypes.sol";
import {IMERAWalletTransactionChecker} from "../../interfaces/extensions/IMERAWalletTransactionChecker.sol";
import {IMERAWalletWhitelistErrors} from "../errors/IMERAWalletWhitelistErrors.sol";
import {MERAWalletWhitelistTypes} from "../types/MERAWalletWhitelistTypes.sol";

contract MERAWalletTargetWhitelistChecker is IMERAWalletTransactionChecker, IMERAWalletWhitelistErrors {
    event EmergencyUpdated(address indexed previousEmergency, address indexed newEmergency, address indexed caller);
    event AllowedTargetUpdated(address indexed target, bool allowed, address indexed caller);

    address public emergency;
    mapping(address target => bool allowed) public allowedTarget;

    constructor(address initialEmergency) {
        require(initialEmergency != address(0), WhitelistInvalidAddress());
        emergency = initialEmergency;
    }

    function setEmergency(address newEmergency) external {
        _onlyEmergency();
        require(newEmergency != address(0), WhitelistInvalidAddress());

        address previousEmergency = emergency;
        emergency = newEmergency;
        emit EmergencyUpdated(previousEmergency, newEmergency, msg.sender);
    }

    function setAllowedTarget(address target, bool allowed) external {
        _onlyEmergency();
        allowedTarget[target] = allowed;
        emit AllowedTargetUpdated(target, allowed, msg.sender);
    }

    function setAllowedTargets(MERAWalletWhitelistTypes.TargetPermission[] calldata permissions) external {
        _onlyEmergency();

        uint256 permissionsLength = permissions.length;
        for (uint256 i = 0; i < permissionsLength;) {
            MERAWalletWhitelistTypes.TargetPermission calldata permission = permissions[i];
            allowedTarget[permission.target] = permission.allowed;
            emit AllowedTargetUpdated(permission.target, permission.allowed, msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    function checkBefore(MERAWalletTypes.Call[] memory calls, bytes32) external view override {
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength;) {
            address target = calls[i].target;
            require(allowedTarget[target], TargetNotAllowed(target, i));
            unchecked {
                ++i;
            }
        }
    }

    function checkAfter(MERAWalletTypes.Call[] memory, bytes32) external pure override {}

    function _onlyEmergency() internal view {
        require(msg.sender == emergency, WhitelistNotEmergency());
    }
}
