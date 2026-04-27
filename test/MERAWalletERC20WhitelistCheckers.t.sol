// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MERAWalletFull} from "../src/extensions/MERAWalletFull.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletERC20TransferWhitelistChecker} from "../src/checkers/MERAWalletERC20TransferWhitelistChecker.sol";
import {MERAWalletERC20ApproveWhitelistChecker} from "../src/checkers/MERAWalletERC20ApproveWhitelistChecker.sol";
import {MERAWalletUniswapV2AssetWhitelist} from "../src/checkers/MERAWalletUniswapV2AssetWhitelist.sol";
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
    MERAWalletFull internal wallet;
    MERAWalletERC20TransferWhitelistChecker internal transferChecker;
    MERAWalletERC20ApproveWhitelistChecker internal approveChecker;
    ERC20Mock internal token;
    MERAWalletUniswapV2AssetWhitelist internal assetWl;
    MERAWalletUniswapV2AssetWhitelist internal counterpartyWl;

    function _mkWl(address checker, bool allowed, bytes memory config)
        internal
        pure
        returns (MERAWalletTypes.OptionalCheckerUpdate[] memory u)
    {
        u = new MERAWalletTypes.OptionalCheckerUpdate[](1);
        u[0] = MERAWalletTypes.OptionalCheckerUpdate({checker: checker, allowed: allowed, config: config});
    }

    function setUp() public {
        wallet = new MERAWalletFull(primary, backup, emergency, address(0), address(0));
        transferChecker = new MERAWalletERC20TransferWhitelistChecker(emergency);
        approveChecker = new MERAWalletERC20ApproveWhitelistChecker(emergency);
        token = new ERC20Mock();

        assetWl = new MERAWalletUniswapV2AssetWhitelist(emergency);
        counterpartyWl = new MERAWalletUniswapV2AssetWhitelist(emergency);

        address[] memory agents = new address[](1);
        agents[0] = pauseAgent;
        bool[] memory agentAllowed = new bool[](1);
        agentAllowed[0] = true;
        vm.startPrank(emergency);
        transferChecker.setPauseAgents(agents, agentAllowed);
        approveChecker.setPauseAgents(agents, agentAllowed);
        wallet.setOptionalCheckers(_mkWl(address(0), true, ""));
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
        counterpartyWl.setAllowedAssets(c, ok2);
    }

    function _cfg() internal view returns (MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory) {
        return MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig({
            assetWhitelist: address(assetWl), recipientWhitelist: address(counterpartyWl)
        });
    }

    function test_Transfer_HappyPath() public {
        _allowTokenAndCounterparty();
        vm.prank(emergency);
        wallet.setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(_cfg())));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        wallet.transferERC20(address(token), recipient, 100, address(transferChecker), "", 1);
        assertEq(token.balanceOf(recipient), 100);
    }

    function test_Transfer_RevertsWhenTokenNotAllowed() public {
        address[] memory c = new address[](1);
        c[0] = recipient;
        bool[] memory ok = new bool[](1);
        ok[0] = true;
        vm.prank(emergency);
        counterpartyWl.setAllowedAssets(c, ok);

        MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory cfg =
            MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig({
                assetWhitelist: address(assetWl), recipientWhitelist: address(counterpartyWl)
            });
        vm.prank(emergency);
        wallet.setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(cfg)));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletERC20WhitelistCheckerErrors.Erc20WhitelistTokenNotAllowed.selector,
                address(token),
                uint256(0)
            )
        );
        wallet.transferERC20(address(token), recipient, 100, address(transferChecker), "", 1);
    }

    function test_Transfer_RevertsWhenRecipientNotAllowed() public {
        address[] memory a = new address[](1);
        a[0] = address(token);
        bool[] memory ok = new bool[](1);
        ok[0] = true;
        vm.prank(emergency);
        assetWl.setAllowedAssets(a, ok);

        vm.prank(emergency);
        wallet.setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(_cfg())));

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
        wallet.transferERC20(address(token), badRecipient, 100, address(transferChecker), "", 1);
    }

    function test_Transfer_RevertsOnWrongSelector() public {
        _allowTokenAndCounterparty();
        vm.prank(emergency);
        wallet.setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(_cfg())));

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
        wallet.setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(_cfg())));

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
        wallet.setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(_cfg())));

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
        wallet.setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(_cfg())));

        vm.prank(pauseAgent);
        transferChecker.pause();

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        vm.expectRevert();
        wallet.transferERC20(address(token), recipient, 100, address(transferChecker), "", 1);
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
        counterpartyWl.setAllowedAssets(c, ok2);

        vm.startPrank(emergency);
        transferChecker.setDefaultAssetWhitelist(address(assetWl));
        transferChecker.setDefaultRecipientWhitelist(address(counterpartyWl));
        MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory emptyCfg =
            MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig({
                assetWhitelist: address(0), recipientWhitelist: address(0)
            });
        wallet.setOptionalCheckers(_mkWl(address(transferChecker), true, abi.encode(emptyCfg)));
        vm.stopPrank();

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        wallet.transferERC20(address(token), recipient, 50, address(transferChecker), "", 2);
        assertEq(token.balanceOf(recipient), 50);
    }

    function test_ApplyConfig_EmptyIsNoOp() public {
        vm.prank(address(wallet));
        transferChecker.applyConfig("");
    }

    function test_Approve_HappyPath() public {
        _allowTokenAndCounterparty();
        vm.prank(emergency);
        wallet.setOptionalCheckers(_mkWl(address(approveChecker), true, abi.encode(_cfg())));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        wallet.approveERC20(address(token), spender, 500, address(approveChecker), "", 1);
        assertEq(token.allowance(address(wallet), spender), 500);
    }

    function test_Approve_RevertsOnWrongSelector() public {
        _allowTokenAndCounterparty();
        vm.prank(emergency);
        wallet.setOptionalCheckers(_mkWl(address(approveChecker), true, abi.encode(_cfg())));

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
        counterpartyWl.setAllowedAssets(c, ok);

        vm.prank(emergency);
        wallet.setOptionalCheckers(_mkWl(address(approveChecker), true, abi.encode(_cfg())));

        token.mint(address(wallet), 1000);
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMERAWalletERC20WhitelistCheckerErrors.Erc20WhitelistCounterpartyNotAllowed.selector,
                spender,
                uint256(0)
            )
        );
        wallet.approveERC20(address(token), spender, 1, address(approveChecker), "", 1);
    }
}
