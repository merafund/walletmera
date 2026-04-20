// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";
import {IMERAWalletTransactionChecker} from "../interfaces/extensions/IMERAWalletTransactionChecker.sol";
import {IMERAWalletWhitelistErrors} from "./errors/IMERAWalletWhitelistErrors.sol";
import {MERAWalletWhitelistTypes} from "./types/MERAWalletWhitelistTypes.sol";

contract MERAWalletTargetWhitelistChecker is IMERAWalletTransactionChecker, IMERAWalletWhitelistErrors {
    event EmergencyUpdated(address indexed previousEmergency, address indexed newEmergency, address indexed caller);
    event AllowedTargetUpdated(address indexed target, bool allowed, address indexed caller);

    address public emergency;
    /// @dev Wallet authorized to call {applyConfig} together with {emergency}; may be zero for emergency-only config.
    address public immutable MERA_WALLET;

    mapping(address target => bool allowed) public allowedTarget;

    constructor(address initialEmergency, address initialMeraWallet) {
        require(initialEmergency != address(0), WhitelistInvalidAddress());
        emergency = initialEmergency;
        MERA_WALLET = initialMeraWallet;
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

    /// @inheritdoc IMERAWalletTransactionChecker
    function applyConfig(bytes calldata config) external override {
        if (config.length == 0) {
            return;
        }
        _onlyEmergencyOrMeraWallet();
        MERAWalletWhitelistTypes.TargetPermission[] memory permissions =
            abi.decode(config, (MERAWalletWhitelistTypes.TargetPermission[]));
        uint256 permissionsLength = permissions.length;
        for (uint256 i = 0; i < permissionsLength;) {
            MERAWalletWhitelistTypes.TargetPermission memory permission = permissions[i];
            allowedTarget[permission.target] = permission.allowed;
            emit AllowedTargetUpdated(permission.target, permission.allowed, msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    function hookModes() external pure override returns (bool enableBefore, bool enableAfter) {
        return (true, false);
    }

    function checkBefore(MERAWalletTypes.Call calldata call, bytes32, uint256 callId) external override {
        address target = call.target;
        require(allowedTarget[target], TargetNotAllowed(target, callId));
    }

    function checkAfter(MERAWalletTypes.Call calldata, bytes32, uint256) external override {}

    function _onlyEmergency() internal view {
        require(msg.sender == emergency, WhitelistNotEmergency());
    }

    /// @dev Allows `emergency` (e.g. timelock) or the bound MERA wallet (when registering via `setWhitelistedChecker`).
    function _onlyEmergencyOrMeraWallet() internal view {
        if (msg.sender == emergency) {
            return;
        }
        require(msg.sender == MERA_WALLET && MERA_WALLET != address(0), WhitelistConfigNotAuthorized());
    }
}
