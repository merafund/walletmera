// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

import {MERAWalletAssetWhiteList} from "../src/checkers/whitelists/MERAWalletAssetWhiteList.sol";
import {MERAWalletERC20RecipientWhitelist} from "../src/checkers/whitelists/MERAWalletERC20RecipientWhitelist.sol";
import {MERAWalletWhitelistRouter} from "../src/checkers/whitelists/MERAWalletWhitelistRouter.sol";
import {MERAWalletERC20ApproveWhitelistChecker} from "../src/checkers/MERAWalletERC20ApproveWhitelistChecker.sol";
import {MERAWalletERC20TransferWhitelistChecker} from "../src/checkers/MERAWalletERC20TransferWhitelistChecker.sol";
import {MERAWalletTargetBlacklistChecker} from "../src/checkers/MERAWalletTargetBlacklistChecker.sol";
import {MERAWalletTargetWhitelistChecker} from "../src/checkers/MERAWalletTargetWhitelistChecker.sol";
import {
    MERAWalletCheckerDataOracleSlippageChecker
} from "../src/checkers/MERAWalletCheckerDataOracleSlippageChecker.sol";
import {MERAWalletUniswapV2OracleSlippageChecker} from "../src/checkers/MERAWalletUniswapV2OracleSlippageChecker.sol";

import {MERAWalletAssetWhiteListFactory} from "../src/factories/checkers/MERAWalletAssetWhiteListFactory.sol";
import {
    MERAWalletERC20RecipientWhitelistFactory
} from "../src/factories/checkers/MERAWalletERC20RecipientWhitelistFactory.sol";
import {MERAWalletWhitelistRouterFactory} from "../src/factories/checkers/MERAWalletWhitelistRouterFactory.sol";
import {
    MERAWalletERC20ApproveWhitelistCheckerFactory
} from "../src/factories/checkers/MERAWalletERC20ApproveWhitelistCheckerFactory.sol";
import {
    MERAWalletERC20TransferWhitelistCheckerFactory
} from "../src/factories/checkers/MERAWalletERC20TransferWhitelistCheckerFactory.sol";
import {
    MERAWalletTargetBlacklistCheckerFactory
} from "../src/factories/checkers/MERAWalletTargetBlacklistCheckerFactory.sol";
import {
    MERAWalletTargetWhitelistCheckerFactory
} from "../src/factories/checkers/MERAWalletTargetWhitelistCheckerFactory.sol";
import {
    MERAWalletCheckerDataOracleSlippageCheckerFactory
} from "../src/factories/checkers/MERAWalletCheckerDataOracleSlippageCheckerFactory.sol";
import {
    MERAWalletUniswapV2OracleSlippageCheckerFactory
} from "../src/factories/checkers/MERAWalletUniswapV2OracleSlippageCheckerFactory.sol";

contract MERAWalletCheckerFactoriesTest is Test {
    address internal initialOwner = address(0xC0FFEE);

    uint256 internal constant DEFAULT_MAX_NEG_BPS = 100;
    uint256 internal constant DEFAULT_MAX_STALE = 3600;
    bool internal constant DEFAULT_REQUIRE_ROUTER = true;

    function test_AssetWhiteListFactory_DeploysAndEmits() public {
        MERAWalletAssetWhiteListFactory factory = new MERAWalletAssetWhiteListFactory();
        address predicted = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));

        vm.expectEmit(true, false, false, true);
        emit MERAWalletAssetWhiteListFactory.Deployed(predicted);

        MERAWalletAssetWhiteList deployed = factory.deploy(initialOwner);
        assertEq(address(deployed), predicted);
        assertEq(deployed.owner(), initialOwner);
    }

    function test_ERC20RecipientWhitelistFactory_DeploysAndEmits() public {
        MERAWalletERC20RecipientWhitelistFactory factory = new MERAWalletERC20RecipientWhitelistFactory();
        address predicted = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));

        vm.expectEmit(true, false, false, true);
        emit MERAWalletERC20RecipientWhitelistFactory.Deployed(predicted);

        MERAWalletERC20RecipientWhitelist deployed = factory.deploy(initialOwner);
        assertEq(address(deployed), predicted);
        assertEq(deployed.owner(), initialOwner);
    }

    function test_WhitelistRouterFactory_DeploysAndEmits() public {
        MERAWalletWhitelistRouterFactory factory = new MERAWalletWhitelistRouterFactory();
        address predicted = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));

        vm.expectEmit(true, false, false, true);
        emit MERAWalletWhitelistRouterFactory.Deployed(predicted);

        MERAWalletWhitelistRouter deployed = factory.deploy(initialOwner);
        assertEq(address(deployed), predicted);
        assertEq(deployed.owner(), initialOwner);
    }

    function test_ERC20ApproveWhitelistCheckerFactory_DeploysAndEmits() public {
        MERAWalletERC20ApproveWhitelistCheckerFactory factory = new MERAWalletERC20ApproveWhitelistCheckerFactory();
        address predicted = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));

        vm.expectEmit(true, false, false, true);
        emit MERAWalletERC20ApproveWhitelistCheckerFactory.Deployed(predicted);

        MERAWalletERC20ApproveWhitelistChecker deployed = factory.deploy(initialOwner);
        assertEq(address(deployed), predicted);
        assertEq(deployed.owner(), initialOwner);
    }

    function test_ERC20TransferWhitelistCheckerFactory_DeploysAndEmits() public {
        MERAWalletERC20TransferWhitelistCheckerFactory factory = new MERAWalletERC20TransferWhitelistCheckerFactory();
        address predicted = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));

        vm.expectEmit(true, false, false, true);
        emit MERAWalletERC20TransferWhitelistCheckerFactory.Deployed(predicted);

        MERAWalletERC20TransferWhitelistChecker deployed = factory.deploy(initialOwner);
        assertEq(address(deployed), predicted);
        assertEq(deployed.owner(), initialOwner);
    }

    function test_TargetBlacklistCheckerFactory_DeploysAndEmits() public {
        MERAWalletTargetBlacklistCheckerFactory factory = new MERAWalletTargetBlacklistCheckerFactory();
        address predicted = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));

        vm.expectEmit(true, false, false, true);
        emit MERAWalletTargetBlacklistCheckerFactory.Deployed(predicted);

        MERAWalletTargetBlacklistChecker deployed = factory.deploy(initialOwner);
        assertEq(address(deployed), predicted);
        assertEq(deployed.owner(), initialOwner);
    }

    function test_TargetWhitelistCheckerFactory_DeploysAndEmits() public {
        MERAWalletTargetWhitelistCheckerFactory factory = new MERAWalletTargetWhitelistCheckerFactory();
        address predicted = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));

        vm.expectEmit(true, false, false, true);
        emit MERAWalletTargetWhitelistCheckerFactory.Deployed(predicted);

        MERAWalletTargetWhitelistChecker deployed = factory.deploy(initialOwner);
        assertEq(address(deployed), predicted);
        assertEq(deployed.owner(), initialOwner);
    }

    function test_CheckerDataOracleSlippageCheckerFactory_DeploysAndEmits() public {
        MERAWalletCheckerDataOracleSlippageCheckerFactory factory =
            new MERAWalletCheckerDataOracleSlippageCheckerFactory();
        address predicted = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));

        vm.expectEmit(true, false, false, true);
        emit MERAWalletCheckerDataOracleSlippageCheckerFactory.Deployed(predicted);

        MERAWalletCheckerDataOracleSlippageChecker deployed =
            factory.deploy(initialOwner, DEFAULT_MAX_NEG_BPS, DEFAULT_MAX_STALE, DEFAULT_REQUIRE_ROUTER);
        assertEq(address(deployed), predicted);
        assertEq(deployed.owner(), initialOwner);
        assertEq(deployed.MAX_ORACLE_NEGATIVE_DEVIATION_BPS(), DEFAULT_MAX_NEG_BPS);
        assertEq(deployed.MAX_ORACLE_STALE_SECONDS(), DEFAULT_MAX_STALE);
        assertTrue(deployed.REQUIRE_ROUTER_ALLOWLIST());
    }

    function test_UniswapV2OracleSlippageCheckerFactory_DeploysAndEmits() public {
        MERAWalletUniswapV2OracleSlippageCheckerFactory factory = new MERAWalletUniswapV2OracleSlippageCheckerFactory();
        address predicted = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));

        vm.expectEmit(true, false, false, true);
        emit MERAWalletUniswapV2OracleSlippageCheckerFactory.Deployed(predicted);

        MERAWalletUniswapV2OracleSlippageChecker deployed =
            factory.deploy(initialOwner, DEFAULT_MAX_NEG_BPS, DEFAULT_MAX_STALE, DEFAULT_REQUIRE_ROUTER);
        assertEq(address(deployed), predicted);
        assertEq(deployed.owner(), initialOwner);
        assertEq(deployed.MAX_ORACLE_NEGATIVE_DEVIATION_BPS(), DEFAULT_MAX_NEG_BPS);
        assertEq(deployed.MAX_ORACLE_STALE_SECONDS(), DEFAULT_MAX_STALE);
        assertTrue(deployed.REQUIRE_ROUTER_ALLOWLIST());
    }
}
