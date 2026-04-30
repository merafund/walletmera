// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletERC20TransferWhitelistChecker} from "../src/checkers/MERAWalletERC20TransferWhitelistChecker.sol";
import {MERAWalletERC20ApproveWhitelistChecker} from "../src/checkers/MERAWalletERC20ApproveWhitelistChecker.sol";
import {MERAWalletERC20RecipientWhitelist} from "../src/checkers/whitelists/MERAWalletERC20RecipientWhitelist.sol";
import {MERAWalletUniswapV2AssetWhitelist} from "../src/checkers/whitelists/MERAWalletUniswapV2AssetWhitelist.sol";
import {MERAWalletERC20WhitelistCheckerTypes} from "../src/checkers/types/MERAWalletERC20WhitelistCheckerTypes.sol";
import {
    IMERAWalletERC20WhitelistCheckerErrors
} from "../src/checkers/errors/IMERAWalletERC20WhitelistCheckerErrors.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract MERAWalletERC20WhitelistCheckersTest is Test {
    uint256 internal primaryPk = 0xA11CE;
    address internal primary = vm.addr(primaryPk);
    address internal backup = vm.addr(0xB0B);
    address internal emergency = vm.addr(0xE911);
    address internal pauseAgent = address(0xBEEF);
    address internal recipient = address(0xB0B0);
    address internal spender = address(0x51ED);
    BaseMERAWallet internal wallet;
    MERAWalletERC20TransferWhitelistChecker internal transferChecker;
    MERAWalletERC20ApproveWhitelistChecker internal approveChecker;
    ERC20Mock internal token;
    MERAWalletUniswapV2AssetWhitelist internal assetWl;
    MERAWalletERC20RecipientWhitelist internal counterpartyWl;

    function _mkWl(address checker, bool allowed, bytes memory config)
        internal
        pure
        returns (MERAWalletTypes.OptionalCheckerUpdate[] memory u)
    {
        u = new MERAWalletTypes.OptionalCheckerUpdate[](1);
        u[0] = MERAWalletTypes.OptionalCheckerUpdate({checker: checker, allowed: allowed, config: config});
    }

    function setUp() public {
        wallet = new BaseMERAWallet(primary, backup, emergency, address(0), address(0));
        transferChecker = new MERAWalletERC20TransferWhitelistChecker(emergency);
        approveChecker = new MERAWalletERC20ApproveWhitelistChecker(emergency);
        token = new ERC20Mock();

        assetWl = new MERAWalletUniswapV2AssetWhitelist(emergency);
        counterpartyWl = new MERAWalletERC20RecipientWhitelist(emergency);

        address[] memory agents = new address[](1);
        agents[0] = pauseAgent;
        bool[] memory agentAllowed = new bool[](1);
        agentAllowed[0] = true;
        vm.startPrank(emergency);
        _setAllRoleTimelocks(0);
        transferChecker.setPauseAgents(agents, agentAllowed);
        approveChecker.setPauseAgents(agents, agentAllowed);
        _setOptionalCheckers(_mkWl(address(0), true, ""));
        vm.stopPrank();
    }

    function _allowTokenAndCounterparty() internal {
        address[] memory a = new address[](1);
        a[0] = address(token);
        bool[] memory ok = new bool[](1);
        ok[0] = true;
        vm.prank(emergency);
        assetWl.setAllowedAssets(a, ok);

        address[] memory c = new address[](2);
        c[0] = recipient;
        c[1] = spender;
        bool[] memory ok2 = new bool[](2);
        ok2[0] = true;
        ok2[1] = true;
        vm.prank(emergency);
        counterpartyWl.setAllowedRecipients(c, ok2);
    }

    function _setAllRoleTimelocks(uint256 delay) internal {
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Primary, delay), 7101
        );
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Backup, delay), 7102
        );
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Emergency, delay), 7103
        );
    }

    function _setOptionalCheckers(MERAWalletTypes.OptionalCheckerUpdate[] memory updates) internal {
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setOptionalCheckers.selector, updates), 7201);
    }

    function _executeWalletSelfCall(bytes memory data, uint256 salt) internal {
        wallet.executeTransaction(_singleCall(address(wallet), 0, data), salt);
    }

    function _singleCall(address target, uint256 value, bytes memory data)
        internal
        pure
        returns (MERAWalletTypes.Call[] memory calls)
    {
        calls = new MERAWalletTypes.Call[](1);
        calls[0] =
            MERAWalletTypes.Call({target: target, value: value, data: data, checker: address(0), checkerData: ""});
    }

    function _cfg() internal view returns (MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory) {
        return MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig({
            assetWhitelist: address(assetWl), recipientWhitelist: address(counterpartyWl)
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
        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(_cfg())));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        wallet.executeTransaction(_transferErc20Calls(address(token), recipient, 100, address(transferChecker)), 1);
        assertEq(token.balanceOf(recipient), 100);
    }

    function test_Transfer_RevertsWhenTokenNotAllowed() public {
        address[] memory c = new address[](1);
        c[0] = recipient;
        bool[] memory ok = new bool[](1);
        ok[0] = true;
        vm.prank(emergency);
        counterpartyWl.setAllowedRecipients(c, ok);

        MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory cfg =
            MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig({
                assetWhitelist: address(assetWl), recipientWhitelist: address(counterpartyWl)
            });
        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(cfg)));

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
        address[] memory a = new address[](1);
        a[0] = address(token);
        bool[] memory ok = new bool[](1);
        ok[0] = true;
        vm.prank(emergency);
        assetWl.setAllowedAssets(a, ok);

        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(_cfg())));

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
        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(_cfg())));

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
        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(_cfg())));

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
        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(_cfg())));

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

    function test_Transfer_RevertsWhenPaused() public {
        _allowTokenAndCounterparty();
        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(_cfg())));

        vm.prank(pauseAgent);
        transferChecker.pause();

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        vm.expectRevert();
        wallet.executeTransaction(_transferErc20Calls(address(token), recipient, 100, address(transferChecker)), 1);
    }

    function test_Transfer_UsesDefaultWhitelistsWhenWalletConfigZero() public {
        address[] memory a = new address[](1);
        a[0] = address(token);
        bool[] memory ok = new bool[](1);
        ok[0] = true;
        vm.prank(emergency);
        assetWl.setAllowedAssets(a, ok);

        address[] memory c = new address[](1);
        c[0] = recipient;
        bool[] memory ok2 = new bool[](1);
        ok2[0] = true;
        vm.prank(emergency);
        counterpartyWl.setAllowedRecipients(c, ok2);

        vm.startPrank(emergency);
        transferChecker.setDefaultAssetWhitelist(address(assetWl));
        transferChecker.setDefaultRecipientWhitelist(address(counterpartyWl));
        MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory emptyCfg =
            MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig({
                assetWhitelist: address(0), recipientWhitelist: address(0)
            });
        _setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(emptyCfg)));
        vm.stopPrank();

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        wallet.executeTransaction(_transferErc20Calls(address(token), recipient, 50, address(transferChecker)), 2);
        assertEq(token.balanceOf(recipient), 50);
    }

    function test_ApplyConfig_EmptyIsNoOp() public {
        vm.prank(address(wallet));
        transferChecker.applyConfig("");
    }

    function test_Approve_HappyPath() public {
        _allowTokenAndCounterparty();
        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(approveChecker), true, abi.encode(_cfg())));

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
        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(approveChecker), true, abi.encode(_cfg())));

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
        address[] memory a = new address[](1);
        a[0] = address(token);
        bool[] memory ok = new bool[](1);
        ok[0] = true;
        vm.prank(emergency);
        assetWl.setAllowedAssets(a, ok);

        address[] memory c = new address[](1);
        c[0] = recipient;
        bool[] memory ok2 = new bool[](1);
        ok2[0] = true;
        vm.prank(emergency);
        counterpartyWl.setAllowedRecipients(c, ok2);

        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(approveChecker), true, abi.encode(_cfg())));

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
}
