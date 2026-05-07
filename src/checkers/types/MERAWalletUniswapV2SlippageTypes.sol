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

    /// @dev ABI payload for {IMERAWalletTransactionChecker-applyConfig} on the slippage checker.
    struct UniswapV2SlippageCheckerConfig {
        /// @dev Optional ERC20 allowlist contract; address(0) disables per-wallet asset gating for that wallet.
        address assetWhitelist;
        /// @dev Optional per-wallet max oracle shortfall in BPS; 0 means fallback to checker default.
        uint256 maxOracleNegativeDeviationBps;
        /// @dev Optional per-wallet max Chainlink staleness in seconds; 0 means fallback to checker default.
        uint256 maxOracleStaleSeconds;
        /// @dev Optional route registry checked before default asset whitelist when `assetWhitelist` is zero.
        address whitelistRouter;
    }

    /// @dev ABI payload for per-call checker data when swap endpoints must not be decoded from `call.data`.
    struct CheckerDataSlippageCheckData {
        address tokenIn;
        address tokenOut;
        bool ethIn;
        bool ethOut;
    }

    /// @dev Swap snapshot: balances and path endpoints recorded in the before-hook, read in the after-hook for oracle comparison.
    struct Snapshot {
        address token0Path;
        address token1Path;
        address priceFeed0;
        address priceFeed1;
        uint256 erc20Bal0;
        uint256 erc20Bal1;
        uint256 ethBal;
        bool ethIn;
        bool ethOut;
        bool active;
    }

    function storeSnapshot(bytes32 key, Snapshot memory snapshot) internal {
        bytes32 baseSlot = _snapshotBaseSlot(key);
        baseSlot.offset(0).asUint256()
            .tstore(_packToken0AndFlags(snapshot.token0Path, snapshot.ethIn, snapshot.ethOut, snapshot.active));
        baseSlot.offset(1).asAddress().tstore(snapshot.token1Path);
        baseSlot.offset(2).asAddress().tstore(snapshot.priceFeed0);
        baseSlot.offset(3).asAddress().tstore(snapshot.priceFeed1);
        if (!snapshot.ethIn) {
            baseSlot.offset(4).asUint256().tstore(snapshot.erc20Bal0);
        }
        if (!snapshot.ethOut) {
            baseSlot.offset(5).asUint256().tstore(snapshot.erc20Bal1);
        }
        if (snapshot.ethIn || snapshot.ethOut) {
            baseSlot.offset(6).asUint256().tstore(snapshot.ethBal);
        }
    }

    function loadSnapshot(bytes32 key) internal view returns (Snapshot memory snapshot) {
        bytes32 baseSlot = _snapshotBaseSlot(key);
        uint256 packedToken0AndFlags = baseSlot.offset(0).asUint256().tload();
        snapshot.active = packedToken0AndFlags & _FLAG_ACTIVE != 0;
        if (!snapshot.active) {
            return snapshot;
        }

        snapshot.token0Path = address(uint160(packedToken0AndFlags & _ADDRESS_MASK));
        snapshot.token1Path = baseSlot.offset(1).asAddress().tload();
        snapshot.priceFeed0 = baseSlot.offset(2).asAddress().tload();
        snapshot.priceFeed1 = baseSlot.offset(3).asAddress().tload();
        snapshot.ethIn = packedToken0AndFlags & _FLAG_ETH_IN != 0;
        snapshot.ethOut = packedToken0AndFlags & _FLAG_ETH_OUT != 0;
        if (!snapshot.ethIn) {
            snapshot.erc20Bal0 = baseSlot.offset(4).asUint256().tload();
        }
        if (!snapshot.ethOut) {
            snapshot.erc20Bal1 = baseSlot.offset(5).asUint256().tload();
        }
        if (snapshot.ethIn || snapshot.ethOut) {
            snapshot.ethBal = baseSlot.offset(6).asUint256().tload();
        }
    }

    function loadAndClearSnapshot(bytes32 key) internal returns (Snapshot memory snapshot) {
        bytes32 baseSlot = _snapshotBaseSlot(key);
        uint256 packedToken0AndFlags = baseSlot.offset(0).asUint256().tload();
        snapshot.active = packedToken0AndFlags & _FLAG_ACTIVE != 0;
        if (!snapshot.active) {
            return snapshot;
        }

        // Clearing only the active flag deactivates the snapshot for this tx.
        baseSlot.offset(0).asUint256().tstore(0);
        snapshot.token0Path = address(uint160(packedToken0AndFlags & _ADDRESS_MASK));
        snapshot.token1Path = baseSlot.offset(1).asAddress().tload();
        snapshot.priceFeed0 = baseSlot.offset(2).asAddress().tload();
        snapshot.priceFeed1 = baseSlot.offset(3).asAddress().tload();
        snapshot.ethIn = packedToken0AndFlags & _FLAG_ETH_IN != 0;
        snapshot.ethOut = packedToken0AndFlags & _FLAG_ETH_OUT != 0;
        if (!snapshot.ethIn) {
            snapshot.erc20Bal0 = baseSlot.offset(4).asUint256().tload();
        }
        if (!snapshot.ethOut) {
            snapshot.erc20Bal1 = baseSlot.offset(5).asUint256().tload();
        }
        if (snapshot.ethIn || snapshot.ethOut) {
            snapshot.ethBal = baseSlot.offset(6).asUint256().tload();
        }
    }

    function clearSnapshot(bytes32 key) internal {
        bytes32 baseSlot = _snapshotBaseSlot(key);
        // Clearing the packed active flag is enough; remaining transient slots expire at tx end.
        baseSlot.offset(0).asUint256().tstore(0);
    }

    function _snapshotBaseSlot(bytes32 key) private pure returns (bytes32) {
        return _SNAPSHOTS_TSTORE_ROOT.deriveMapping(key);
    }

    function _packToken0AndFlags(address token0Path, bool ethIn, bool ethOut, bool active)
        private
        pure
        returns (uint256 packed)
    {
        packed = uint256(uint160(token0Path));
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
