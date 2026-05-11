// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";
import {IMERAWalletTransactionChecker} from "../interfaces/checkers/IMERAWalletTransactionChecker.sol";
import {IMERAWalletBlacklistErrors} from "./errors/IMERAWalletBlacklistErrors.sol";
import {MERAWalletBlacklistTypes} from "./types/MERAWalletBlacklistTypes.sol";

/// @title MERAWalletTargetBlacklistChecker
/// @notice Global target blocklist with {Ownable-owner} admin only (no emergency / per-wallet applyConfig layer).
contract MERAWalletTargetBlacklistChecker is Ownable, IMERAWalletTransactionChecker, IMERAWalletBlacklistErrors {
    /// @notice Emitted when a target block flag changes.
    event BlockedTargetUpdated(address indexed target, bool blocked, address indexed caller);

    /// @notice Local block flag by target address.
    mapping(address target => bool blocked) public blockedTarget;

    /// @notice Creates a target blacklist checker owned by `initialOwner`.
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Sets the block flag for a single target.
    function setBlockedTarget(address target, bool blocked) external onlyOwner {
        blockedTarget[target] = blocked;
        emit BlockedTargetUpdated(target, blocked, msg.sender);
    }

    /// @notice Batch-sets target block flags.
    function setBlockedTargets(MERAWalletBlacklistTypes.TargetBlockState[] calldata states) external onlyOwner {
        uint256 statesLength = states.length;
        for (uint256 i = 0; i < statesLength;) {
            MERAWalletBlacklistTypes.TargetBlockState calldata state = states[i];
            blockedTarget[state.target] = state.blocked;
            emit BlockedTargetUpdated(state.target, state.blocked, msg.sender);
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
        MERAWalletBlacklistTypes.TargetBlockState[] memory states =
            abi.decode(config, (MERAWalletBlacklistTypes.TargetBlockState[]));
        uint256 statesLength = states.length;
        for (uint256 i = 0; i < statesLength;) {
            MERAWalletBlacklistTypes.TargetBlockState memory state = states[i];
            blockedTarget[state.target] = state.blocked;
            emit BlockedTargetUpdated(state.target, state.blocked, msg.sender);
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
        require(!blockedTarget[target], TargetBlocked(target, callId));
    }

    /// @inheritdoc IMERAWalletTransactionChecker
    function checkAfter(MERAWalletTypes.Call calldata, bytes32, uint256) external override {}
}
