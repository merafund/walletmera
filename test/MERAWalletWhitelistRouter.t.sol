// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MERAWalletWhitelistRouter} from "../src/checkers/whitelists/MERAWalletWhitelistRouter.sol";
import {IMERAWalletWhitelistRouterErrors} from "../src/checkers/errors/IMERAWalletWhitelistRouterErrors.sol";

contract MERAWalletWhitelistRouterTest is Test {
    address internal owner = address(0x01);
    address internal outsider = address(0x02);
    address internal whitelistA = address(0xA);
    address internal whitelistB = address(0xB);

    MERAWalletWhitelistRouter internal router;

    function setUp() public {
        router = new MERAWalletWhitelistRouter(owner);
    }

    function test_OwnerCanSetUpdateAndClearRoute() public {
        bytes32 key = keccak256("custom.route");

        vm.prank(owner);
        router.setWhitelist(key, whitelistA);
        assertEq(router.whitelistByHash(key), whitelistA);

        vm.prank(owner);
        router.setWhitelist(key, whitelistB);
        assertEq(router.whitelistByHash(key), whitelistB);

        vm.prank(owner);
        router.setWhitelist(key, address(0));
        assertEq(router.whitelistByHash(key), address(0));
    }

    function test_NonOwnerCannotSetRoute() public {
        bytes32 key = keccak256("custom.route");

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        router.setWhitelist(key, whitelistA);
    }

    function test_BatchSetRejectsLengthMismatch() public {
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = keccak256("custom.route");
        address[] memory whitelists = new address[](2);
        whitelists[0] = whitelistA;
        whitelists[1] = whitelistB;

        vm.prank(owner);
        vm.expectRevert(IMERAWalletWhitelistRouterErrors.WhitelistRouterArrayLengthMismatch.selector);
        router.setWhitelists(keys, whitelists);
    }

    function test_ZeroHashRejected() public {
        vm.prank(owner);
        vm.expectRevert(IMERAWalletWhitelistRouterErrors.WhitelistRouterInvalidHash.selector);
        router.setWhitelist(bytes32(0), whitelistA);
    }

    function test_BuiltInRouteConstants() public view {
        assertEq(router.ASSET_WHITELIST_KEY(), keccak256("MERA_ASSET_WHITELIST"));
        assertEq(router.RECIPIENT_WHITELIST_KEY(), keccak256("MERA_RECIPIENT_WHITELIST"));
    }
}
