// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {IBaseMERAWalletErrors} from "../src/interfaces/IBaseMERAWalletErrors.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletFull} from "../src/extensions/MERAWalletFull.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ReceiverMock} from "./mocks/ReceiverMock.sol";

contract BaseMERAWalletTest is Test {
    uint256 internal primaryPk = 0xA11CE;
    uint256 internal backupPk = 0xB0B;
    uint256 internal emergencyPk = 0xE911;

    address internal primary = vm.addr(primaryPk);
    address internal backup = vm.addr(backupPk);
    address internal emergency = vm.addr(emergencyPk);
    address internal outsider = address(0x1234);

    BaseMERAWallet internal wallet;
    MERAWalletFull internal walletWithExtensions;
    ReceiverMock internal receiver;
    ERC20Mock internal token;

    function setUp() public {
        wallet = new BaseMERAWallet(primary, backup, emergency, address(0));
        walletWithExtensions = new MERAWalletFull(primary, backup, emergency, address(0));
        receiver = new ReceiverMock();
        token = new ERC20Mock();
    }

    function test_SetPrimary_PrimaryCanSetNewAddress() public {
        address newPrimary = address(0x9999);
        vm.prank(primary);
        wallet.setPrimary(newPrimary);
        assertEq(wallet.primary(), newPrimary);
    }

    function test_SetBackup_Matrix() public {
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.NotAllowedRoleChange.selector);
        wallet.setBackup(primary);

        address newBackup = address(0xBEEF);
        vm.prank(backup);
        wallet.setBackup(newBackup);
        assertEq(wallet.backup(), newBackup);
    }

    function test_EmergencyCanReconfigureAllRoles() public {
        address newPrimary = address(0xAAA1);
        address newBackup = address(0xAAA2);
        address newEmergency = address(0xAAA3);

        vm.startPrank(emergency);
        wallet.setPrimary(newPrimary);
        wallet.setBackup(newBackup);
        wallet.setEmergency(newEmergency);
        vm.stopPrank();

        assertEq(wallet.primary(), newPrimary);
        assertEq(wallet.backup(), newBackup);
        assertEq(wallet.emergency(), newEmergency);
    }

    function test_ExecuteTransaction_ImmediateWhenDelayIsZero() public {
        MERAWalletTypes.Call[] memory calls = _singleCall(
            address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 77)
        );

        vm.prank(primary);
        wallet.executeTransaction(calls);

        assertEq(receiver.value(), 77);
    }

    function test_ExecuteTransaction_RevertsWhenTimelockRequired() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        MERAWalletTypes.Call[] memory calls = _singleCall(
            address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 11)
        );

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.TimelockRequired.selector, 1 days));
        wallet.executeTransaction(calls);
    }

    function test_BackupBypassAllowsImmediateExecution() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);
        vm.prank(emergency);
        wallet.setBackupTargetBypass(address(receiver), true);

        MERAWalletTypes.Call[] memory calls = _singleCall(
            address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 2024)
        );

        vm.prank(backup);
        wallet.executeTransaction(calls);

        assertEq(receiver.value(), 2024);
    }

    function test_ProposeAndExecutePending_Lifecycle() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(2 hours);

        MERAWalletTypes.Call[] memory calls = _singleCall(
            address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 314)
        );

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls);

        (address creator,, uint64 createdAt, uint64 executeAfter, MERAWalletTypes.OperationStatus status) =
            wallet.operations(operationId);
        assertEq(creator, primary);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Pending));
        assertEq(uint256(executeAfter), uint256(createdAt) + 2 hours);

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.TimelockNotExpired.selector, uint256(executeAfter), block.timestamp)
        );
        wallet.executePending(calls);

        vm.warp(executeAfter);
        vm.prank(primary);
        wallet.executePending(calls);

        assertEq(receiver.value(), 314);
        (,,, , MERAWalletTypes.OperationStatus finalStatus) = wallet.operations(operationId);
        assertEq(uint256(finalStatus), uint256(MERAWalletTypes.OperationStatus.Executed));
    }

    function test_CancelPending_RespectsRoleHierarchy() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        MERAWalletTypes.Call[] memory calls = _singleCall(
            address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 9)
        );

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls);

        vm.prank(backup);
        wallet.cancelPending(operationId);

        (,,, , MERAWalletTypes.OperationStatus status) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Cancelled));
    }

    function test_CancelPending_PrimaryCannotCancelBackupOperation() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        MERAWalletTypes.Call[] memory calls = _singleCall(
            address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 55)
        );

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CannotCancelOperation.selector, operationId));
        wallet.cancelPending(operationId);
    }

    function test_IsValidSignature_RequiresDedicatedSigner() public {
        bytes32 digest = keccak256("mera-wallet");

        bytes memory primarySignature = _signDigest(primaryPk, digest);
        bytes memory backupSignature = _signDigest(backupPk, digest);

        // No EIP-1271 signer configured: always reject (invalid magic).
        assertEq(uint256(uint32(wallet.isValidSignature(digest, primarySignature))), uint256(uint32(0xffffffff)));
        assertEq(uint256(uint32(wallet.isValidSignature(digest, backupSignature))), uint256(uint32(0xffffffff)));

        vm.prank(emergency);
        wallet.set1271Signer(backup);

        assertEq(uint256(uint32(wallet.isValidSignature(digest, backupSignature))), uint256(uint32(0x1626ba7e)));
        assertEq(uint256(uint32(wallet.isValidSignature(digest, primarySignature))), uint256(uint32(0xffffffff)));
    }

    function test_TransferNativeWrapper_ExecutesSingleCall() public {
        vm.deal(address(walletWithExtensions), 2 ether);

        vm.prank(primary);
        walletWithExtensions.transferNative(payable(address(receiver)), 1 ether);

        assertEq(address(receiver).balance, 1 ether);
    }

    function test_TransferERC20AndApproveWrappers() public {
        token.mint(address(walletWithExtensions), 1000);

        vm.prank(primary);
        walletWithExtensions.transferERC20(address(token), outsider, 250);
        assertEq(token.balanceOf(outsider), 250);

        vm.prank(primary);
        walletWithExtensions.approveERC20(address(token), outsider, 400);
        assertEq(token.allowance(address(walletWithExtensions), outsider), 400);
    }

    function _singleCall(address target, uint256 value, bytes memory data)
        internal
        pure
        returns (MERAWalletTypes.Call[] memory calls)
    {
        calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({target: target, value: value, data: data});
    }

    function _signDigest(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
