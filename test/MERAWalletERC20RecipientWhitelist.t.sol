// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

import {MERAWalletERC20RecipientWhitelist} from "../src/checkers/whitelists/MERAWalletERC20RecipientWhitelist.sol";
import {
    IMERAWalletERC20RecipientWhitelistErrors
} from "../src/checkers/errors/IMERAWalletERC20RecipientWhitelistErrors.sol";

contract MERAWalletERC20RecipientWhitelistTest is Test {
    address internal owner = address(0x01);
    address internal recipientA = address(0xA);
    address internal recipientB = address(0xB);

    MERAWalletERC20RecipientWhitelist internal primary;
    MERAWalletERC20RecipientWhitelist internal secondaryList;

    function setUp() public {
        primary = new MERAWalletERC20RecipientWhitelist(owner);
        secondaryList = new MERAWalletERC20RecipientWhitelist(owner);
    }

    function test_IsRecipientAllowed_LocalTrue() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipientA;
        bool[] memory allowed = new bool[](1);
        allowed[0] = true;

        vm.prank(owner);
        primary.setAllowedRecipients(recipients, allowed);

        assertTrue(primary.isRecipientAllowed(recipientA));
        assertFalse(primary.isRecipientAllowed(recipientB));
    }

    function test_IsRecipientAllowed_DelegatesToFallback() public {
        address[] memory fbRecipients = new address[](1);
        fbRecipients[0] = recipientB;
        bool[] memory fbAllowed = new bool[](1);
        fbAllowed[0] = true;

        vm.startPrank(owner);
        secondaryList.setAllowedRecipients(fbRecipients, fbAllowed);
        primary.setFallbackWhitelist(address(secondaryList));
        vm.stopPrank();

        assertTrue(primary.isRecipientAllowed(recipientB));
    }

    function test_SetAllowedRecipients_ZeroAddressReverts() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(0);
        bool[] memory allowed = new bool[](1);
        allowed[0] = true;

        vm.prank(owner);
        vm.expectRevert(IMERAWalletERC20RecipientWhitelistErrors.RecipientWhitelistInvalidAddress.selector);
        primary.setAllowedRecipients(recipients, allowed);
    }
}
