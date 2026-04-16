// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {IBaseMERAWalletErrors} from "../src/interfaces/IBaseMERAWalletErrors.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletFull} from "../src/extensions/MERAWalletFull.sol";
import {MERAWalletTargetWhitelistChecker} from "../src/whitelist/checkers/MERAWalletTargetWhitelistChecker.sol";
import {MERAWalletTargetBlacklistChecker} from "../src/whitelist/checkers/MERAWalletTargetBlacklistChecker.sol";
import {IMERAWalletWhitelistErrors} from "../src/whitelist/errors/IMERAWalletWhitelistErrors.sol";
import {IMERAWalletBlacklistErrors} from "../src/whitelist/errors/IMERAWalletBlacklistErrors.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ConfigurableTransactionChecker} from "./mocks/ConfigurableTransactionChecker.sol";
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
    MERAWalletTargetWhitelistChecker internal targetWhitelistChecker;
    MERAWalletTargetBlacklistChecker internal targetBlacklistChecker;
    ConfigurableTransactionChecker internal checkerBothHooks;
    ConfigurableTransactionChecker internal checkerAfterOnly;
    ConfigurableTransactionChecker internal checkerBeforeOnly;
    ConfigurableTransactionChecker internal checkerNoHooks;

    function setUp() public {
        wallet = new BaseMERAWallet(primary, backup, emergency, address(0));
        walletWithExtensions = new MERAWalletFull(primary, backup, emergency, address(0));
        receiver = new ReceiverMock();
        token = new ERC20Mock();
        targetWhitelistChecker = new MERAWalletTargetWhitelistChecker(emergency);
        targetBlacklistChecker = new MERAWalletTargetBlacklistChecker(emergency);
        checkerBothHooks = new ConfigurableTransactionChecker(true, true);
        checkerAfterOnly = new ConfigurableTransactionChecker(false, true);
        checkerBeforeOnly = new ConfigurableTransactionChecker(true, false);
        checkerNoHooks = new ConfigurableTransactionChecker(false, false);

        vm.startPrank(emergency);
        wallet.setWhitelistedChecker(address(0), true);
        walletWithExtensions.setWhitelistedChecker(address(0), true);
        vm.stopPrank();
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

    function test_ExecuteTransaction_ImmediateWhenNoTimelockConfigured() public {
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 77));

        vm.prank(primary);
        wallet.executeTransaction(calls, 1);

        assertEq(receiver.value(), 77);
    }

    function test_ExecuteTransaction_RevertsWhenTimelockRequired() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 11));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.TimelockRequired.selector, 1 days));
        wallet.executeTransaction(calls, 1);
    }

    function test_GetRequiredDelay_UsesGlobalWhenPerRoleDelaysAreZero() public {
        vm.startPrank(emergency);
        wallet.setGlobalTimelock(1 days);
        wallet.setTargetCallPolicy(address(receiver), _callPathPolicy(0, false, 0, false));
        wallet.setSelectorCallPolicy(ReceiverMock.setValue.selector, _callPathPolicy(0, false, 0, false));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 42));

        vm.prank(primary);
        uint256 delay = wallet.getRequiredDelay(calls);
        assertEq(delay, 1 days);
    }

    function test_GetRequiredDelay_TargetPrimaryDelayApplies() public {
        vm.startPrank(emergency);
        wallet.setGlobalTimelock(1 days);
        wallet.setTargetCallPolicy(address(receiver), _callPathPolicy(uint120(2 days), false, 0, false));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 101));

        vm.prank(primary);
        uint256 delay = wallet.getRequiredDelay(calls);
        assertEq(delay, 2 days);
    }

    function test_GetRequiredDelay_UsesMaxOfTargetAndSelectorPrimaryDelays() public {
        vm.startPrank(emergency);
        wallet.setGlobalTimelock(1 days);
        wallet.setTargetCallPolicy(address(receiver), _callPathPolicy(uint120(5 days), false, 0, false));
        wallet.setSelectorCallPolicy(ReceiverMock.setValue.selector, _callPathPolicy(uint120(2 days), false, 0, false));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 303));

        vm.prank(primary);
        uint256 delay = wallet.getRequiredDelay(calls);
        assertEq(delay, 5 days);
    }

    function test_GetRequiredDelay_UsesMaxWhenSelectorPrimaryDelayIsHigher() public {
        vm.startPrank(emergency);
        wallet.setGlobalTimelock(1 days);
        wallet.setTargetCallPolicy(address(receiver), _callPathPolicy(uint120(2 days), false, 0, false));
        wallet.setSelectorCallPolicy(ReceiverMock.setValue.selector, _callPathPolicy(uint120(5 days), false, 0, false));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 404));

        vm.prank(primary);
        uint256 delay = wallet.getRequiredDelay(calls);
        assertEq(delay, 5 days);
    }

    function test_GetRequiredDelay_UsesMaxDelayWhenBothDimensionsSet() public {
        vm.startPrank(emergency);
        wallet.setGlobalTimelock(1 days);
        wallet.setTargetCallPolicy(address(receiver), _callPathPolicy(uint120(2 days), false, 0, false));
        wallet.setSelectorCallPolicy(ReceiverMock.setValue.selector, _callPathPolicy(uint120(3 days), false, 0, false));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 505));

        vm.prank(primary);
        uint256 delay = wallet.getRequiredDelay(calls);
        assertEq(delay, 3 days);
    }

    function test_CallPolicyGetters_ReturnStoredPolicy() public {
        vm.startPrank(emergency);
        wallet.setTargetCallPolicy(address(receiver), _callPathPolicy(uint120(123), true, uint120(7), false));
        wallet.setSelectorCallPolicy(
            ReceiverMock.setValue.selector, _callPathPolicy(uint120(456), false, uint120(8), true)
        );
        vm.stopPrank();

        (MERAWalletTypes.RoleCallPolicy memory tPrimary, MERAWalletTypes.RoleCallPolicy memory tBackup) =
            wallet.callPolicyByTarget(address(receiver));
        assertEq(uint256(tPrimary.delay), 123);
        assertTrue(tPrimary.forbidden);
        assertEq(uint256(tBackup.delay), 7);
        assertFalse(tBackup.forbidden);

        (MERAWalletTypes.RoleCallPolicy memory sPrimary, MERAWalletTypes.RoleCallPolicy memory sBackup) =
            wallet.callPolicyBySelector(ReceiverMock.setValue.selector);
        assertEq(uint256(sPrimary.delay), 456);
        assertFalse(sPrimary.forbidden);
        assertEq(uint256(sBackup.delay), 8);
        assertTrue(sBackup.forbidden);
    }

    function test_BackupZeroPerRoleDelayAllowsImmediateExecutionWhilePrimaryStillTimelocked() public {
        // Per-role delays only: global stays 0 so backup max(0,0,0)=0 while primary max(0,1d,0)=1d.
        vm.startPrank(emergency);
        wallet.setTargetCallPolicy(address(receiver), _callPathPolicy(uint120(1 days), false, uint120(0), false));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 2024));

        vm.prank(backup);
        wallet.executeTransaction(calls, 1);

        assertEq(receiver.value(), 2024);
    }

    function test_GetRequiredDelay_RevertsWhenCallPathForbiddenForPrimary() public {
        vm.startPrank(emergency);
        wallet.setTargetCallPolicy(address(receiver), _callPathPolicy(0, true, 0, false));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallPathForbiddenForRole.selector, MERAWalletTypes.Role.Primary
            )
        );
        wallet.getRequiredDelay(calls);
    }

    function test_ProposeAndExecutePending_Lifecycle() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(2 hours);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 314));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        (
            address creator,,
            uint64 createdAt,
            uint64 executeAfter,
            uint256 operationNonce,
            MERAWalletTypes.OperationStatus status
        ) = wallet.operations(operationId);
        assertEq(creator, primary);
        assertEq(operationNonce, 1);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Pending));
        assertEq(uint256(executeAfter), uint256(createdAt) + 2 hours);

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.TimelockNotExpired.selector, uint256(executeAfter), block.timestamp
            )
        );
        wallet.executePending(calls, 1);

        vm.warp(executeAfter);
        vm.prank(primary);
        wallet.executePending(calls, 1);

        assertEq(receiver.value(), 314);
        (,,,,, MERAWalletTypes.OperationStatus finalStatus) = wallet.operations(operationId);
        assertEq(uint256(finalStatus), uint256(MERAWalletTypes.OperationStatus.Executed));
    }

    function test_GetOperationId_DiffersByNonce() public view {
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 501));

        bytes32 operationIdA = wallet.getOperationId(calls, 10);
        bytes32 operationIdB = wallet.getOperationId(calls, 11);

        assertTrue(operationIdA != operationIdB);
    }

    function test_CancelPending_RespectsRoleHierarchy() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 9));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
        wallet.cancelPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Cancelled));
    }

    function test_CancelPending_PrimaryCannotCancelBackupOperation() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 55));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

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
        walletWithExtensions.transferNative(payable(address(receiver)), 1 ether, 1);

        assertEq(address(receiver).balance, 1 ether);
    }

    function test_TransferERC20AndApproveWrappers() public {
        token.mint(address(walletWithExtensions), 1000);

        vm.prank(primary);
        walletWithExtensions.transferERC20(address(token), outsider, 250, 1);
        assertEq(token.balanceOf(outsider), 250);

        vm.prank(primary);
        walletWithExtensions.approveERC20(address(token), outsider, 400, 2);
        assertEq(token.allowance(address(walletWithExtensions), outsider), 400);
    }

    function test_SetRequiredChecker_OnlyEmergencyAndSupportsBothMode() public {
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.NotEmergency.selector);
        walletWithExtensions.setRequiredChecker(address(checkerBothHooks), true);

        vm.prank(emergency);
        walletWithExtensions.setRequiredChecker(address(checkerBothHooks), true);

        address[] memory beforeList = walletWithExtensions.getRequiredBeforeCheckers();
        address[] memory afterList = walletWithExtensions.getRequiredAfterCheckers();
        assertEq(beforeList.length, 1);
        assertEq(afterList.length, 1);
        assertEq(beforeList[0], address(checkerBothHooks));
        assertEq(afterList[0], address(checkerBothHooks));
    }

    function test_TargetWhitelistChecker_BlocksDisallowedTarget() public {
        vm.prank(emergency);
        walletWithExtensions.setRequiredChecker(address(targetWhitelistChecker), true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 777));

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(IMERAWalletWhitelistErrors.TargetNotAllowed.selector, address(receiver), 0)
        );
        walletWithExtensions.executeTransaction(calls, 1);
    }

    function test_TargetWhitelistChecker_AllowsConfiguredTargetsAndWrappers() public {
        vm.deal(address(walletWithExtensions), 2 ether);
        token.mint(address(walletWithExtensions), 1000);

        vm.startPrank(emergency);
        targetWhitelistChecker.setAllowedTarget(address(receiver), true);
        targetWhitelistChecker.setAllowedTarget(address(token), true);
        walletWithExtensions.setRequiredChecker(address(targetWhitelistChecker), true);
        vm.stopPrank();

        vm.prank(primary);
        walletWithExtensions.transferNative(payable(address(receiver)), 1 ether, 1);
        assertEq(address(receiver).balance, 1 ether);

        vm.prank(primary);
        walletWithExtensions.transferERC20(address(token), outsider, 250, 2);
        assertEq(token.balanceOf(outsider), 250);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IMERAWalletWhitelistErrors.TargetNotAllowed.selector, outsider, 0));
        walletWithExtensions.callExternal(outsider, 0, "", 3);
    }

    function test_TargetWhitelistChecker_IsCheckedWhenExecutePending() public {
        vm.prank(emergency);
        walletWithExtensions.setGlobalTimelock(1 days);

        vm.prank(emergency);
        walletWithExtensions.setRequiredChecker(address(targetWhitelistChecker), true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 11));

        vm.prank(primary);
        bytes32 operationId = walletWithExtensions.proposeTransaction(calls, 1);

        (,, uint64 createdAt, uint64 executeAfter,,) = walletWithExtensions.operations(operationId);
        assertEq(uint256(executeAfter), uint256(createdAt) + 1 days);

        vm.warp(executeAfter);
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(IMERAWalletWhitelistErrors.TargetNotAllowed.selector, address(receiver), 0)
        );
        walletWithExtensions.executePending(calls, 1);
    }

    function test_TargetBlacklistChecker_BlocksListedTarget() public {
        vm.startPrank(emergency);
        targetBlacklistChecker.setBlockedTarget(address(receiver), true);
        walletWithExtensions.setRequiredChecker(address(targetBlacklistChecker), true);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 888));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IMERAWalletBlacklistErrors.TargetBlocked.selector, address(receiver), 0));
        walletWithExtensions.executeTransaction(calls, 1);
    }

    function test_TargetBlacklistChecker_AllowsNonBlockedTargets() public {
        vm.startPrank(emergency);
        targetBlacklistChecker.setBlockedTarget(outsider, true);
        walletWithExtensions.setRequiredChecker(address(targetBlacklistChecker), true);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 42));

        vm.prank(primary);
        walletWithExtensions.executeTransaction(calls, 1);
        assertEq(receiver.value(), 42);
    }

    function test_TargetBlacklistChecker_IsCheckedWhenExecutePending() public {
        vm.prank(emergency);
        walletWithExtensions.setGlobalTimelock(1 days);

        vm.startPrank(emergency);
        targetBlacklistChecker.setBlockedTarget(address(receiver), true);
        walletWithExtensions.setRequiredChecker(address(targetBlacklistChecker), true);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 11));

        vm.prank(primary);
        bytes32 operationId = walletWithExtensions.proposeTransaction(calls, 1);

        (,, uint64 createdAt, uint64 executeAfter,,) = walletWithExtensions.operations(operationId);
        assertEq(uint256(executeAfter), uint256(createdAt) + 1 days);

        vm.warp(executeAfter);
        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IMERAWalletBlacklistErrors.TargetBlocked.selector, address(receiver), 0));
        walletWithExtensions.executePending(calls, 1);
    }

    function test_TargetBlacklistChecker_UnblockAllowsAgain() public {
        vm.startPrank(emergency);
        targetBlacklistChecker.setBlockedTarget(address(receiver), true);
        walletWithExtensions.setRequiredChecker(address(targetBlacklistChecker), true);
        targetBlacklistChecker.setBlockedTarget(address(receiver), false);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 100));

        vm.prank(primary);
        walletWithExtensions.executeTransaction(calls, 1);
        assertEq(receiver.value(), 100);
    }

    function test_AfterChecker_RevertsAndRollsBackExecution() public {
        vm.prank(emergency);
        walletWithExtensions.setRequiredChecker(address(checkerAfterOnly), true);

        checkerAfterOnly.configure(false, true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 909));

        vm.prank(primary);
        vm.expectRevert(ConfigurableTransactionChecker.AfterCheckFailed.selector);
        walletWithExtensions.executeTransaction(calls, 1);

        assertEq(receiver.value(), 0);
    }

    function test_SetRequiredChecker_RevertsForNoopConfig() public {
        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.NoopCheckerConfig.selector);
        walletWithExtensions.setRequiredChecker(address(checkerNoHooks), true);
    }

    function test_SetWhitelistedChecker_RevertsForNoopConfigOnNonZeroChecker() public {
        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.NoopCheckerConfig.selector);
        walletWithExtensions.setWhitelistedChecker(address(checkerNoHooks), true);
    }

    function test_ExecuteTransaction_RevertsWhenOptionalCheckerNotWhitelisted() public {
        MERAWalletTypes.Call[] memory calls = _singleCallWithChecker(
            address(receiver),
            0,
            abi.encodeWithSelector(ReceiverMock.setValue.selector, 123),
            address(checkerBothHooks),
            abi.encodePacked(uint256(42))
        );

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.CheckerNotWhitelisted.selector, address(checkerBothHooks), 0)
        );
        walletWithExtensions.executeTransaction(calls, 1);
    }

    function test_ExecuteTransaction_RevertsWhenZeroCheckerNotWhitelisted() public {
        vm.prank(emergency);
        wallet.setWhitelistedChecker(address(0), false);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 456));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CheckerNotWhitelisted.selector, address(0), 0));
        wallet.executeTransaction(calls, 1);
    }

    function test_WhitelistedChecker_BeforeOnlyMode() public {
        vm.prank(emergency);
        walletWithExtensions.setWhitelistedChecker(address(checkerBeforeOnly), true);

        checkerBeforeOnly.configure(true, false);

        MERAWalletTypes.Call[] memory calls = _singleCallWithChecker(
            address(receiver),
            0,
            abi.encodeWithSelector(ReceiverMock.setValue.selector, 888),
            address(checkerBeforeOnly),
            abi.encodePacked(uint256(1))
        );

        vm.prank(primary);
        vm.expectRevert(ConfigurableTransactionChecker.BeforeCheckFailed.selector);
        walletWithExtensions.executeTransaction(calls, 1);
    }

    function test_WhitelistedChecker_AfterOnlyMode() public {
        vm.prank(emergency);
        walletWithExtensions.setWhitelistedChecker(address(checkerAfterOnly), true);

        checkerAfterOnly.configure(false, true);

        MERAWalletTypes.Call[] memory calls = _singleCallWithChecker(
            address(receiver),
            0,
            abi.encodeWithSelector(ReceiverMock.setValue.selector, 909),
            address(checkerAfterOnly),
            abi.encodePacked(uint256(2))
        );

        vm.prank(primary);
        vm.expectRevert(ConfigurableTransactionChecker.AfterCheckFailed.selector);
        walletWithExtensions.executeTransaction(calls, 1);

        assertEq(receiver.value(), 0);
    }

    function _callPathPolicy(uint120 primaryDelay, bool primaryForbidden, uint120 backupDelay, bool backupForbidden)
        internal
        pure
        returns (MERAWalletTypes.CallPathPolicy memory p)
    {
        p.primary = MERAWalletTypes.RoleCallPolicy({delay: primaryDelay, forbidden: primaryForbidden});
        p.backup = MERAWalletTypes.RoleCallPolicy({delay: backupDelay, forbidden: backupForbidden});
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

    function _singleCallWithChecker(
        address target,
        uint256 value,
        bytes memory data,
        address checker,
        bytes memory checkerData
    ) internal pure returns (MERAWalletTypes.Call[] memory calls) {
        calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: target, value: value, data: data, checker: checker, checkerData: checkerData
        });
    }

    function _signDigest(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
