// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";

/// @notice Types for MERA Uniswap V2 oracle slippage checker configuration.
library MERAWalletUniswapV2SlippageTypes {
    using SlotDerivation for bytes32;
    using TransientSlot for bytes32;
    using TransientSlot for TransientSlot.AddressSlot;
    using TransientSlot for TransientSlot.Uint256Slot;

    bytes32 private constant _SNAPSHOTS_TSTORE_ROOT = keccak256("mera.wallet.univ2.slippage.snapshot");
    uint256 private constant _ADDRESS_MASK = (uint256(1) << 160) - 1;
    uint256 private constant _FLAG_ETH_IN = uint256(1) << 160;
    uint256 private constant _FLAG_ETH_OUT = uint256(1) << 161;
    uint256 private constant _FLAG_ACTIVE = uint256(1) << 162;

    /// @notice ABI payload for {IMERAWalletTransactionChecker-applyConfig} on the slippage checker.
    struct UniswapV2SlippageCheckerConfig {
        /// @notice Optional ERC20 allowlist contract; address(0) disables per-wallet asset gating for that wallet.
        address assetWhitelist;
        /// @notice Optional per-wallet max oracle shortfall in BPS; 0 means fallback to checker default.
        uint256 maxOracleNegativeDeviationBps;
        /// @notice Optional per-wallet max Chainlink staleness in seconds; 0 means fallback to checker default.
        uint256 maxOracleStaleSeconds;
        /// @notice Optional route registry checked before default asset whitelist when `assetWhitelist` is zero.
        address whitelistRouter;
    }

    /// @notice ABI payload for per-call checker data when swap endpoints must not be decoded from `call.data`.
    struct CheckerDataSlippageCheckData {
        /// @notice Input asset measured by the checker.
        address tokenIn;
        /// @notice Output asset measured by the checker.
        address tokenOut;
        /// @notice Whether the input side is native ETH.
        bool ethIn;
        /// @notice Whether the output side is native ETH.
        bool ethOut;
    }

    /// @notice Swap snapshot recorded in the before-hook and read in the after-hook for oracle comparison.
    struct Snapshot {
        /// @notice Input token address, or wrapped/native marker depending on checker path.
        address tokenIn;
        /// @notice Output token address, or wrapped/native marker depending on checker path.
        address tokenOut;
        /// @notice Token whose feed prices `tokenIn`.
        address priceFeedTokenIn;
        /// @notice Token whose feed prices `tokenOut`.
        address priceFeedTokenOut;
        /// @notice Wallet ERC20 input-token balance before the swap.
        uint256 erc20BalanceTokenInBefore;
        /// @notice Wallet ERC20 output-token balance before the swap.
        uint256 erc20BalanceTokenOutBefore;
        /// @notice Wallet native ETH balance before the swap.
        uint256 nativeEthBalanceBefore;
        /// @notice Whether the input side is native ETH.
        bool ethIn;
        /// @notice Whether the output side is native ETH.
        bool ethOut;
        /// @notice Whether the snapshot exists for the current transaction.
        bool active;
    }

    /// @notice Store a transient swap snapshot under `key`.
    /// @param key Snapshot key derived from wallet, operation id, and call id.
    /// @param snapshot Snapshot data to store until the after-hook reads it.
    function storeSnapshot(bytes32 key, Snapshot memory snapshot) internal {
        bytes32 baseSlot = _snapshotBaseSlot(key);
        baseSlot.offset(0).asUint256()
            .tstore(_packTokenInAndFlags(snapshot.tokenIn, snapshot.ethIn, snapshot.ethOut, snapshot.active));
        baseSlot.offset(1).asAddress().tstore(snapshot.tokenOut);
        baseSlot.offset(2).asAddress().tstore(snapshot.priceFeedTokenIn);
        baseSlot.offset(3).asAddress().tstore(snapshot.priceFeedTokenOut);
        if (!snapshot.ethIn) {
            baseSlot.offset(4).asUint256().tstore(snapshot.erc20BalanceTokenInBefore);
        }
        if (!snapshot.ethOut) {
            baseSlot.offset(5).asUint256().tstore(snapshot.erc20BalanceTokenOutBefore);
        }
        if (snapshot.ethIn || snapshot.ethOut) {
            baseSlot.offset(6).asUint256().tstore(snapshot.nativeEthBalanceBefore);
        }
    }

    /// @notice Load a transient swap snapshot without clearing it.
    /// @param key Snapshot key derived from wallet, operation id, and call id.
    /// @return snapshot Snapshot data, with `active == false` when no snapshot is present.
    function loadSnapshot(bytes32 key) internal view returns (Snapshot memory snapshot) {
        bytes32 baseSlot = _snapshotBaseSlot(key);
        uint256 packedTokenInAndFlags = baseSlot.offset(0).asUint256().tload();
        snapshot.active = packedTokenInAndFlags & _FLAG_ACTIVE != 0;
        if (!snapshot.active) {
            return snapshot;
        }

        snapshot.tokenIn = address(uint160(packedTokenInAndFlags & _ADDRESS_MASK));
        snapshot.tokenOut = baseSlot.offset(1).asAddress().tload();
        snapshot.priceFeedTokenIn = baseSlot.offset(2).asAddress().tload();
        snapshot.priceFeedTokenOut = baseSlot.offset(3).asAddress().tload();
        snapshot.ethIn = packedTokenInAndFlags & _FLAG_ETH_IN != 0;
        snapshot.ethOut = packedTokenInAndFlags & _FLAG_ETH_OUT != 0;
        if (!snapshot.ethIn) {
            snapshot.erc20BalanceTokenInBefore = baseSlot.offset(4).asUint256().tload();
        }
        if (!snapshot.ethOut) {
            snapshot.erc20BalanceTokenOutBefore = baseSlot.offset(5).asUint256().tload();
        }
        if (snapshot.ethIn || snapshot.ethOut) {
            snapshot.nativeEthBalanceBefore = baseSlot.offset(6).asUint256().tload();
        }
    }

    /// @notice Load a transient swap snapshot and deactivate it.
    /// @param key Snapshot key derived from wallet, operation id, and call id.
    /// @return snapshot Snapshot data, with `active == false` when no snapshot is present.
    function loadAndClearSnapshot(bytes32 key) internal returns (Snapshot memory snapshot) {
        bytes32 baseSlot = _snapshotBaseSlot(key);
        uint256 packedTokenInAndFlags = baseSlot.offset(0).asUint256().tload();
        snapshot.active = packedTokenInAndFlags & _FLAG_ACTIVE != 0;
        if (!snapshot.active) {
            return snapshot;
        }

        // Clearing only the active flag deactivates the snapshot for this tx.
        baseSlot.offset(0).asUint256().tstore(0);
        snapshot.tokenIn = address(uint160(packedTokenInAndFlags & _ADDRESS_MASK));
        snapshot.tokenOut = baseSlot.offset(1).asAddress().tload();
        snapshot.priceFeedTokenIn = baseSlot.offset(2).asAddress().tload();
        snapshot.priceFeedTokenOut = baseSlot.offset(3).asAddress().tload();
        snapshot.ethIn = packedTokenInAndFlags & _FLAG_ETH_IN != 0;
        snapshot.ethOut = packedTokenInAndFlags & _FLAG_ETH_OUT != 0;
        if (!snapshot.ethIn) {
            snapshot.erc20BalanceTokenInBefore = baseSlot.offset(4).asUint256().tload();
        }
        if (!snapshot.ethOut) {
            snapshot.erc20BalanceTokenOutBefore = baseSlot.offset(5).asUint256().tload();
        }
        if (snapshot.ethIn || snapshot.ethOut) {
            snapshot.nativeEthBalanceBefore = baseSlot.offset(6).asUint256().tload();
        }
    }

    function _snapshotBaseSlot(bytes32 key) private pure returns (bytes32) {
        return _SNAPSHOTS_TSTORE_ROOT.deriveMapping(key);
    }

    function _packTokenInAndFlags(address tokenIn, bool ethIn, bool ethOut, bool active)
        private
        pure
        returns (uint256 packed)
    {
        packed = uint256(uint160(tokenIn));
        if (ethIn) {
            packed |= _FLAG_ETH_IN;
        }
        if (ethOut) {
            packed |= _FLAG_ETH_OUT;
        }
        if (active) {
            packed |= _FLAG_ACTIVE;
        }
    }
}
