// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Custom errors for ERC20 transfer/approve whitelist checkers.
interface IMERAWalletERC20WhitelistCheckerErrors {
    error Erc20WhitelistUnexpectedSelector(bytes4 selector, uint256 callId);
    error Erc20WhitelistCalldataTooShort(uint256 callId);
    error Erc20WhitelistNonZeroValue(uint256 callId);
    error Erc20WhitelistTokenNotAllowed(address token, uint256 callId);
    error Erc20WhitelistCounterpartyNotAllowed(address account, uint256 callId);
    error Erc20WhitelistArrayLengthMismatch();
    error Erc20WhitelistInvalidAddress();
    error Erc20WhitelistNotPauseAuthorized();
}
