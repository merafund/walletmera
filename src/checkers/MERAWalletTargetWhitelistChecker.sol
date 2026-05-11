// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";
import {IMERAWalletTransactionChecker} from "../interfaces/checkers/IMERAWalletTransactionChecker.sol";
import {IMERAWalletWhitelistErrors} from "./errors/IMERAWalletWhitelistErrors.sol";
import {MERAWalletWhitelistTypes} from "./types/MERAWalletWhitelistTypes.sol";

/// @title MERAWalletTargetWhitelistChecker
/// @notice Global target allowlist with {Ownable-owner} admin only (no emergency / per-wallet applyConfig layer).
contract MERAWalletTargetWhitelistChecker is Ownable, IMERAWalletTransactionChecker, IMERAWalletWhitelistErrors {
    /// @notice Emitted when a target allow flag changes.
    event AllowedTargetUpdated(address indexed target, bool allowed, address indexed caller);

    /// @notice Local allow flag by target address.
    mapping(address target => bool allowed) public allowedTarget;

    /// @notice Creates a target whitelist checker owned by `initialOwner`.
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Sets the allow flag for a single target.
    function setAllowedTarget(address target, bool allowed) external onlyOwner {
        allowedTarget[target] = allowed;
        emit AllowedTargetUpdated(target, allowed, msg.sender);
    }

    /// @notice Batch-sets target allow flags.
    function setAllowedTargets(MERAWalletWhitelistTypes.TargetPermission[] calldata permissions) external onlyOwner {
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
    function applyConfig(bytes calldata config) external override onlyOwner {
        if (config.length == 0) {
            return;
        }
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

    /// @inheritdoc IMERAWalletTransactionChecker
    function hookModes() external pure override returns (bool enableBefore, bool enableAfter) {
        return (true, false);
    }

    /// @inheritdoc IMERAWalletTransactionChecker
    function checkBefore(MERAWalletTypes.Call calldata call, bytes32, uint256 callId) external override {
        address target = call.target;
        require(allowedTarget[target], TargetNotAllowed(target, callId));
    }

    /// @inheritdoc IMERAWalletTransactionChecker
    function checkAfter(MERAWalletTypes.Call calldata, bytes32, uint256) external override {}
}
