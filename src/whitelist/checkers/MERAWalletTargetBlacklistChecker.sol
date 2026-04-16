// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../../types/MERAWalletTypes.sol";
import {IMERAWalletTransactionChecker} from "../../interfaces/extensions/IMERAWalletTransactionChecker.sol";
import {IMERAWalletBlacklistErrors} from "../errors/IMERAWalletBlacklistErrors.sol";
import {MERAWalletBlacklistTypes} from "../types/MERAWalletBlacklistTypes.sol";

/// @title MERAWalletTargetBlacklistChecker
/// @notice Blocks wallet calls whose `call.target` is marked blocked. Intended only as a required **before** hook:
/// validation runs before the external call; register via `setRequiredChecker` on the wallet (wallet reads `hookModes()`).
contract MERAWalletTargetBlacklistChecker is IMERAWalletTransactionChecker, IMERAWalletBlacklistErrors {
    event EmergencyUpdated(address indexed previousEmergency, address indexed newEmergency, address indexed caller);
    event BlockedTargetUpdated(address indexed target, bool blocked, address indexed caller);

    address public emergency;
    mapping(address target => bool blocked) public blockedTarget;

    constructor(address initialEmergency) {
        require(initialEmergency != address(0), BlacklistInvalidAddress());
        emergency = initialEmergency;
    }

    function setEmergency(address newEmergency) external {
        _onlyEmergency();
        require(newEmergency != address(0), BlacklistInvalidAddress());

        address previousEmergency = emergency;
        emergency = newEmergency;
        emit EmergencyUpdated(previousEmergency, newEmergency, msg.sender);
    }

    function setBlockedTarget(address target, bool blocked) external {
        _onlyEmergency();
        blockedTarget[target] = blocked;
        emit BlockedTargetUpdated(target, blocked, msg.sender);
    }

    function setBlockedTargets(MERAWalletBlacklistTypes.TargetBlockState[] calldata states) external {
        _onlyEmergency();

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
    function hookModes() external pure override returns (bool enableBefore, bool enableAfter) {
        return (true, false);
    }

    function checkBefore(MERAWalletTypes.Call calldata call, bytes32, uint256 callId) external override {
        address target = call.target;
        require(!blockedTarget[target], TargetBlocked(target, callId));
    }

    function checkAfter(MERAWalletTypes.Call calldata, bytes32, uint256) external override {}

    function _onlyEmergency() internal view {
        require(msg.sender == emergency, BlacklistNotEmergency());
    }
}
