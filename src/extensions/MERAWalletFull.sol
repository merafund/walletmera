// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {BaseMERAWallet} from "../BaseMERAWallet.sol";
import {MERAWalletNative} from "./MERAWalletNative.sol";
import {MERAWalletERC20} from "./token/ERC20/MERAWalletERC20.sol";

contract MERAWalletFull is MERAWalletNative, MERAWalletERC20 {
    constructor(
        address initialPrimary,
        address initialBackup,
        address initialEmergency,
        address initialSigner,
        address initialGuardian
    ) BaseMERAWallet(initialPrimary, initialBackup, initialEmergency, initialSigner, initialGuardian) {}
}
