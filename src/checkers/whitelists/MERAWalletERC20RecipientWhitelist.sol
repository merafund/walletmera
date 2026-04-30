// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IMERAWalletERC20RecipientWhitelist} from "../../interfaces/checkers/IMERAWalletERC20RecipientWhitelist.sol";
import {IMERAWalletERC20RecipientWhitelistErrors} from "../errors/IMERAWalletERC20RecipientWhitelistErrors.sol";

/// @title MERAWalletERC20RecipientWhitelist
/// @notice Ownable allowlist for ERC20 transfer recipients and approve spenders with optional fallback list contract.
/// @dev Avoid circular `fallbackWhitelist` graphs; resolution is unbounded recursion in the EVM.
contract MERAWalletERC20RecipientWhitelist is
    Ownable,
    IMERAWalletERC20RecipientWhitelist,
    IMERAWalletERC20RecipientWhitelistErrors
{
    event RecipientAllowedUpdated(address indexed recipient, bool allowed, address indexed caller);
    event FallbackWhitelistUpdated(
        address indexed previousFallback, address indexed newFallback, address indexed caller
    );

    mapping(address recipient => bool allowed) public allowedRecipient;

    /// @dev Secondary list consulted when `allowedRecipient[recipient]` is false.
    address public fallbackWhitelist;

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Batch-set local allow flags; pairs `recipients[i]` with `allowed[i]`.
    function setAllowedRecipients(address[] calldata recipients, bool[] calldata allowed) external onlyOwner {
        uint256 n = recipients.length;
        require(n == allowed.length, RecipientWhitelistArrayLengthMismatch());
        for (uint256 i = 0; i < n;) {
            address recipient = recipients[i];
            require(recipient != address(0), RecipientWhitelistInvalidAddress());
            allowedRecipient[recipient] = allowed[i];
            emit RecipientAllowedUpdated(recipient, allowed[i], msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Set optional fallback contract; pass address(0) to disable delegation.
    function setFallbackWhitelist(address newFallback) external onlyOwner {
        address previous = fallbackWhitelist;
        fallbackWhitelist = newFallback;
        emit FallbackWhitelistUpdated(previous, newFallback, msg.sender);
    }

    /// @inheritdoc IMERAWalletERC20RecipientWhitelist
    function isRecipientAllowed(address recipient) external view returns (bool) {
        if (allowedRecipient[recipient]) {
            return true;
        }
        address fb = fallbackWhitelist;
        if (fb != address(0)) {
            return IMERAWalletERC20RecipientWhitelist(fb).isRecipientAllowed(recipient);
        }
        return false;
    }
}
