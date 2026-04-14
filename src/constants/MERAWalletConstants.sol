// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Magic return values for EIP-1271 `isValidSignature` (https://eips.ethereum.org/EIPS/eip-1271).
library MERAWalletConstants {
    bytes4 internal constant EIP1271_MAGICVALUE = 0x1626ba7e;
    bytes4 internal constant EIP1271_INVALID = 0xffffffff;
}
