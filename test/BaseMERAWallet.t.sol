// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {IBaseMERAWalletErrors} from "../src/interfaces/IBaseMERAWalletErrors.sol";
import {MERAWalletConstants} from "../src/constants/MERAWalletConstants.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletFull} from "../src/extensions/MERAWalletFull.sol";
import {MERAWalletTargetWhitelistChecker} from "../src/checkers/MERAWalletTargetWhitelistChecker.sol";
import {MERAWalletTargetBlacklistChecker} from "../src/checkers/MERAWalletTargetBlacklistChecker.sol";
import {MERAWalletWhitelistTypes} from "../src/checkers/types/MERAWalletWhitelistTypes.sol";
import {IMERAWalletWhitelistErrors} from "../src/checkers/errors/IMERAWalletWhitelistErrors.sol";
import {MERAWalletUniswapV2OracleSlippageChecker} from "../src/checkers/MERAWalletUniswapV2OracleSlippageChecker.sol";
import {MERAWalletUniswapV2AssetWhitelist} from "../src/checkers/MERAWalletUniswapV2AssetWhitelist.sol";
import {MERAWalletUniswapV2SlippageTypes} from "../src/checkers/types/MERAWalletUniswapV2SlippageTypes.sol";
import {IMERAWalletBlacklistErrors} from "../src/checkers/errors/IMERAWalletBlacklistErrors.sol";
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
    address internal agentAddr = address(0xA61);

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
        wallet = new BaseMERAWallet(primary, backup, emergency, address(0), address(0));
        walletWithExtensions = new MERAWalletFull(primary, backup, emergency, address(0), address(0));
        receiver = new ReceiverMock();
        token = new ERC20Mock();
        targetWhitelistChecker = new MERAWalletTargetWhitelistChecker(emergency, address(walletWithExtensions));
        targetBlacklistChecker = new MERAWalletTargetBlacklistChecker(emergency, address(walletWithExtensions));
        checkerBothHooks = new ConfigurableTransactionChecker(true, true, address(walletWithExtensions));
        checkerAfterOnly = new ConfigurableTransactionChecker(false, true, address(walletWithExtensions));
        checkerBeforeOnly = new ConfigurableTransactionChecker(true, false, address(walletWithExtensions));
        checkerNoHooks = new ConfigurableTransactionChecker(false, false, address(walletWithExtensions));

        vm.startPrank(emergency);
        wallet.setWhitelistedCheckers(_mkWl(address(0), true, ""));
        walletWithExtensions.setWhitelistedCheckers(_mkWl(address(0), true, ""));
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

    function test_SetEmergency_GuardianCanRotate() public {
        address guardianAddr = vm.addr(0xCAFE);
        BaseMERAWallet w = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddr);

        address newEmergency = address(0xE2E2);
        vm.prank(guardianAddr);
        w.setEmergency(newEmergency);
        assertEq(w.emergency(), newEmergency);
    }

    function test_SetEmergency_OutsiderRevertsWithoutGuardian() public {
        address newEmergency = address(0xE4E4);
        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.NotEmergency.selector);
        wallet.setEmergency(newEmergency);
    }

    function test_LifeControllers_InitialEmergencyIncluded() public view {
        assertTrue(wallet.isLifeController(emergency));
    }

    function test_SetLifeControl_EnableRequiresNonZeroTimeout() public {
        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.LifeHeartbeatTimeoutZero.selector);
        wallet.setLifeControl(true, 0);
    }

    function test_SetGlobalTimelock_MaxDelaySucceeds() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(MERAWalletConstants.MAX_TIMELOCK_DELAY);
        assertEq(wallet.globalTimelock(), MERAWalletConstants.MAX_TIMELOCK_DELAY);
    }

    function test_SetGlobalTimelock_DelayAboveMaxReverts() public {
        vm.prank(emergency);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.TimelockDelayTooLarge.selector,
                MERAWalletConstants.MAX_TIMELOCK_DELAY + 1,
                MERAWalletConstants.MAX_TIMELOCK_DELAY
            )
        );
        wallet.setGlobalTimelock(MERAWalletConstants.MAX_TIMELOCK_DELAY + 1);
    }

    function test_ExecuteTransaction_TooManyCallsReverts() public {
        MERAWalletTypes.Call[] memory calls =
            _repeatedCalls(address(receiver), MERAWalletConstants.MAX_CALLS_PER_BATCH + 1);
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.TooManyCalls.selector,
                MERAWalletConstants.MAX_CALLS_PER_BATCH + 1,
                MERAWalletConstants.MAX_CALLS_PER_BATCH
            )
        );
        wallet.executeTransaction(calls, 1);
    }

    function test_LifeControl_Expiry_RevertsSetGlobalTimelockUntilHeartbeat() public {
        vm.prank(emergency);
        wallet.setLifeControl(true, 1 days);

        vm.warp(block.timestamp + 2 days);

        uint256 lastHeartbeatAt = wallet.lastLifeHeartbeatAt();
        uint256 timeout = wallet.lifeHeartbeatTimeout();
        vm.prank(emergency);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.LifeHeartbeatExpired.selector, lastHeartbeatAt, timeout, block.timestamp
            )
        );
        wallet.setGlobalTimelock(1 days);

        vm.prank(emergency);
        wallet.confirmAlive();

        vm.prank(emergency);
        wallet.setGlobalTimelock(2 days);
        assertEq(wallet.globalTimelock(), 2 days);
    }

    function test_LifeControl_AnyControllerHeartbeatUnblocksExecution() public {
        address[] memory controllers = new address[](1);
        controllers[0] = outsider;

        vm.startPrank(emergency);
        wallet.setLifeControllers(controllers, true);
        wallet.setLifeControl(true, 1 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 88));
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.LifeHeartbeatExpired.selector,
                wallet.lastLifeHeartbeatAt(),
                wallet.lifeHeartbeatTimeout(),
                block.timestamp
            )
        );
        wallet.executeTransaction(calls, 1);

        vm.prank(outsider);
        wallet.confirmAlive();

        vm.prank(primary);
        wallet.executeTransaction(calls, 1);
        assertEq(receiver.value(), 88);
    }

    function test_LifeControl_EmergencyCannotBeRemovedFromControllers() public {
        address[] memory controllers = new address[](1);
        controllers[0] = emergency;

        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.EmergencyMustStayLifeController.selector);
        wallet.setLifeControllers(controllers, false);
    }

    function test_SetEmergency_SyncsLifeControllerMembership() public {
        address newEmergency = address(0xE700);

        vm.prank(emergency);
        wallet.setEmergency(newEmergency);

        assertFalse(wallet.isLifeController(emergency));
        assertTrue(wallet.isLifeController(newEmergency));
    }

    function test_SetEmergency_RemovesPreviousLifeControllerEvenIfPreviouslyInSetLifeControllers() public {
        address[] memory controllers = new address[](1);
        controllers[0] = emergency;
        vm.prank(emergency);
        wallet.setLifeControllers(controllers, true);

        address newEmergency = address(0xE701);
        vm.prank(emergency);
        wallet.setEmergency(newEmergency);

        assertFalse(wallet.isLifeController(emergency));
        assertTrue(wallet.isLifeController(newEmergency));
    }

    function test_LifeControl_BlocksExtensionCallsUntilHeartbeat() public {
        vm.prank(emergency);
        walletWithExtensions.setLifeControl(true, 1 days);

        vm.deal(address(walletWithExtensions), 1 ether);
        vm.warp(block.timestamp + 2 days);

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.LifeHeartbeatExpired.selector,
                walletWithExtensions.lastLifeHeartbeatAt(),
                walletWithExtensions.lifeHeartbeatTimeout(),
                block.timestamp
            )
        );
        walletWithExtensions.transferNative(payable(outsider), 0.1 ether, 1);

        vm.prank(emergency);
        walletWithExtensions.confirmAlive();

        uint256 outsiderBalanceBefore = outsider.balance;
        vm.prank(primary);
        walletWithExtensions.transferNative(payable(outsider), 0.1 ether, 1);
        assertEq(outsider.balance, outsiderBalanceBefore + 0.1 ether);
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
        _policyTarget(address(receiver), _inactiveCallPathPolicy(0, false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _inactiveCallPathPolicy(0, false, 0, false));
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
        _policyTarget(address(receiver), _callPathPolicy(uint56(2 days), false, 0, false));
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
        _policyTarget(address(receiver), _callPathPolicy(uint56(5 days), false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(2 days), false, 0, false));
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
        _policyTarget(address(receiver), _callPathPolicy(uint56(2 days), false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(5 days), false, 0, false));
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
        _policyTarget(address(receiver), _callPathPolicy(uint56(2 days), false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(3 days), false, 0, false));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 505));

        vm.prank(primary);
        uint256 delay = wallet.getRequiredDelay(calls);
        assertEq(delay, 3 days);
    }

    function test_GetRequiredDelay_PairPolicyOverridesSeparateTargetAndSelector() public {
        vm.startPrank(emergency);
        wallet.setGlobalTimelock(1 days);
        _policyTarget(address(receiver), _callPathPolicy(uint56(5 days), false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(2 days), false, 0, false));
        _policyPair(
            address(receiver), ReceiverMock.setValue.selector, _pairCallPathPolicy(uint56(1 days), false, 0, false)
        );
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 606));

        vm.prank(primary);
        assertEq(wallet.getRequiredDelay(calls), 1 days);
    }

    function test_GetRequiredDelay_AfterClearPairPolicy_UsesMaxOfTargetAndSelector() public {
        vm.startPrank(emergency);
        wallet.setGlobalTimelock(1 days);
        _policyTarget(address(receiver), _callPathPolicy(uint56(5 days), false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(2 days), false, 0, false));
        _policyPair(
            address(receiver), ReceiverMock.setValue.selector, _pairCallPathPolicy(uint56(1 days), false, 0, false)
        );
        _policyPair(address(receiver), ReceiverMock.setValue.selector, _inactiveCallPathPolicy(0, false, 0, false));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 707));

        vm.prank(primary);
        assertEq(wallet.getRequiredDelay(calls), 5 days);
    }

    function test_GetRequiredDelay_PairPolicyZeroPrimaryDelayReturnsZero() public {
        vm.startPrank(emergency);
        wallet.setGlobalTimelock(1 days);
        _policyTarget(address(receiver), _callPathPolicy(uint56(5 days), false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(2 days), false, 0, false));
        _policyPair(address(receiver), ReceiverMock.setValue.selector, _pairCallPathPolicy(0, false, 0, false));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 808));

        vm.prank(primary);
        assertEq(wallet.getRequiredDelay(calls), 0);
    }

    function test_GetRequiredDelay_RevertsWhenPairCallPathForbiddenForPrimary() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(0, false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(0, false, 0, false));
        _policyPair(address(receiver), ReceiverMock.setValue.selector, _pairCallPathPolicy(0, true, 0, false));
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

    function test_SetTargetSelectorCallPolicy_Clear_RevertsWhenNotConfigured() public {
        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.NoopTargetSelectorCallPolicy.selector);
        _policyPair(address(receiver), ReceiverMock.setValue.selector, _inactiveCallPathPolicy(0, false, 0, false));
    }

    function test_CallPolicyByTargetSelector_PublicGetter_ReturnsStored() public {
        MERAWalletTypes.CallPathPolicy memory stored = _pairCallPathPolicy(uint56(9 days), false, uint56(1 days), true);
        vm.prank(emergency);
        _policyPair(address(receiver), ReceiverMock.setValue.selector, stored);

        (
            MERAWalletTypes.RoleCallPolicy memory readPrimary,
            MERAWalletTypes.RoleCallPolicy memory readBackup,
            bool readExists
        ) = wallet.callPolicyByTargetSelector(address(receiver), ReceiverMock.setValue.selector);
        assertTrue(readExists);
        assertEq(uint256(readPrimary.delay), 9 days);
        assertFalse(readPrimary.forbidden);
        assertEq(uint256(readBackup.delay), 1 days);
        assertTrue(readBackup.forbidden);
    }

    function test_CallPolicyGetters_ReturnStoredPolicy() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(uint56(123), true, uint56(7), false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(456), false, uint56(8), true));
        vm.stopPrank();

        (MERAWalletTypes.RoleCallPolicy memory tPrimary, MERAWalletTypes.RoleCallPolicy memory tBackup, bool tExists) =
            wallet.callPolicyByTarget(address(receiver));
        assertTrue(tExists);
        assertEq(uint256(tPrimary.delay), 123);
        assertTrue(tPrimary.forbidden);
        assertEq(uint256(tBackup.delay), 7);
        assertFalse(tBackup.forbidden);

        (MERAWalletTypes.RoleCallPolicy memory sPrimary, MERAWalletTypes.RoleCallPolicy memory sBackup, bool sExists) =
            wallet.callPolicyBySelector(ReceiverMock.setValue.selector);
        assertTrue(sExists);
        assertEq(uint256(sPrimary.delay), 456);
        assertFalse(sPrimary.forbidden);
        assertEq(uint256(sBackup.delay), 8);
        assertTrue(sBackup.forbidden);
    }

    function test_BackupZeroPerRoleDelayAllowsImmediateExecutionWhilePrimaryStillTimelocked() public {
        // Per-role delays only: global stays 0 so backup max(0,0,0)=0 while primary max(0,1d,0)=1d.
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(uint56(1 days), false, uint56(0), false));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 2024));

        vm.prank(backup);
        wallet.executeTransaction(calls, 1);

        assertEq(receiver.value(), 2024);
    }

    function test_GetRequiredDelay_RevertsWhenCallPathForbiddenForPrimary() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(0, true, 0, false));
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
            uint256 operationSalt,
            MERAWalletTypes.OperationStatus status,
            MERAWalletTypes.RelayExecutorPolicy relayPolicy,
            uint256 relayReward,
            address designatedExecutor,
            bytes32 executorSetHash
        ) = wallet.operations(operationId);
        assertEq(creator, primary);
        assertEq(operationSalt, 1);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Pending));
        assertEq(uint256(relayPolicy), uint256(MERAWalletTypes.RelayExecutorPolicy.CoreExecute));
        assertEq(relayReward, 0);
        assertEq(designatedExecutor, address(0));
        assertEq(executorSetHash, bytes32(0));
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
        (,,,,, MERAWalletTypes.OperationStatus finalStatus,,,,) = wallet.operations(operationId);
        assertEq(uint256(finalStatus), uint256(MERAWalletTypes.OperationStatus.Executed));
    }

    function test_GetOperationId_DiffersBySalt() public view {
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 501));

        bytes32 operationIdA = wallet.getOperationId(calls, 10);
        bytes32 operationIdB = wallet.getOperationId(calls, 11);

        assertTrue(operationIdA != operationIdB);
    }

    function test_CancelPending_OnlyPrimaryMayCancel() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 9));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
        vm.expectRevert(IBaseMERAWalletErrors.CancelPendingPrimaryOnly.selector);
        wallet.cancelPending(operationId);

        vm.prank(primary);
        wallet.cancelPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Cancelled));
    }

    function test_ProposeTransaction_RevertsWhenOperationIdWasCancelledBefore() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 9));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(primary);
        wallet.cancelPending(operationId);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.OperationAlreadyUsed.selector, operationId));
        wallet.proposeTransaction(calls, 1);
    }

    function test_ProposeTransaction_RevertsWhenOperationIdWasExecutedBefore() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 77));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.warp(block.timestamp + 1 days);
        vm.prank(primary);
        wallet.executePending(calls, 1);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.OperationAlreadyUsed.selector, operationId));
        wallet.proposeTransaction(calls, 1);
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
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(checkerBothHooks), true);
            walletWithExtensions.setRequiredCheckers(__rqA, __rqB);
        }

        vm.prank(emergency);
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(checkerBothHooks), true);
            walletWithExtensions.setRequiredCheckers(__rqA, __rqB);
        }

        address[] memory beforeList = walletWithExtensions.getRequiredBeforeCheckers();
        address[] memory afterList = walletWithExtensions.getRequiredAfterCheckers();
        assertEq(beforeList.length, 1);
        assertEq(afterList.length, 1);
        assertEq(beforeList[0], address(checkerBothHooks));
        assertEq(afterList[0], address(checkerBothHooks));
    }

    function test_TargetWhitelistChecker_BlocksDisallowedTarget() public {
        vm.prank(emergency);
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(targetWhitelistChecker), true);
            walletWithExtensions.setRequiredCheckers(__rqA, __rqB);
        }

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
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(targetWhitelistChecker), true);
            walletWithExtensions.setRequiredCheckers(__rqA, __rqB);
        }
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
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(targetWhitelistChecker), true);
            walletWithExtensions.setRequiredCheckers(__rqA, __rqB);
        }

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 11));

        vm.prank(primary);
        bytes32 operationId = walletWithExtensions.proposeTransaction(calls, 1);

        (,, uint64 createdAt, uint64 executeAfter,,,,,,) = walletWithExtensions.operations(operationId);
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
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(targetBlacklistChecker), true);
            walletWithExtensions.setRequiredCheckers(__rqA, __rqB);
        }
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
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(targetBlacklistChecker), true);
            walletWithExtensions.setRequiredCheckers(__rqA, __rqB);
        }
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
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(targetBlacklistChecker), true);
            walletWithExtensions.setRequiredCheckers(__rqA, __rqB);
        }
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 11));

        vm.prank(primary);
        bytes32 operationId = walletWithExtensions.proposeTransaction(calls, 1);

        (,, uint64 createdAt, uint64 executeAfter,,,,,,) = walletWithExtensions.operations(operationId);
        assertEq(uint256(executeAfter), uint256(createdAt) + 1 days);

        vm.warp(executeAfter);
        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IMERAWalletBlacklistErrors.TargetBlocked.selector, address(receiver), 0));
        walletWithExtensions.executePending(calls, 1);
    }

    function test_TargetBlacklistChecker_UnblockAllowsAgain() public {
        vm.startPrank(emergency);
        targetBlacklistChecker.setBlockedTarget(address(receiver), true);
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(targetBlacklistChecker), true);
            walletWithExtensions.setRequiredCheckers(__rqA, __rqB);
        }
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
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(checkerAfterOnly), true);
            walletWithExtensions.setRequiredCheckers(__rqA, __rqB);
        }

        checkerAfterOnly.configure(false, true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 909));

        vm.prank(primary);
        vm.expectRevert(ConfigurableTransactionChecker.AfterCheckFailed.selector);
        walletWithExtensions.executeTransaction(calls, 1);

        assertEq(receiver.value(), 0);
    }

    function test_ControllerAgent_CannotExecute_IsVetoOnly() public {
        vm.prank(primary);
        _agentsCall(wallet, agentAddr, true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 33));

        vm.prank(agentAddr);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        wallet.executeTransaction(calls, 1);
    }

    function test_ControllerAgent_BackupCanAssignVetoAgent() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);
        (bool en,) = wallet.controllerAgents(agentAddr);
        assertTrue(en);
    }

    function test_ControllerAgent_OutsiderCannotSetOrRemove() public {
        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.NotCoreController.selector);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(primary);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.NotCoreController.selector);
        _agentsCall(wallet, agentAddr, false);
    }

    function test_ControllerAgent_AgentCannotAssignAnotherAgent() public {
        address secondAgent = address(0xA62);

        vm.prank(primary);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(agentAddr);
        vm.expectRevert(IBaseMERAWalletErrors.NotCoreController.selector);
        _agentsCall(wallet, secondAgent, true);
    }

    function test_ControllerAgent_PrimaryScoped_RemovedByPrimaryOrHigher() public {
        vm.prank(primary);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.NotCoreController.selector);
        _agentsCall(wallet, agentAddr, false);

        vm.prank(primary);
        _agentsCall(wallet, agentAddr, false);
        (bool enAfterPrimary,) = wallet.controllerAgents(agentAddr);
        assertFalse(enAfterPrimary);

        vm.prank(primary);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(backup);
        _agentsCall(wallet, agentAddr, false);
        (bool enAfterBackup,) = wallet.controllerAgents(agentAddr);
        assertFalse(enAfterBackup);
    }

    function test_ControllerAgent_EmergencyScoped_OnlyEmergencyRemoves() public {
        vm.prank(emergency);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.AgentRemovalNotAuthorized.selector);
        _agentsCall(wallet, agentAddr, false);

        vm.prank(backup);
        vm.expectRevert(IBaseMERAWalletErrors.AgentRemovalNotAuthorized.selector);
        _agentsCall(wallet, agentAddr, false);

        vm.prank(emergency);
        _agentsCall(wallet, agentAddr, false);
        (bool en,) = wallet.controllerAgents(agentAddr);
        assertFalse(en);
    }

    function test_ControllerAgent_BackupAssigned_OnlyBackupOrHigherRemoves() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.AgentRemovalNotAuthorized.selector);
        _agentsCall(wallet, agentAddr, false);

        vm.prank(backup);
        _agentsCall(wallet, agentAddr, false);
        (bool en,) = wallet.controllerAgents(agentAddr);
        assertFalse(en);
    }

    function test_ControllerAgent_VetoAgent_VetoClearExecute_Lifecycle() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 9));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Vetoed));

        (,,, uint64 executeAfter,,,,,,) = wallet.operations(operationId);
        vm.warp(executeAfter);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.OperationVetoed.selector, operationId));
        wallet.executePending(calls, 1);

        vm.prank(backup);
        wallet.clearVeto(operationId);

        (,,,,, MERAWalletTypes.OperationStatus statusAfter,,,,) = wallet.operations(operationId);
        assertEq(uint256(statusAfter), uint256(MERAWalletTypes.OperationStatus.Pending));

        vm.prank(primary);
        wallet.executePending(calls, 1);
        assertEq(receiver.value(), 9);
    }

    function test_ControllerAgent_CannotVetoEmergencyProposedOperation() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 7));

        vm.prank(emergency);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        vm.expectRevert(IBaseMERAWalletErrors.AgentCannotVetoEmergencyOperation.selector);
        wallet.vetoPending(operationId);
    }

    function test_ControllerAgent_CannotCancelPending() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 3));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        wallet.cancelPending(operationId);
    }

    function test_CancelPending_AfterVeto_Irreversible() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 21));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        vm.prank(primary);
        wallet.cancelPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Cancelled));
    }

    function test_ControllerAgent_CoreRoleUnaffectedByVetoSlotOnPrimaryAddress() public {
        vm.startPrank(emergency);
        wallet.setGlobalTimelock(1 days);
        _agentsCall(wallet, primary, true);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 7));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.TimelockRequired.selector, 1 days));
        wallet.executeTransaction(calls, 1);
    }

    function test_ControllerAgent_DisableWhenNotEnabled_Reverts() public {
        vm.prank(backup);
        vm.expectRevert(IBaseMERAWalletErrors.NoopControllerAgent.selector);
        _agentsCall(wallet, agentAddr, false);
    }

    function test_SetRequiredChecker_RevertsForNoopConfig() public {
        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.NoopCheckerConfig.selector);
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(checkerNoHooks), true);
            walletWithExtensions.setRequiredCheckers(__rqA, __rqB);
        }
    }

    function test_SetWhitelistedChecker_RevertsForNoopConfigOnNonZeroChecker() public {
        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.NoopCheckerConfig.selector);
        walletWithExtensions.setWhitelistedCheckers(_mkWl(address(checkerNoHooks), true, ""));
    }

    function test_SetWhitelistedChecker_AppliesConfigToTargetWhitelistChecker() public {
        MERAWalletTargetWhitelistChecker wl =
            new MERAWalletTargetWhitelistChecker(emergency, address(walletWithExtensions));
        MERAWalletWhitelistTypes.TargetPermission[] memory perms = new MERAWalletWhitelistTypes.TargetPermission[](1);
        perms[0] = MERAWalletWhitelistTypes.TargetPermission({target: address(receiver), allowed: true});

        vm.prank(emergency);
        walletWithExtensions.setWhitelistedCheckers(_mkWl(address(wl), true, abi.encode(perms)));

        assertTrue(wl.allowedTarget(address(receiver)));
        (bool allowed,,) = walletWithExtensions.whitelistedChecker(address(wl));
        assertTrue(allowed);
    }

    function test_SetWhitelistedChecker_AppliesSlippageCheckerAssetWhitelistConfig() public {
        MERAWalletUniswapV2OracleSlippageChecker slip =
            new MERAWalletUniswapV2OracleSlippageChecker(emergency, 100, 3600);
        MERAWalletUniswapV2AssetWhitelist aw = new MERAWalletUniswapV2AssetWhitelist(emergency);
        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg =
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({assetWhitelist: address(aw)});

        vm.startPrank(emergency);
        walletWithExtensions.setWhitelistedCheckers(_mkWl(address(slip), true, abi.encode(cfg)));
        vm.stopPrank();

        (address storedWl) = slip.walletSlippageCheckerConfig(address(walletWithExtensions));
        assertEq(storedWl, address(aw));
    }

    function test_TargetWhitelistChecker_ApplyConfig_EmptyNoOp() public {
        assertFalse(targetWhitelistChecker.allowedTarget(address(receiver)));
        targetWhitelistChecker.applyConfig("");
        assertFalse(targetWhitelistChecker.allowedTarget(address(receiver)));
    }

    function test_TargetWhitelistChecker_ApplyConfig_RevertsWhenUnauthorized() public {
        MERAWalletWhitelistTypes.TargetPermission[] memory perms = new MERAWalletWhitelistTypes.TargetPermission[](1);
        perms[0] = MERAWalletWhitelistTypes.TargetPermission({target: address(receiver), allowed: true});

        vm.prank(outsider);
        vm.expectRevert(IMERAWalletWhitelistErrors.WhitelistConfigNotAuthorized.selector);
        targetWhitelistChecker.applyConfig(abi.encode(perms));
    }

    function test_SetWhitelistedChecker_AppliesConfigToConfigurableChecker() public {
        bytes memory cfg = abi.encode(true, false);
        vm.prank(emergency);
        walletWithExtensions.setWhitelistedCheckers(_mkWl(address(checkerBeforeOnly), true, cfg));
        assertTrue(checkerBeforeOnly.revertBefore());
        assertFalse(checkerBeforeOnly.revertAfter());
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
        wallet.setWhitelistedCheckers(_mkWl(address(0), false, ""));

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 456));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CheckerNotWhitelisted.selector, address(0), 0));
        wallet.executeTransaction(calls, 1);
    }

    function test_WhitelistedChecker_BeforeOnlyMode() public {
        vm.prank(emergency);
        walletWithExtensions.setWhitelistedCheckers(_mkWl(address(checkerBeforeOnly), true, ""));

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
        walletWithExtensions.setWhitelistedCheckers(_mkWl(address(checkerAfterOnly), true, ""));

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

    function test_Freeze_BackupAndEmergency_MayToggleFrozenPrimary() public {
        vm.prank(backup);
        wallet.setFrozenPrimary(true);
        assertTrue(wallet.frozenPrimary());

        vm.prank(emergency);
        wallet.setFrozenPrimary(false);
        assertFalse(wallet.frozenPrimary());
    }

    function test_Freeze_PrimaryCannotSetFrozenPrimary() public {
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.FreezeActionNotAuthorized.selector);
        wallet.setFrozenPrimary(true);
    }

    function test_Freeze_BackupCannotSetFrozenBackup() public {
        vm.prank(backup);
        vm.expectRevert(IBaseMERAWalletErrors.FreezeActionNotAuthorized.selector);
        wallet.setFrozenBackup(true);
    }

    function test_Freeze_EmergencyMayToggleFrozenBackup() public {
        vm.prank(emergency);
        wallet.setFrozenBackup(true);
        assertTrue(wallet.frozenBackup());

        vm.prank(emergency);
        wallet.setFrozenBackup(false);
        assertFalse(wallet.frozenBackup());
    }

    function test_Freeze_BackupLevelAgent_SetsFrozenBackup_CannotUnfreeze() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(agentAddr);
        wallet.setFrozenBackup(true);
        assertTrue(wallet.frozenBackup());

        vm.prank(agentAddr);
        vm.expectRevert(IBaseMERAWalletErrors.FreezeActionNotAuthorized.selector);
        wallet.setFrozenBackup(false);

        vm.prank(emergency);
        wallet.setFrozenBackup(false);
        assertFalse(wallet.frozenBackup());
    }

    function test_Freeze_PrimaryScopedAgent_CannotSetFrozenBackup() public {
        vm.prank(primary);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(agentAddr);
        vm.expectRevert(IBaseMERAWalletErrors.FreezeActionNotAuthorized.selector);
        wallet.setFrozenBackup(true);
    }

    function test_FrozenPrimary_PrimaryCannotExecuteOrProposeOrGetDelay() public {
        vm.prank(backup);
        wallet.setFrozenPrimary(true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Primary));
        wallet.executeTransaction(calls, 1);

        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Primary));
        wallet.proposeTransaction(calls, 2);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Primary));
        wallet.getRequiredDelay(calls);
    }

    function test_FrozenPrimary_BackupCanExecute() public {
        vm.prank(backup);
        wallet.setFrozenPrimary(true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 55));

        vm.prank(backup);
        wallet.executeTransaction(calls, 1);
        assertEq(receiver.value(), 55);
    }

    function test_FrozenPrimary_PrimaryCannotSetPrimary_BackupCan() public {
        vm.prank(backup);
        wallet.setFrozenPrimary(true);

        address newPrimary = address(0x7001);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Primary));
        wallet.setPrimary(newPrimary);

        vm.prank(backup);
        wallet.setPrimary(newPrimary);
        assertEq(wallet.primary(), newPrimary);
    }

    function test_FrozenPrimary_PrimaryCannotSetControllerAgent_BackupCan() public {
        vm.prank(backup);
        wallet.setFrozenPrimary(true);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Primary));
        _agentsCall(wallet, agentAddr, true);

        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);
        (bool en,) = wallet.controllerAgents(agentAddr);
        assertTrue(en);
    }

    function test_FrozenBackup_BackupCannotExecute_EmergencyCan() public {
        vm.prank(emergency);
        wallet.setFrozenBackup(true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 66));

        vm.prank(backup);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Backup));
        wallet.executeTransaction(calls, 1);

        vm.prank(emergency);
        wallet.executeTransaction(calls, 1);
        assertEq(receiver.value(), 66);
    }

    function test_FrozenBoth_OnlyEmergencyExecutes() public {
        vm.startPrank(emergency);
        wallet.setFrozenPrimary(true);
        wallet.setFrozenBackup(true);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 77));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Primary));
        wallet.executeTransaction(calls, 1);

        vm.prank(backup);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Backup));
        wallet.executeTransaction(calls, 2);

        vm.prank(emergency);
        wallet.executeTransaction(calls, 3);
        assertEq(receiver.value(), 77);
    }

    function test_FreezePrimaryByAgent_SetsFrozen_AgentCannotUnfreeze() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(agentAddr);
        wallet.setFrozenPrimary(true);
        assertTrue(wallet.frozenPrimary());

        vm.prank(agentAddr);
        vm.expectRevert(IBaseMERAWalletErrors.FreezeActionNotAuthorized.selector);
        wallet.setFrozenPrimary(false);

        vm.prank(backup);
        wallet.setFrozenPrimary(false);
        assertFalse(wallet.frozenPrimary());
    }

    function test_FreezePrimaryByAgent_OutsiderReverts() public {
        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.FreezeActionNotAuthorized.selector);
        wallet.setFrozenPrimary(true);
    }

    function test_FrozenPrimary_AgentVetoPending_StillWorks() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 8));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
        wallet.setFrozenPrimary(true);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Vetoed));
    }

    function test_FrozenPrimary_Emergency_ConfigUnaffected() public {
        vm.prank(backup);
        wallet.setFrozenPrimary(true);

        vm.prank(emergency);
        wallet.setGlobalTimelock(3 days);
        assertEq(wallet.globalTimelock(), 3 days);
    }

    function test_FrozenPrimary_BackupExecutePending_AfterPrimaryProposed() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 99));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
        wallet.setFrozenPrimary(true);

        (,,, uint64 executeAfter,,,,,,) = wallet.operations(operationId);
        vm.warp(executeAfter);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Primary));
        wallet.executePending(calls, 1);

        vm.prank(backup);
        wallet.executePending(calls, 1);
        assertEq(receiver.value(), 99);
    }

    function test_FrozenBackup_PrimaryCannotSetBackup_EmergencyCan() public {
        vm.prank(emergency);
        wallet.setFrozenBackup(true);

        address newBackup = address(0x8002);

        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.NotAllowedRoleChange.selector);
        wallet.setBackup(newBackup);

        vm.prank(backup);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Backup));
        wallet.setBackup(newBackup);

        vm.prank(emergency);
        wallet.setBackup(newBackup);
        assertEq(wallet.backup(), newBackup);
    }

    function test_ProposeWithRelay_Anyone_ExternalExecutorGetsReward() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 717));
        MERAWalletTypes.RelayProposeConfig memory relayConfig =
            _relayConfig(MERAWalletTypes.RelayExecutorPolicy.Anyone, address(0), bytes32(0));

        vm.deal(primary, 1 ether);
        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransactionWithRelay{value: 1 ether}(calls, 1, relayConfig);
        (,,, uint64 executeAfter,,,,,,) = wallet.operations(operationId);
        vm.warp(executeAfter);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CoreExecutorNotAllowed.selector, primary));
        wallet.executePending(calls, 1);

        uint256 outsiderBalanceBefore = outsider.balance;
        vm.prank(outsider);
        wallet.executePending(calls, 1);

        assertEq(receiver.value(), 717);
        assertEq(outsider.balance, outsiderBalanceBefore + 1 ether);
        (,,,,,,, uint256 relayReward,,) = wallet.operations(operationId);
        assertEq(relayReward, 0);
    }

    function test_ProposeWithRelay_Designated_OnlyDesignatedCanExecute() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        address designated = address(0xD3516);
        address randomRelayer = address(0xCA11);
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 808));
        MERAWalletTypes.RelayProposeConfig memory relayConfig =
            _relayConfig(MERAWalletTypes.RelayExecutorPolicy.Designated, designated, bytes32(0));

        vm.deal(primary, 0.25 ether);
        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransactionWithRelay{value: 0.25 ether}(calls, 1, relayConfig);
        (,,, uint64 executeAfter,,,,,,) = wallet.operations(operationId);
        vm.warp(executeAfter);

        vm.prank(randomRelayer);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RelayExecutorNotAllowed.selector, randomRelayer));
        wallet.executePending(calls, 1);

        vm.prank(backup);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CoreExecutorNotAllowed.selector, backup));
        wallet.executePending(calls, 1);

        uint256 designatedBalanceBefore = designated.balance;
        vm.prank(designated);
        wallet.executePending(calls, 1);

        assertEq(receiver.value(), 808);
        assertEq(designated.balance, designatedBalanceBefore + 0.25 ether);
    }

    function test_ProposeWithRelay_Whitelist_ValidatesHashAndExecutor() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        address whitelistRelayerA = outsider;
        address whitelistRelayerB = address(0xBEEF);
        address[] memory whitelist = new address[](2);
        whitelist[0] = whitelistRelayerA;
        whitelist[1] = whitelistRelayerB;

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 909));
        MERAWalletTypes.RelayProposeConfig memory relayConfig =
            _relayConfig(MERAWalletTypes.RelayExecutorPolicy.Whitelist, address(0), keccak256(abi.encode(whitelist)));

        vm.deal(primary, 0.4 ether);
        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransactionWithRelay{value: 0.4 ether}(calls, 1, relayConfig);
        (,,, uint64 executeAfter,,,,,,) = wallet.operations(operationId);
        vm.warp(executeAfter);

        address[] memory wrongWhitelist = new address[](2);
        wrongWhitelist[0] = whitelistRelayerB;
        wrongWhitelist[1] = whitelistRelayerA;
        vm.prank(whitelistRelayerA);
        vm.expectRevert(IBaseMERAWalletErrors.InvalidExecutorWhitelist.selector);
        wallet.executePending(calls, 1, wrongWhitelist);

        vm.prank(address(0xFA11));
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RelayExecutorNotAllowed.selector, address(0xFA11)));
        wallet.executePending(calls, 1, whitelist);

        uint256 relayerBalanceBefore = whitelistRelayerA.balance;
        vm.prank(whitelistRelayerA);
        wallet.executePending(calls, 1, whitelist);

        assertEq(receiver.value(), 909);
        assertEq(whitelistRelayerA.balance, relayerBalanceBefore + 0.4 ether);
    }

    function test_CancelPending_RefundsRelayRewardToCreator() public {
        vm.prank(emergency);
        wallet.setGlobalTimelock(1 days);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 123));
        MERAWalletTypes.RelayProposeConfig memory relayConfig =
            _relayConfig(MERAWalletTypes.RelayExecutorPolicy.Anyone, address(0), bytes32(0));

        vm.deal(primary, 2 ether);
        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransactionWithRelay{value: 0.6 ether}(calls, 1, relayConfig);
        assertEq(address(wallet).balance, 0.6 ether);

        vm.prank(primary);
        wallet.cancelPending(operationId);

        assertEq(address(wallet).balance, 0);
        assertEq(primary.balance, 2 ether);
        (,,,,,,, uint256 relayReward,,) = wallet.operations(operationId);
        assertEq(relayReward, 0);
    }

    function _callPathPolicy(uint56 primaryDelay, bool primaryForbidden, uint56 backupDelay, bool backupForbidden)
        internal
        pure
        returns (MERAWalletTypes.CallPathPolicy memory p)
    {
        p.primary = MERAWalletTypes.RoleCallPolicy({delay: primaryDelay, forbidden: primaryForbidden});
        p.backup = MERAWalletTypes.RoleCallPolicy({delay: backupDelay, forbidden: backupForbidden});
        p.exists = true;
    }

    /// @dev Policies with `exists == false` so merge path uses `globalTimelock` when both dimensions use this helper.
    function _inactiveCallPathPolicy(
        uint56 primaryDelay,
        bool primaryForbidden,
        uint56 backupDelay,
        bool backupForbidden
    ) internal pure returns (MERAWalletTypes.CallPathPolicy memory p) {
        p.primary = MERAWalletTypes.RoleCallPolicy({delay: primaryDelay, forbidden: primaryForbidden});
        p.backup = MERAWalletTypes.RoleCallPolicy({delay: backupDelay, forbidden: backupForbidden});
    }

    /// @dev Alias for `_callPathPolicy`; pair override requires `exists == true`.
    function _pairCallPathPolicy(uint56 primaryDelay, bool primaryForbidden, uint56 backupDelay, bool backupForbidden)
        internal
        pure
        returns (MERAWalletTypes.CallPathPolicy memory)
    {
        return _callPathPolicy(primaryDelay, primaryForbidden, backupDelay, backupForbidden);
    }

    /// @dev Builds `n` identical calls to `target` with `ReceiverMock.setValue(0)` calldata (for batch limit tests).
    function _repeatedCalls(address target, uint256 n) internal pure returns (MERAWalletTypes.Call[] memory calls) {
        bytes memory data = abi.encodeWithSelector(ReceiverMock.setValue.selector, uint256(0));
        calls = new MERAWalletTypes.Call[](n);
        for (uint256 i = 0; i < n; i++) {
            calls[i] =
                MERAWalletTypes.Call({target: target, value: 0, data: data, checker: address(0), checkerData: ""});
        }
    }

    function _mkReq(address c, bool e) internal pure returns (address[] memory cc, bool[] memory ee) {
        cc = new address[](1);
        ee = new bool[](1);
        cc[0] = c;
        ee[0] = e;
    }

    function _mkAgents(address a, bool e) internal pure returns (address[] memory aa, bool[] memory bb) {
        aa = new address[](1);
        bb = new bool[](1);
        aa[0] = a;
        bb[0] = e;
    }

    function _agentsCall(BaseMERAWallet w, address agent, bool enabled) internal {
        (address[] memory aa, bool[] memory bb) = _mkAgents(agent, enabled);
        w.setControllerAgents(aa, bb);
    }

    /// @dev Applies one target policy via `setTargetCallPolicies` (singleton batch).
    function _policyTarget(address target, MERAWalletTypes.CallPathPolicy memory pol) internal {
        address[] memory ts = new address[](1);
        MERAWalletTypes.CallPathPolicy[] memory ps = new MERAWalletTypes.CallPathPolicy[](1);
        ts[0] = target;
        ps[0] = pol;
        wallet.setTargetCallPolicies(ts, ps);
    }

    /// @dev Applies one selector policy via `setSelectorCallPolicies`.
    function _policySelector(bytes4 sel, MERAWalletTypes.CallPathPolicy memory pol) internal {
        bytes4[] memory ss = new bytes4[](1);
        MERAWalletTypes.CallPathPolicy[] memory ps = new MERAWalletTypes.CallPathPolicy[](1);
        ss[0] = sel;
        ps[0] = pol;
        wallet.setSelectorCallPolicies(ss, ps);
    }

    /// @dev Applies one (target, selector) pair policy via `setTargetSelectorCallPolicies`.
    function _policyPair(address target, bytes4 sel, MERAWalletTypes.CallPathPolicy memory pol) internal {
        address[] memory ts = new address[](1);
        bytes4[] memory ss = new bytes4[](1);
        MERAWalletTypes.CallPathPolicy[] memory ps = new MERAWalletTypes.CallPathPolicy[](1);
        ts[0] = target;
        ss[0] = sel;
        ps[0] = pol;
        wallet.setTargetSelectorCallPolicies(ts, ss, ps);
    }

    function _mkWl(address checker, bool allowed, bytes memory config)
        internal
        pure
        returns (MERAWalletTypes.WhitelistCheckerUpdate[] memory u)
    {
        u = new MERAWalletTypes.WhitelistCheckerUpdate[](1);
        u[0] = MERAWalletTypes.WhitelistCheckerUpdate({checker: checker, allowed: allowed, config: config});
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

    function _relayConfig(
        MERAWalletTypes.RelayExecutorPolicy relayPolicy,
        address designatedExecutor,
        bytes32 executorSetHash
    ) internal pure returns (MERAWalletTypes.RelayProposeConfig memory relayConfig) {
        relayConfig = MERAWalletTypes.RelayProposeConfig({
                relayPolicy: relayPolicy, designatedExecutor: designatedExecutor, executorSetHash: executorSetHash
            });
    }

    function _signDigest(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
