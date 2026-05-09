// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletTargetBlacklistChecker} from "../src/checkers/MERAWalletTargetBlacklistChecker.sol";
import {MERAWalletTargetWhitelistChecker} from "../src/checkers/MERAWalletTargetWhitelistChecker.sol";
import {IMERAWalletBlacklistErrors} from "../src/checkers/errors/IMERAWalletBlacklistErrors.sol";
import {IMERAWalletWhitelistErrors} from "../src/checkers/errors/IMERAWalletWhitelistErrors.sol";
import {MERAWalletBlacklistTypes} from "../src/checkers/types/MERAWalletBlacklistTypes.sol";
import {MERAWalletWhitelistTypes} from "../src/checkers/types/MERAWalletWhitelistTypes.sol";
import {ReceiverMock} from "./mocks/ReceiverMock.sol";

contract MERAWalletTargetCheckersTest is Test {
    address internal owner = address(0x0A);
    address internal outsider = address(0x0B);
    address internal walletAddr = address(0xCAFE);

    MERAWalletTargetBlacklistChecker internal bl;
    MERAWalletTargetWhitelistChecker internal wl;
    ReceiverMock internal receiver;

    function setUp() public {
        bl = new MERAWalletTargetBlacklistChecker(owner);
        wl = new MERAWalletTargetWhitelistChecker(owner);
        receiver = new ReceiverMock();
    }

    function _call(address target, bytes memory data) internal pure returns (MERAWalletTypes.Call memory c) {
        c = MERAWalletTypes.Call({target: target, value: 0, data: data, checker: address(0), checkerData: ""});
    }

    function test_Blacklist_CheckBefore_PassesWhenNotBlocked() public {
        MERAWalletTypes.Call memory call =
            _call(address(receiver), abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));
        vm.prank(walletAddr);
        bl.checkBefore(call, bytes32(0), 0);
    }

    function test_BlacklistOwnable_NonOwnerCannotSetBlockedTarget() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        bl.setBlockedTarget(address(receiver), true);
    }

    function test_BlacklistOwnable_OwnerBlocks_CheckBeforeReverts() public {
        vm.prank(owner);
        bl.setBlockedTarget(address(receiver), true);

        MERAWalletTypes.Call memory call =
            _call(address(receiver), abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));

        vm.prank(walletAddr);
        vm.expectRevert(abi.encodeWithSelector(IMERAWalletBlacklistErrors.TargetBlocked.selector, address(receiver), 0));
        bl.checkBefore(call, bytes32(0), 0);
    }

    function test_BlacklistOwnable_ApplyConfig_OnlyOwner() public {
        MERAWalletBlacklistTypes.TargetBlockState[] memory states = new MERAWalletBlacklistTypes.TargetBlockState[](1);
        states[0] = MERAWalletBlacklistTypes.TargetBlockState({target: address(receiver), blocked: true});

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        bl.applyConfig(abi.encode(states));

        vm.prank(owner);
        bl.applyConfig(abi.encode(states));

        MERAWalletTypes.Call memory call =
            _call(address(receiver), abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));
        vm.prank(walletAddr);
        vm.expectRevert(abi.encodeWithSelector(IMERAWalletBlacklistErrors.TargetBlocked.selector, address(receiver), 0));
        bl.checkBefore(call, bytes32(0), 0);
    }

    function test_BlacklistOwnable_ApplyConfig_EmptyStillRequiresOwner() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        bl.applyConfig("");

        vm.prank(owner);
        bl.applyConfig("");
    }

    function test_WhitelistOwnable_NonOwnerCannotSetAllowedTarget() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        wl.setAllowedTarget(address(receiver), true);
    }

    function test_WhitelistOwnable_OwnerAllows_CheckBeforePasses() public {
        vm.prank(owner);
        wl.setAllowedTarget(address(receiver), true);

        MERAWalletTypes.Call memory call =
            _call(address(receiver), abi.encodeWithSelector(ReceiverMock.setValue.selector, 7));

        vm.prank(walletAddr);
        wl.checkBefore(call, bytes32(0), 0);
    }

    function test_WhitelistOwnable_CheckBefore_RevertsWhenNotAllowed() public {
        MERAWalletTypes.Call memory call =
            _call(address(receiver), abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));

        vm.prank(walletAddr);
        vm.expectRevert(
            abi.encodeWithSelector(IMERAWalletWhitelistErrors.TargetNotAllowed.selector, address(receiver), 0)
        );
        wl.checkBefore(call, bytes32(0), 0);
    }

    function test_WhitelistOwnable_ApplyConfig_OnlyOwner() public {
        MERAWalletWhitelistTypes.TargetPermission[] memory perms = new MERAWalletWhitelistTypes.TargetPermission[](1);
        perms[0] = MERAWalletWhitelistTypes.TargetPermission({target: address(receiver), allowed: true});

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        wl.applyConfig(abi.encode(perms));

        vm.prank(owner);
        wl.applyConfig(abi.encode(perms));

        MERAWalletTypes.Call memory call =
            _call(address(receiver), abi.encodeWithSelector(ReceiverMock.setValue.selector, 2));
        vm.prank(walletAddr);
        wl.checkBefore(call, bytes32(0), 0);
    }

    // ── Blacklist: setBlockedTargets (batch variant) ──────────────────────────

    function test_Blacklist_SetBlockedTargets_BatchBlocks() public {
        MERAWalletBlacklistTypes.TargetBlockState[] memory states = new MERAWalletBlacklistTypes.TargetBlockState[](2);
        states[0] = MERAWalletBlacklistTypes.TargetBlockState({target: address(receiver), blocked: true});
        states[1] = MERAWalletBlacklistTypes.TargetBlockState({target: address(0xDEAD), blocked: true});

        vm.prank(owner);
        bl.setBlockedTargets(states);

        MERAWalletTypes.Call memory call =
            _call(address(receiver), abi.encodeWithSelector(ReceiverMock.setValue.selector, 99));
        vm.prank(walletAddr);
        vm.expectRevert(abi.encodeWithSelector(IMERAWalletBlacklistErrors.TargetBlocked.selector, address(receiver), 0));
        bl.checkBefore(call, bytes32(0), 0);
    }

    function test_Blacklist_HookModes_ReturnsTrueAndFalse() public view {
        (bool before_, bool after_) = bl.hookModes();
        assertTrue(before_);
        assertFalse(after_);
    }

    function test_Blacklist_CheckAfter_DoesNothing() public {
        MERAWalletTypes.Call memory call = _call(address(receiver), "");
        vm.prank(walletAddr);
        bl.checkAfter(call, bytes32(0), 0); // must not revert
    }

    // ── Whitelist: setAllowedTargets (batch variant) ──────────────────────────

    function test_Whitelist_SetAllowedTargets_BatchAllows() public {
        MERAWalletWhitelistTypes.TargetPermission[] memory perms = new MERAWalletWhitelistTypes.TargetPermission[](1);
        perms[0] = MERAWalletWhitelistTypes.TargetPermission({target: address(receiver), allowed: true});

        vm.prank(owner);
        wl.setAllowedTargets(perms);

        MERAWalletTypes.Call memory call =
            _call(address(receiver), abi.encodeWithSelector(ReceiverMock.setValue.selector, 3));
        vm.prank(walletAddr);
        wl.checkBefore(call, bytes32(0), 0); // must not revert
    }

    function test_Whitelist_HookModes_ReturnsTrueAndFalse() public view {
        (bool before_, bool after_) = wl.hookModes();
        assertTrue(before_);
        assertFalse(after_);
    }

    function test_Whitelist_CheckAfter_DoesNothing() public {
        MERAWalletTypes.Call memory call = _call(address(receiver), "");
        vm.prank(walletAddr);
        wl.checkAfter(call, bytes32(0), 0); // must not revert
    }
}
