// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Configuration for MERA ERC20 transfer/approve whitelist checkers.
library MERAWalletERC20WhitelistCheckerTypes {
    /// @dev ABI payload for {IMERAWalletTransactionChecker-applyConfig}.
    /// @param assetWhitelist Optional {IMERAWalletAssetWhiteList} for `call.target` (ERC20 token); zero uses {defaultAssetWhitelist}.
    /// @param recipientWhitelist Optional {IMERAWalletERC20RecipientWhitelist} for transfer `to` or approve `spender`; zero uses {defaultRecipientWhitelist}.
    /// @param whitelistRouter Optional route registry checked before default whitelists when explicit lists are zero.
    struct Erc20WhitelistCheckerConfig {
        address assetWhitelist;
        address recipientWhitelist;
        address whitelistRouter;
    }
}
