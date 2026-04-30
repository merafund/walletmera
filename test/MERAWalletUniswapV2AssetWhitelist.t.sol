// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {MERAWalletUniswapV2AssetWhitelist} from "../src/checkers/whitelists/MERAWalletUniswapV2AssetWhitelist.sol";
import {
    IMERAWalletUniswapV2AssetWhitelistErrors
} from "../src/checkers/errors/IMERAWalletUniswapV2AssetWhitelistErrors.sol";

contract MERAWalletUniswapV2AssetWhitelistTest is Test {
    address internal owner = address(0x01);
    address internal tokenA = address(0xA);
    address internal tokenB = address(0xB);

    MERAWalletUniswapV2AssetWhitelist internal primary;
    MERAWalletUniswapV2AssetWhitelist internal secondaryList;

    function setUp() public {
        primary = new MERAWalletUniswapV2AssetWhitelist(owner);
        secondaryList = new MERAWalletUniswapV2AssetWhitelist(owner);
    }

    function test_IsAssetAllowed_LocalTrue() public {
        address[] memory assets = new address[](1);
        assets[0] = tokenA;
        bool[] memory allowed = new bool[](1);
        allowed[0] = true;

        vm.prank(owner);
        primary.setAllowedAssets(assets, allowed);

        assertTrue(primary.isAssetAllowed(tokenA));
        assertFalse(primary.isAssetAllowed(tokenB));
    }

    function test_IsAssetAllowed_DelegatesToFallback() public {
        address[] memory fbAssets = new address[](1);
        fbAssets[0] = tokenB;
        bool[] memory fbAllowed = new bool[](1);
        fbAllowed[0] = true;

        vm.startPrank(owner);
        secondaryList.setAllowedAssets(fbAssets, fbAllowed);
        primary.setFallbackWhitelist(address(secondaryList));
        vm.stopPrank();

        assertTrue(primary.isAssetAllowed(tokenB));
    }

    function test_SetAllowedAssets_ZeroAddressReverts() public {
        address[] memory assets = new address[](1);
        assets[0] = address(0);
        bool[] memory allowed = new bool[](1);
        allowed[0] = true;

        vm.prank(owner);
        vm.expectRevert(IMERAWalletUniswapV2AssetWhitelistErrors.AssetWhitelistInvalidAddress.selector);
        primary.setAllowedAssets(assets, allowed);
    }
}
