// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors for ERC20 transfer/approve whitelist checkers.
interface IMERAWalletERC20WhitelistCheckerErrors {
    /// @notice ERC20 call selector does not match the checker flavor.
    error Erc20WhitelistUnexpectedSelector(bytes4 selector, uint256 callId);
    /// @notice ERC20 calldata is too short to decode recipient/spender and amount.
    error Erc20WhitelistCalldataTooShort(uint256 callId);
    /// @notice ERC20 transfer/approve calls must not carry native ETH.
    error Erc20WhitelistNonZeroValue(uint256 callId);
    /// @notice ERC20 token target is not allowed.
    error Erc20WhitelistTokenNotAllowed(address token, uint256 callId);
    /// @notice ERC20 recipient or spender is not allowed.
    error Erc20WhitelistCounterpartyNotAllowed(address account, uint256 callId);
    /// @notice Parallel update arrays have different lengths.
    error Erc20WhitelistArrayLengthMismatch();
    /// @notice Address argument is invalid.
    error Erc20WhitelistInvalidAddress();
}
