// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MERAWalletERC20WhitelistCheckerBase} from "./MERAWalletERC20WhitelistCheckerBase.sol";

/// @notice Validates wallet ERC20 `transfer` calls: optional token allowlist plus recipient (`to`) allowlist.
contract MERAWalletERC20TransferWhitelistChecker is MERAWalletERC20WhitelistCheckerBase {
    constructor(address initialOwner) MERAWalletERC20WhitelistCheckerBase(initialOwner) {}

    /// @inheritdoc MERAWalletERC20WhitelistCheckerBase
    function _expectedSelector() internal pure override returns (bytes4) {
        return IERC20.transfer.selector;
    }
}
