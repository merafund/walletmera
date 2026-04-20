// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../../types/MERAWalletTypes.sol";

/// @notice External checker invoked by wallet execution hooks.
interface IMERAWalletTransactionChecker {
    /// @notice Which hooks this checker participates in; fixed per implementation (wallet reads at registration).
    function hookModes() external view returns (bool enableBefore, bool enableAfter);

    /// @param callId 0-based index of `call` in the batch being executed (same for before/after hooks).
    function checkBefore(MERAWalletTypes.Call calldata call, bytes32 operationId, uint256 callId) external;

    /// @param callId 0-based index of `call` in the batch being executed (same for before/after hooks).
    function checkAfter(MERAWalletTypes.Call calldata call, bytes32 operationId, uint256 callId) external;

    /// @notice Opaque on-chain configuration; encoding is implementation-defined.
    /// @dev The MERA wallet may call this with non-empty `config` when whitelisting this checker. Empty `config` is a no-op.
    function applyConfig(bytes calldata config) external;
}
