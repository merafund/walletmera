// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseMERAWallet} from "../../../BaseMERAWallet.sol";

abstract contract MERAWalletERC20 is BaseMERAWallet {
    function transferERC20(address token, address to, uint256 amount, uint256 nonce) external {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
        _executeSingleCall(token, 0, data, nonce);
    }

    function approveERC20(address token, address spender, uint256 amount, uint256 nonce) external {
        bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, spender, amount);
        _executeSingleCall(token, 0, data, nonce);
    }
}
