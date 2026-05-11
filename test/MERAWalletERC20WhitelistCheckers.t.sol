// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletERC20TransferWhitelistChecker} from "../src/checkers/MERAWalletERC20TransferWhitelistChecker.sol";
import {MERAWalletERC20ApproveWhitelistChecker} from "../src/checkers/MERAWalletERC20ApproveWhitelistChecker.sol";
import {MERAWalletERC20RecipientWhitelist} from "../src/checkers/whitelists/MERAWalletERC20RecipientWhitelist.sol";
import {MERAWalletAssetWhiteList} from "../src/checkers/whitelists/MERAWalletAssetWhiteList.sol";
import {MERAWalletWhitelistRouter} from "../src/checkers/whitelists/MERAWalletWhitelistRouter.sol";
import {MERAWalletERC20WhitelistCheckerTypes} from "../src/checkers/types/MERAWalletERC20WhitelistCheckerTypes.sol";
import {
    IMERAWalletERC20WhitelistCheckerErrors
} from "../src/checkers/errors/IMERAWalletERC20WhitelistCheckerErrors.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {MERAWalletTestBase} from "./helpers/MERAWalletTestBase.sol";

contract MERAWalletERC20WhitelistCheckersTest is MERAWalletTestBase {
    uint256 private _optCfgSalt = 10_000;

    uint256 internal primaryPk = PRIMARY_PK;
    address internal primary = vm.addr(PRIMARY_PK);
    address internal backup = vm.addr(BACKUP_PK);
    address internal emergency = vm.addr(EMERGENCY_PK);
    address internal recipient = address(0xB0B0);
    address internal spender = address(0x51ED);
    BaseMERAWallet internal wallet;
    MERAWalletERC20TransferWhitelistChecker internal transferChecker;
    MERAWalletERC20ApproveWhitelistChecker internal approveChecker;
    ERC20Mock internal token;
    MERAWalletAssetWhiteList internal assetWl;
    MERAWalletERC20RecipientWhitelist internal counterpartyWl;
    MERAWalletWhitelistRouter internal whitelistRouter;

    function setUp() public {
        wallet = new BaseMERAWallet(primary, backup, emergency, address(0), address(0));
        transferChecker = new MERAWalletERC20TransferWhitelistChecker(emergency);
        approveChecker = new MERAWalletERC20ApproveWhitelistChecker(emergency);
        token = new ERC20Mock();

        assetWl = new MERAWalletAssetWhiteList(emergency);
        counterpartyWl = new MERAWalletERC20RecipientWhitelist(emergency);
        whitelistRouter = new MERAWalletWhitelistRouter(emergency);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(wallet, 0);
        vm.stopPrank();
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(0), true, ""));
    }

    function _allowTokenAndCounterparty() internal {
        vm.prank(emergency);
        assetWl.setAllowedAssets(_oneAddress(address(token)), _oneBool(true));

        vm.prank(emergency);
        counterpartyWl.setAllowedRecipients(_twoAddresses(recipient, spender), _twoBools(true, true));
    }

    function _setOptionalCheckers(MERAWalletTypes.OptionalCheckerUpdate[] memory updates) internal {
        vm.startPrank(emergency);
        _executeEmergencyWalletSelfCallTimelocked(
            wallet, abi.encodeWithSelector(wallet.setOptionalCheckers.selector, updates), ++_optCfgSalt
        );
        vm.stopPrank();
    }

    function _cfg() internal view returns (MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory) {
        return MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig({
            assetWhitelist: address(assetWl), recipientWhitelist: address(counterpartyWl), whitelistRouter: address(0)
        });
    }

    function _routerCfg()
        internal
        view
        returns (MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory)
    {
        return MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig({
            assetWhitelist: address(0), recipientWhitelist: address(0), whitelistRouter: address(whitelistRouter)
        });
    }

    /// @dev Mirrors `MERAWalletERC20.transferERC20` routing (single IERC20.transfer via `executeTransaction`).
    function _transferErc20Calls(address token_, address to, uint256 amount, address checker)
        internal
        pure
        returns (MERAWalletTypes.Call[] memory calls)
    {
        calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: token_,
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, to, amount),
            checker: checker,
            checkerData: ""
        });
    }

    function test_Transfer_HappyPath() public {
        _allowTokenAndCounterparty();
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(transferChecker), true, abi.encode(_cfg())));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        wallet.executeTransaction(_transferErc20Calls(address(token), recipient, 100, address(transferChecker)), 1);
        assertEq(token.balanceOf(recipient), 100);
    }

    function test_Transfer_RevertsWhenTokenNotAllowed() public {
        vm.prank(emergency);
        counterpartyWl.setAllowedRecipients(_oneAddress(recipient), _oneBool(true));

        MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory cfg =
            MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig({
                assetWhitelist: address(assetWl),
                recipientWhitelist: address(counterpartyWl),
                whitelistRouter: address(0)
            });
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(transferChecker), true, abi.encode(cfg)));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletERC20WhitelistCheckerErrors.Erc20WhitelistTokenNotAllowed.selector,
                address(token),
                uint256(0)
            )
        );
        wallet.executeTransaction(_transferErc20Calls(address(token), recipient, 100, address(transferChecker)), 1);
    }

    function test_Transfer_RevertsWhenRecipientNotAllowed() public {
        vm.prank(emergency);
        assetWl.setAllowedAssets(_oneAddress(address(token)), _oneBool(true));

        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(transferChecker), true, abi.encode(_cfg())));

        token.mint(address(wallet), 1000);
        address badRecipient = address(0xBAD);
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletERC20WhitelistCheckerErrors.Erc20WhitelistCounterpartyNotAllowed.selector,
                badRecipient,
                uint256(0)
            )
        );
        wallet.executeTransaction(_transferErc20Calls(address(token), badRecipient, 100, address(transferChecker)), 1);
    }

    function test_Transfer_RevertsOnWrongSelector() public {
        _allowTokenAndCounterparty();
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(transferChecker), true, abi.encode(_cfg())));

        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: address(token),
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, spender, 1 ether),
            checker: address(transferChecker),
            checkerData: ""
        });

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletERC20WhitelistCheckerErrors.Erc20WhitelistUnexpectedSelector.selector,
                IERC20.approve.selector,
                uint256(0)
            )
        );
        wallet.executeTransaction(calls, 1);
    }

    function test_Transfer_RevertsOnCalldataTooShort() public {
        _allowTokenAndCounterparty();
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(transferChecker), true, abi.encode(_cfg())));

        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: address(token),
            value: 0,
            data: bytes.concat(IERC20.transfer.selector),
            checker: address(transferChecker),
            checkerData: ""
        });

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletERC20WhitelistCheckerErrors.Erc20WhitelistCalldataTooShort.selector, uint256(0)
            )
        );
        wallet.executeTransaction(calls, 1);
    }

    function test_Transfer_RevertsOnNonZeroValue() public {
        _allowTokenAndCounterparty();
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(transferChecker), true, abi.encode(_cfg())));

        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: address(token),
            value: 1 wei,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, 1),
            checker: address(transferChecker),
            checkerData: ""
        });

        vm.deal(address(wallet), 1 ether);
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletERC20WhitelistCheckerErrors.Erc20WhitelistNonZeroValue.selector, uint256(0)
            )
        );
        wallet.executeTransaction(calls, 1);
    }

    function test_Transfer_UsesDefaultWhitelistsWhenWalletConfigZero() public {
        vm.prank(emergency);
        assetWl.setAllowedAssets(_oneAddress(address(token)), _oneBool(true));

        vm.prank(emergency);
        counterpartyWl.setAllowedRecipients(_oneAddress(recipient), _oneBool(true));

        vm.startPrank(emergency);
        transferChecker.setDefaultAssetWhitelist(address(assetWl));
        transferChecker.setDefaultRecipientWhitelist(address(counterpartyWl));
        vm.stopPrank();
        MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory emptyCfg =
            MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig({
                assetWhitelist: address(0), recipientWhitelist: address(0), whitelistRouter: address(0)
            });
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(transferChecker), true, abi.encode(emptyCfg)));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        wallet.executeTransaction(_transferErc20Calls(address(token), recipient, 50, address(transferChecker)), 2);
        assertEq(token.balanceOf(recipient), 50);
    }

    function test_Transfer_UsesRouterWhitelistsWhenExplicitConfigZero() public {
        _allowTokenAndCounterparty();

        vm.startPrank(emergency);
        whitelistRouter.setWhitelist(whitelistRouter.ASSET_WHITELIST_KEY(), address(assetWl));
        whitelistRouter.setWhitelist(whitelistRouter.RECIPIENT_WHITELIST_KEY(), address(counterpartyWl));
        vm.stopPrank();
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(transferChecker), true, abi.encode(_routerCfg())));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        wallet.executeTransaction(_transferErc20Calls(address(token), recipient, 50, address(transferChecker)), 2);
        assertEq(token.balanceOf(recipient), 50);
    }

    function test_Transfer_ExplicitWhitelistsWinOverRouterRoutes() public {
        _allowTokenAndCounterparty();
        MERAWalletAssetWhiteList blockedAssets = new MERAWalletAssetWhiteList(emergency);
        MERAWalletERC20RecipientWhitelist blockedRecipients = new MERAWalletERC20RecipientWhitelist(emergency);

        vm.startPrank(emergency);
        whitelistRouter.setWhitelist(whitelistRouter.ASSET_WHITELIST_KEY(), address(blockedAssets));
        whitelistRouter.setWhitelist(whitelistRouter.RECIPIENT_WHITELIST_KEY(), address(blockedRecipients));
        vm.stopPrank();

        MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory cfg =
            MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig({
                assetWhitelist: address(assetWl),
                recipientWhitelist: address(counterpartyWl),
                whitelistRouter: address(whitelistRouter)
            });
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(transferChecker), true, abi.encode(cfg)));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        wallet.executeTransaction(_transferErc20Calls(address(token), recipient, 50, address(transferChecker)), 2);
        assertEq(token.balanceOf(recipient), 50);
    }

    function test_Transfer_UsesDefaultsWhenRouterRouteMissingOrCleared() public {
        _allowTokenAndCounterparty();

        vm.startPrank(emergency);
        transferChecker.setDefaultAssetWhitelist(address(assetWl));
        transferChecker.setDefaultRecipientWhitelist(address(counterpartyWl));
        whitelistRouter.setWhitelist(whitelistRouter.ASSET_WHITELIST_KEY(), address(assetWl));
        whitelistRouter.setWhitelist(whitelistRouter.ASSET_WHITELIST_KEY(), address(0));
        vm.stopPrank();
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(transferChecker), true, abi.encode(_routerCfg())));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        wallet.executeTransaction(_transferErc20Calls(address(token), recipient, 50, address(transferChecker)), 2);
        assertEq(token.balanceOf(recipient), 50);
    }

    function test_Transfer_RouterRouteChangeAppliesWithoutReapplyingCheckerConfig() public {
        _allowTokenAndCounterparty();
        MERAWalletERC20RecipientWhitelist blockedRecipients = new MERAWalletERC20RecipientWhitelist(emergency);
        bytes32 recipientKey = whitelistRouter.RECIPIENT_WHITELIST_KEY();

        vm.startPrank(emergency);
        whitelistRouter.setWhitelist(whitelistRouter.ASSET_WHITELIST_KEY(), address(assetWl));
        whitelistRouter.setWhitelist(recipientKey, address(counterpartyWl));
        vm.stopPrank();
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(transferChecker), true, abi.encode(_routerCfg())));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        wallet.executeTransaction(_transferErc20Calls(address(token), recipient, 50, address(transferChecker)), 2);
        assertEq(token.balanceOf(recipient), 50);

        vm.prank(emergency);
        whitelistRouter.setWhitelist(recipientKey, address(blockedRecipients));

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletERC20WhitelistCheckerErrors.Erc20WhitelistCounterpartyNotAllowed.selector,
                recipient,
                uint256(0)
            )
        );
        wallet.executeTransaction(_transferErc20Calls(address(token), recipient, 50, address(transferChecker)), 3);
    }

    function test_ApplyConfig_EmptyIsNoOp() public {
        vm.prank(address(wallet));
        transferChecker.applyConfig("");
    }

    function test_Approve_HappyPath() public {
        _allowTokenAndCounterparty();
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(approveChecker), true, abi.encode(_cfg())));

        token.mint(address(wallet), 1000);
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: address(token),
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, spender, 500),
            checker: address(approveChecker),
            checkerData: ""
        });
        vm.prank(primary);
        wallet.executeTransaction(calls, 1);
        assertEq(token.allowance(address(wallet), spender), 500);
    }

    function test_Approve_UsesRouterWhitelistsWhenExplicitConfigZero() public {
        _allowTokenAndCounterparty();

        vm.startPrank(emergency);
        whitelistRouter.setWhitelist(whitelistRouter.ASSET_WHITELIST_KEY(), address(assetWl));
        whitelistRouter.setWhitelist(whitelistRouter.RECIPIENT_WHITELIST_KEY(), address(counterpartyWl));
        vm.stopPrank();
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(approveChecker), true, abi.encode(_routerCfg())));

        token.mint(address(wallet), 1000);
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: address(token),
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, spender, 500),
            checker: address(approveChecker),
            checkerData: ""
        });
        vm.prank(primary);
        wallet.executeTransaction(calls, 1);
        assertEq(token.allowance(address(wallet), spender), 500);
    }

    function test_Approve_RevertsOnWrongSelector() public {
        _allowTokenAndCounterparty();
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(approveChecker), true, abi.encode(_cfg())));

        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: address(token),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, 1),
            checker: address(approveChecker),
            checkerData: ""
        });

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletERC20WhitelistCheckerErrors.Erc20WhitelistUnexpectedSelector.selector,
                IERC20.transfer.selector,
                uint256(0)
            )
        );
        wallet.executeTransaction(calls, 1);
    }

    function test_Approve_RevertsWhenSpenderNotAllowed() public {
        vm.prank(emergency);
        assetWl.setAllowedAssets(_oneAddress(address(token)), _oneBool(true));

        vm.prank(emergency);
        counterpartyWl.setAllowedRecipients(_oneAddress(recipient), _oneBool(true));

        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(approveChecker), true, abi.encode(_cfg())));

        token.mint(address(wallet), 1000);
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: address(token),
            value: 0,
            data: abi.encodeWithSelector(IERC20.approve.selector, spender, 1),
            checker: address(approveChecker),
            checkerData: ""
        });
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletERC20WhitelistCheckerErrors.Erc20WhitelistCounterpartyNotAllowed.selector,
                spender,
                uint256(0)
            )
        );
        wallet.executeTransaction(calls, 1);
    }

    function test_Transfer_NoAssetWhitelist_PassesTokenCheck() public {
        MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory emptyCfg =
            MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig({
                assetWhitelist: address(0), recipientWhitelist: address(counterpartyWl), whitelistRouter: address(0)
            });
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(transferChecker), true, abi.encode(emptyCfg)));

        vm.prank(emergency);
        counterpartyWl.setAllowedRecipients(_oneAddress(recipient), _oneBool(true));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        wallet.executeTransaction(_transferErc20Calls(address(token), recipient, 100, address(transferChecker)), 2);
        assertEq(token.balanceOf(recipient), 100);
    }

    function test_Transfer_NoRecipientWhitelist_PassesCounterpartyCheck() public {
        MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory emptyCfg =
            MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig({
                assetWhitelist: address(assetWl), recipientWhitelist: address(0), whitelistRouter: address(0)
            });
        _setOptionalCheckers(_mkOptionalCheckerUpdate(address(transferChecker), true, abi.encode(emptyCfg)));

        vm.prank(emergency);
        assetWl.setAllowedAssets(_oneAddress(address(token)), _oneBool(true));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        wallet.executeTransaction(_transferErc20Calls(address(token), recipient, 100, address(transferChecker)), 3);
        assertEq(token.balanceOf(recipient), 100);
    }

    function test_HookModes_ReturnsTrueAndFalse() public view {
        (bool before_, bool after_) = transferChecker.hookModes();
        assertTrue(before_);
        assertFalse(after_);
    }

    function test_CheckAfter_DoesNothing() public {
        MERAWalletTypes.Call memory call = MERAWalletTypes.Call({
            target: address(token),
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, 1),
            checker: address(0),
            checkerData: ""
        });
        vm.prank(address(wallet));
        transferChecker.checkAfter(call, bytes32(0), 0); // must not revert
    }
}
