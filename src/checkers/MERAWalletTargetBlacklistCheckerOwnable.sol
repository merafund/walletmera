// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";
import {IMERAWalletTransactionChecker} from "../interfaces/extensions/IMERAWalletTransactionChecker.sol";
import {IMERAWalletBlacklistErrors} from "./errors/IMERAWalletBlacklistErrors.sol";
import {MERAWalletBlacklistTypes} from "./types/MERAWalletBlacklistTypes.sol";

/// @title MERAWalletTargetBlacklistCheckerOwnable
/// @notice Same blocking semantics as {MERAWalletTargetBlacklistChecker} but admin is {Ownable-owner} only (no emergency / bound wallet).
contract MERAWalletTargetBlacklistCheckerOwnable is Ownable, IMERAWalletTransactionChecker, IMERAWalletBlacklistErrors {
    event BlockedTargetUpdated(address indexed target, bool blocked, address indexed caller);

    mapping(address target => bool blocked) public blockedTarget;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setBlockedTarget(address target, bool blocked) external onlyOwner {
        blockedTarget[target] = blocked;
        emit BlockedTargetUpdated(target, blocked, msg.sender);
    }

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

    function checkBefore(MERAWalletTypes.Call calldata call, bytes32, uint256 callId) external override {
        address target = call.target;
        require(!blockedTarget[target], TargetBlocked(target, callId));
    }

    function checkAfter(MERAWalletTypes.Call calldata, bytes32, uint256) external override {}
}
