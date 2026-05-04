// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {IBaseMERAWalletErrors} from "../src/interfaces/IBaseMERAWalletErrors.sol";
import {MERAWalletConstants} from "../src/constants/MERAWalletConstants.sol";
import {MERAWalletLoginRegistry} from "../src/MERAWalletLoginRegistry.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletUniswapV2OracleSlippageChecker} from "../src/checkers/MERAWalletUniswapV2OracleSlippageChecker.sol";
import {MERAWalletUniswapV2AssetWhitelist} from "../src/checkers/whitelists/MERAWalletUniswapV2AssetWhitelist.sol";
import {MERAWalletUniswapV2SlippageTypes} from "../src/checkers/types/MERAWalletUniswapV2SlippageTypes.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ConfigurableTransactionChecker} from "./mocks/ConfigurableTransactionChecker.sol";
import {ReceiverMock} from "./mocks/ReceiverMock.sol";
import {IBaseMERAWalletEvents} from "../src/interfaces/IBaseMERAWalletEvents.sol";

contract BaseMERAWalletHarness is BaseMERAWallet {
    constructor(
        address initialPrimary,
        address initialBackup,
        address initialEmergency,
        address initialSigner,
        address initialGuardian
    ) BaseMERAWallet(initialPrimary, initialBackup, initialEmergency, initialSigner, initialGuardian) {}

    function exposedCallWithExecutionContext(
        MERAWalletTypes.Call calldata callData,
        address contextCaller,
        MERAWalletTypes.Role contextRole
    ) external returns (bool success, bytes memory result) {
        return _callWithExecutionContext(callData, contextCaller, contextRole);
    }
}

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
    ReceiverMock internal receiver;
    ERC20Mock internal token;
    ConfigurableTransactionChecker internal checkerBothHooks;
    ConfigurableTransactionChecker internal checkerAfterOnly;
    ConfigurableTransactionChecker internal checkerBeforeOnly;
    ConfigurableTransactionChecker internal checkerNoHooks;

    function setUp() public {
        wallet = new BaseMERAWallet(primary, backup, emergency, address(0), address(0));
        receiver = new ReceiverMock();
        token = new ERC20Mock();
        checkerBothHooks = new ConfigurableTransactionChecker(true, true, address(wallet));
        checkerAfterOnly = new ConfigurableTransactionChecker(false, true, address(wallet));
        checkerBeforeOnly = new ConfigurableTransactionChecker(true, false, address(wallet));
        checkerNoHooks = new ConfigurableTransactionChecker(false, false, address(wallet));

        vm.startPrank(emergency);
        _setAllRoleTimelocks(0);
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setOptionalCheckers.selector, _mkWl(address(0), true, "")), 7001
        );
        vm.stopPrank();
    }

    function test_SetPrimary_DirectPrimaryReverts() public {
        address newPrimary = address(0x9999);
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setPrimary(newPrimary);
    }

    function test_SetPrimary_SelfCallUsesEffectivePrimaryCaller() public {
        address newPrimary = address(0x9999);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit IBaseMERAWalletEvents.PrimaryUpdated(primary, newPrimary, primary);
        vm.prank(primary);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setPrimary.selector, newPrimary), 910);
        assertEq(wallet.primary(), newPrimary);
    }

    function test_SetPrimary_SelfCallRevertsDuringSafeMode() public {
        BaseMERAWalletHarness h = new BaseMERAWalletHarness(primary, backup, emergency, address(0), address(0));
        vm.prank(emergency);
        h.enterSafeMode(30 days);

        MERAWalletTypes.Call memory callData = MERAWalletTypes.Call({
            target: address(h),
            value: 0,
            data: abi.encodeWithSelector(h.setPrimary.selector, address(0x9999)),
            checker: address(0),
            checkerData: ""
        });

        (bool success, bytes memory result) =
            h.exposedCallWithExecutionContext(callData, primary, MERAWalletTypes.Role.Primary);

        assertFalse(success);
        assertEq(result, abi.encodeWithSelector(IBaseMERAWalletErrors.SafeModeActive.selector, h.safeModeBefore()));
    }

    function test_SetBackup_Matrix() public {
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setBackup(primary);

        address newBackup = address(0xBEEF);
        vm.prank(backup);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setBackup.selector, newBackup), 911);
        assertEq(wallet.backup(), newBackup);
    }

    function test_SetBackup_PrimarySelfCallStillNotAllowed() public {
        address newBackup = address(0xBEEF);
        vm.prank(primary);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.NotAllowedRoleChange.selector),
            abi.encodeWithSelector(wallet.setBackup.selector, newBackup),
            912
        );
    }

    function test_SetBackup_SelfCallRevertsDuringSafeMode() public {
        BaseMERAWalletHarness h = new BaseMERAWalletHarness(primary, backup, emergency, address(0), address(0));
        vm.prank(emergency);
        h.enterSafeMode(30 days);

        MERAWalletTypes.Call memory callData = MERAWalletTypes.Call({
            target: address(h),
            value: 0,
            data: abi.encodeWithSelector(h.setBackup.selector, address(0xBEEF)),
            checker: address(0),
            checkerData: ""
        });

        (bool success, bytes memory result) =
            h.exposedCallWithExecutionContext(callData, backup, MERAWalletTypes.Role.Backup);

        assertFalse(success);
        assertEq(result, abi.encodeWithSelector(IBaseMERAWalletErrors.SafeModeActive.selector, h.safeModeBefore()));
    }

    function test_EmergencyCanReconfigureAllRoles() public {
        address newPrimary = address(0xAAA1);
        address newBackup = address(0xAAA2);
        address newEmergency = address(0xAAA3);

        vm.startPrank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setPrimary.selector, newPrimary), 913);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setBackup.selector, newBackup), 914);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setEmergency.selector, newEmergency), 924);
        vm.stopPrank();

        assertEq(wallet.primary(), newPrimary);
        assertEq(wallet.backup(), newBackup);
        assertEq(wallet.emergency(), newEmergency);
    }

    function test_SetEmergency_DirectEmergencyReverts() public {
        address newEmergency = address(0xE2E2);

        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setEmergency(newEmergency);
    }

    function test_SetEmergency_SelfCallUsesEffectiveEmergencyCaller() public {
        address newEmergency = address(0xE2E2);

        vm.expectEmit(true, true, true, true, address(wallet));
        emit IBaseMERAWalletEvents.EmergencyUpdated(emergency, newEmergency, emergency);
        vm.prank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setEmergency.selector, newEmergency), 925);

        assertEq(wallet.emergency(), newEmergency);
    }

    function test_SetEmergency_TimelockedSelfCallLifecycle() public {
        vm.startPrank(emergency);
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Emergency, uint256(1 days)),
            926
        );
        vm.stopPrank();

        address newEmergency = address(0xE2E2);
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(wallet), 0, abi.encodeWithSelector(wallet.setEmergency.selector, newEmergency));

        vm.prank(emergency);
        bytes32 operationId = wallet.proposeTransaction(calls, 927);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(operationId);

        vm.prank(emergency);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.TimelockNotExpired.selector, uint256(executeAfter), block.timestamp
            )
        );
        wallet.executePending(calls, 927);

        vm.warp(executeAfter);
        vm.prank(emergency);
        wallet.executePending(calls, 927);

        assertEq(wallet.emergency(), newEmergency);
    }

    function test_SetPrimary_TimelockedSelfCallLifecycle() public {
        vm.startPrank(emergency);
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Primary, uint256(1 days)), 915
        );
        vm.stopPrank();

        address newPrimary = address(0x9999);
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(wallet), 0, abi.encodeWithSelector(wallet.setPrimary.selector, newPrimary));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 916);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(operationId);

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.TimelockNotExpired.selector, uint256(executeAfter), block.timestamp
            )
        );
        wallet.executePending(calls, 916);

        vm.warp(executeAfter);
        vm.prank(primary);
        wallet.executePending(calls, 916);

        assertEq(wallet.primary(), newPrimary);
    }

    function test_SetEmergency_GuardianCanRotate() public {
        address guardianAddr = vm.addr(0xCAFE);
        BaseMERAWallet w = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddr);

        address newEmergency = address(0xE2E2);
        vm.prank(guardianAddr);
        w.setEmergency(newEmergency);
        assertEq(w.emergency(), newEmergency);
    }

    function test_DefaultRoleTimelocksAndEmergencyAgentLifetime() public {
        BaseMERAWallet w = new BaseMERAWallet(primary, backup, emergency, address(0), address(0));

        assertEq(w.roleTimelock(MERAWalletTypes.Role.Primary), 24 hours);
        assertEq(w.roleTimelock(MERAWalletTypes.Role.Backup), 12 hours);
        assertEq(w.roleTimelock(MERAWalletTypes.Role.Emergency), 0);
        assertEq(w.emergencyAgentLifetime(), 30 days);
    }

    function test_GuardianCanEnterSafeModeAndRotationClearsIt() public {
        address guardianAddr = vm.addr(0xCAFE);
        BaseMERAWallet w = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddr);

        // safeModeBefore is the timestamp when restrictions lift (entered + duration).
        uint256 expectedExpiry = block.timestamp + 30 days;
        vm.prank(guardianAddr);
        w.enterSafeMode(30 days);
        assertTrue(w.safeModeUsed());
        assertEq(w.safeModeBefore(), expectedExpiry);

        address newEmergency = address(0xE2E2);
        vm.prank(guardianAddr);
        w.setEmergency(newEmergency);

        assertEq(w.emergency(), newEmergency);
        // Guardian rotation zeroes the deadline; the one-shot flag clears only via resetSafeMode.
        assertTrue(w.safeModeUsed());
        assertEq(w.safeModeBefore(), 0);
        vm.prank(newEmergency);
        w.resetSafeMode();
        assertFalse(w.safeModeUsed());
        assertEq(w.safeModeBefore(), 0);
    }

    function test_GuardianCanFreezePrimaryAndBackup() public {
        address guardianAddr = vm.addr(0xCAFE);
        BaseMERAWallet w = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddr);

        vm.prank(guardianAddr);
        w.setFrozenPrimary(true);
        assertTrue(w.frozenPrimary());

        vm.prank(guardianAddr);
        w.setFrozenBackup(true);
        assertTrue(w.frozenBackup());
    }

    function test_NoGuardianAddressCannotUseGuardianFreezePath() public {
        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.FreezeActionNotAuthorized.selector);
        wallet.setFrozenPrimary(true);
    }

    function test_SetEmergency_OutsiderRevertsWithoutGuardian() public {
        address newEmergency = address(0xE4E4);
        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setEmergency(newEmergency);
    }

    function test_SetGuardian_EmergencyRevertsWhenNoGuardian() public {
        address newGuardian = address(0xC001);
        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setGuardian(newGuardian);
    }

    function test_SetGuardian_EmergencyRevertsWhenGuardianSet() public {
        address guardianAddr = vm.addr(0xCAFE);
        BaseMERAWallet w = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddr);

        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        w.setGuardian(address(0xD00D));
    }

    function test_SetGuardian_BatchedSelfCallUsesEffectiveEmergencyWhenGuardianSet() public {
        address guardianAddr = vm.addr(0xCAFE);
        address newGuardian = address(0xD00D);
        BaseMERAWallet w = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddr);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(w), 0, abi.encodeWithSelector(BaseMERAWallet.setGuardian.selector, newGuardian));
        vm.prank(emergency);
        w.executeTransaction(calls, 42);
        assertEq(w.guardian(), newGuardian);
    }

    function test_SetGuardian_BatchedSelfCallToZeroUsesEffectiveEmergencyWhenGuardianSet() public {
        address guardianAddr = vm.addr(0xCAFE);
        BaseMERAWallet w = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddr);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(w), 0, abi.encodeWithSelector(BaseMERAWallet.setGuardian.selector, address(0)));
        vm.prank(emergency);
        w.executeTransaction(calls, 777);
        assertEq(w.guardian(), address(0));
    }

    function test_SetGuardian_OutsiderReverts() public {
        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setGuardian(address(0xABCD));
    }

    function test_SetGuardian_PrimaryBackupSelfCallRevertsNotEmergency() public {
        address guardianAddr = vm.addr(0xCAFE);
        address newGuardian = address(0xD00D);
        BaseMERAWallet w = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddr);

        vm.startPrank(emergency);
        _setAllRoleTimelocksOn(w, 0);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(w), 0, abi.encodeWithSelector(BaseMERAWallet.setGuardian.selector, newGuardian));

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallExecutionFailed.selector,
                uint256(0),
                abi.encodeWithSelector(IBaseMERAWalletErrors.NotEmergency.selector)
            )
        );
        w.executeTransaction(calls, 1001);

        vm.prank(backup);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallExecutionFailed.selector,
                uint256(0),
                abi.encodeWithSelector(IBaseMERAWalletErrors.NotEmergency.selector)
            )
        );
        w.executeTransaction(calls, 1002);
    }

    function test_OnlyEmergencyOrSelf_DirectEmergencySetRoleTimelockRevertsWithoutGuardian() public {
        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setRoleTimelock(MERAWalletTypes.Role.Primary, 2 hours);
    }

    function test_OnlyEmergencyOrSelf_SelfCallSetRoleTimelockSucceeds() public {
        vm.prank(emergency);
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Primary, uint256(2 hours)), 901
        );

        assertEq(wallet.roleTimelock(MERAWalletTypes.Role.Primary), 2 hours);
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
        vm.startPrank(emergency);
        _setAllRoleTimelocks(MERAWalletConstants.MAX_TIMELOCK_DELAY);
        vm.stopPrank();
        assertEq(wallet.roleTimelock(MERAWalletTypes.Role.Primary), MERAWalletConstants.MAX_TIMELOCK_DELAY);
    }

    function test_SetGlobalTimelock_DelayAboveMaxReverts() public {
        vm.prank(emergency);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.TimelockDelayTooLarge.selector,
                MERAWalletConstants.MAX_TIMELOCK_DELAY + 1,
                MERAWalletConstants.MAX_TIMELOCK_DELAY
            ),
            abi.encodeWithSelector(
                wallet.setRoleTimelock.selector,
                MERAWalletTypes.Role.Primary,
                MERAWalletConstants.MAX_TIMELOCK_DELAY + 1
            ),
            902
        );
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
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Primary, uint256(1 days)), 903
        );

        vm.prank(emergency);
        wallet.confirmAlive();

        vm.startPrank(emergency);
        _setAllRoleTimelocks(2 days);
        vm.stopPrank();
        assertEq(wallet.roleTimelock(MERAWalletTypes.Role.Primary), 2 days);
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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setEmergency.selector, newEmergency), 928);

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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setEmergency.selector, newEmergency), 929);

        assertFalse(wallet.isLifeController(emergency));
        assertTrue(wallet.isLifeController(newEmergency));
    }

    function test_ExecuteTransaction_ImmediateWhenNoTimelockConfigured() public {
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 77));

        vm.prank(primary);
        wallet.executeTransaction(calls, 1);

        assertEq(receiver.value(), 77);
    }

    function test_ExecuteTransaction_RevertsWhenTimelockRequired() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 11));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.TimelockRequired.selector, 1 days));
        wallet.executeTransaction(calls, 1);
    }

    function test_GetRequiredDelay_UsesGlobalWhenPerRoleDelaysAreZero() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _inactiveCallPathPolicy(0, false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _inactiveCallPathPolicy(0, false, 0, false));
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 42));

        vm.prank(primary);
        uint256 delay = wallet.getRequiredDelay(calls);
        assertEq(delay, 1 days);
    }

    function test_GetRequiredDelay_TargetPrimaryDelayApplies() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(uint56(2 days), false, 0, false));
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 101));

        vm.prank(primary);
        uint256 delay = wallet.getRequiredDelay(calls);
        assertEq(delay, 2 days);
    }

    function test_GetRequiredDelay_EmergencyPolicySliceApplies() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(uint56(0), false, 0, false, uint56(5 hours)));
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Emergency, uint256(2 hours)),
            904
        );
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 101));

        vm.prank(emergency);
        uint256 delay = wallet.getRequiredDelay(calls);
        assertEq(delay, 5 hours);
    }

    function test_GetRequiredDelay_TargetPolicyOverridesRoleTimelock() public {
        vm.startPrank(emergency);
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Primary, uint256(1 days)), 905
        );
        _policyTarget(address(receiver), _callPathPolicy(0, false, 0, false));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 101));

        vm.prank(primary);
        uint256 delay = wallet.getRequiredDelay(calls);
        assertEq(delay, 0);
    }

    function test_GetRequiredDelay_UsesMaxOfTargetAndSelectorPrimaryDelays() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(uint56(5 days), false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(2 days), false, 0, false));
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 303));

        vm.prank(primary);
        uint256 delay = wallet.getRequiredDelay(calls);
        assertEq(delay, 5 days);
    }

    function test_GetRequiredDelay_UsesMaxWhenSelectorPrimaryDelayIsHigher() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(uint56(2 days), false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(5 days), false, 0, false));
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 404));

        vm.prank(primary);
        uint256 delay = wallet.getRequiredDelay(calls);
        assertEq(delay, 5 days);
    }

    function test_GetRequiredDelay_UsesMaxDelayWhenBothDimensionsSet() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(uint56(2 days), false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(3 days), false, 0, false));
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 505));

        vm.prank(primary);
        uint256 delay = wallet.getRequiredDelay(calls);
        assertEq(delay, 3 days);
    }

    function test_GetRequiredDelay_PairPolicyOverridesSeparateTargetAndSelector() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(uint56(5 days), false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(2 days), false, 0, false));
        _policyPair(
            address(receiver), ReceiverMock.setValue.selector, _pairCallPathPolicy(uint56(1 days), false, 0, false)
        );
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 606));

        vm.prank(primary);
        assertEq(wallet.getRequiredDelay(calls), 1 days);
    }

    function test_GetRequiredDelay_AfterClearPairPolicy_UsesMaxOfTargetAndSelector() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(uint56(5 days), false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(2 days), false, 0, false));
        _policyPair(
            address(receiver), ReceiverMock.setValue.selector, _pairCallPathPolicy(uint56(1 days), false, 0, false)
        );
        _policyPair(address(receiver), ReceiverMock.setValue.selector, _inactiveCallPathPolicy(0, false, 0, false));
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 707));

        vm.prank(primary);
        assertEq(wallet.getRequiredDelay(calls), 5 days);
    }

    function test_GetRequiredDelay_PairPolicyZeroPrimaryDelayReturnsZero() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(uint56(5 days), false, 0, false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(2 days), false, 0, false));
        _policyPair(address(receiver), ReceiverMock.setValue.selector, _pairCallPathPolicy(0, false, 0, false));
        _setAllRoleTimelocks(1 days);
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
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallExecutionFailed.selector,
                uint256(0),
                abi.encodeWithSelector(IBaseMERAWalletErrors.NoopTargetSelectorCallPolicy.selector)
            )
        );
        _policyPair(address(receiver), ReceiverMock.setValue.selector, _inactiveCallPathPolicy(0, false, 0, false));
    }

    function test_CallPolicyByTargetSelector_PublicGetter_ReturnsStored() public {
        MERAWalletTypes.CallPathPolicy memory stored = _pairCallPathPolicy(uint56(9 days), false, uint56(1 days), true);
        vm.prank(emergency);
        _policyPair(address(receiver), ReceiverMock.setValue.selector, stored);

        (
            MERAWalletTypes.RoleCallPolicy memory readPrimary,
            MERAWalletTypes.RoleCallPolicy memory readBackup,
            uint256 readEmergencyDelay,
            bool readExists
        ) = wallet.callPolicyByTargetSelector(address(receiver), ReceiverMock.setValue.selector);
        assertTrue(readExists);
        assertEq(uint256(readPrimary.delay), 9 days);
        assertFalse(readPrimary.forbidden);
        assertEq(uint256(readBackup.delay), 1 days);
        assertTrue(readBackup.forbidden);
        assertEq(readEmergencyDelay, 0);
    }

    function test_CallPolicyGetters_ReturnStoredPolicy() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(uint56(123), true, uint56(7), false));
        _policySelector(ReceiverMock.setValue.selector, _callPathPolicy(uint56(456), false, uint56(8), true));
        vm.stopPrank();

        (
            MERAWalletTypes.RoleCallPolicy memory tPrimary,
            MERAWalletTypes.RoleCallPolicy memory tBackup,
            uint256 tEmergencyDelay,
            bool tExists
        ) = wallet.callPolicyByTarget(address(receiver));
        assertTrue(tExists);
        assertEq(uint256(tPrimary.delay), 123);
        assertTrue(tPrimary.forbidden);
        assertEq(uint256(tBackup.delay), 7);
        assertFalse(tBackup.forbidden);
        assertEq(tEmergencyDelay, 0);

        (
            MERAWalletTypes.RoleCallPolicy memory sPrimary,
            MERAWalletTypes.RoleCallPolicy memory sBackup,
            uint256 sEmergencyDelay,
            bool sExists
        ) = wallet.callPolicyBySelector(ReceiverMock.setValue.selector);
        assertTrue(sExists);
        assertEq(uint256(sPrimary.delay), 456);
        assertFalse(sPrimary.forbidden);
        assertEq(uint256(sBackup.delay), 8);
        assertTrue(sBackup.forbidden);
        assertEq(sEmergencyDelay, 0);
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
        vm.startPrank(emergency);
        _setAllRoleTimelocks(2 hours);
        vm.stopPrank();

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
            bytes32 executorSetHash,
            uint64 relayExecuteBefore
        ) = wallet.operations(operationId);
        assertEq(creator, primary);
        assertEq(operationSalt, 1);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Pending));
        assertEq(uint256(relayPolicy), uint256(MERAWalletTypes.RelayExecutorPolicy.CoreExecute));
        assertEq(relayReward, 0);
        assertEq(designatedExecutor, address(0));
        assertEq(executorSetHash, bytes32(0));
        assertEq(relayExecuteBefore, uint64(0));
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
        (,,,,, MERAWalletTypes.OperationStatus finalStatus,,,,,) = wallet.operations(operationId);
        assertEq(uint256(finalStatus), uint256(MERAWalletTypes.OperationStatus.Executed));
    }

    function test_GetOperationId_DiffersBySalt() public view {
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 501));

        bytes32 operationIdA = wallet.getOperationId(calls, 10);
        bytes32 operationIdB = wallet.getOperationId(calls, 11);

        assertTrue(operationIdA != operationIdB);
    }

    function test_CancelPending_BackupCannotCancelPrimaryOperation() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 9));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CannotCancelOperation.selector, operationId));
        wallet.cancelPending(operationId);

        vm.prank(primary);
        wallet.cancelPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Cancelled));
    }

    function test_CancelPending_BackupMayCancelOwnOperation() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 42));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
        wallet.cancelPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Cancelled));
    }

    function test_CancelPending_DemotionBlocksCancelPrimaryOp() public {
        vm.startPrank(emergency);
        _policyTarget(address(receiver), _callPathPolicy(uint56(1 days), false, 0, false));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 88));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setPrimary.selector, backup), 917);
        vm.prank(backup);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setBackup.selector, primary), 918);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CannotCancelOperation.selector, operationId));
        wallet.cancelPending(operationId);
    }

    function test_ProposeTransaction_RevertsWhenOperationIdWasCancelledBefore() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

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
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

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

    function test_CancelPending_PrimaryMayCancelBackupOperation() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 55));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(primary);
        wallet.cancelPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Cancelled));
    }

    function test_CancelPending_BackupMayCancelEmergencyOperation() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 56));

        vm.prank(emergency);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
        wallet.cancelPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Cancelled));
    }

    function test_CancelPending_EmergencyCannotCancelBackupOperation() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 57));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(emergency);
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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.set1271Signer.selector, backup), 906);

        assertEq(uint256(uint32(wallet.isValidSignature(digest, backupSignature))), uint256(uint32(0x1626ba7e)));
        assertEq(uint256(uint32(wallet.isValidSignature(digest, primarySignature))), uint256(uint32(0xffffffff)));
    }

    function test_SetRequiredChecker_OnlyEmergencyAndSupportsBothMode() public {
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(checkerBothHooks), true);
            wallet.setRequiredCheckers(__rqA, __rqB);
        }

        vm.prank(emergency);
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(checkerBothHooks), true);
            _setRequiredCheckers(__rqA, __rqB);
        }

        (address[] memory beforeList, address[] memory afterList) = wallet.getRequiredCheckers();
        assertEq(beforeList.length, 1);
        assertEq(afterList.length, 1);
        assertEq(beforeList[0], address(checkerBothHooks));
        assertEq(afterList[0], address(checkerBothHooks));
    }

    function test_AfterChecker_RevertsAndRollsBackExecution() public {
        vm.prank(emergency);
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(checkerAfterOnly), true);
            _setRequiredCheckers(__rqA, __rqB);
        }

        checkerAfterOnly.configure(false, true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 909));

        vm.prank(primary);
        vm.expectRevert(ConfigurableTransactionChecker.AfterCheckFailed.selector);
        wallet.executeTransaction(calls, 1);

        assertEq(receiver.value(), 0);
    }

    function test_CheckersSkippedForSelfCalls() public {
        vm.startPrank(emergency);
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(checkerBeforeOnly), true);
            _setRequiredCheckers(__rqA, __rqB);
        }
        checkerBeforeOnly.configure(true, false);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls = _singleCallWithChecker(
            address(wallet),
            0,
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Primary, uint256(3 hours)),
            address(checkerBeforeOnly),
            ""
        );

        vm.prank(emergency);
        wallet.executeTransaction(calls, 1);

        assertEq(wallet.roleTimelock(MERAWalletTypes.Role.Primary), 3 hours);
    }

    function test_Agent_CannotExecute_IsVetoOnly() public {
        vm.prank(primary);
        _agentsCall(wallet, agentAddr, true);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 33));

        vm.prank(agentAddr);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        wallet.executeTransaction(calls, 1);
    }

    function test_Agent_BackupCanAssignVetoAgent() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);
        (MERAWalletTypes.Role role,) = wallet.agents(agentAddr);
        assertEq(uint256(role), uint256(MERAWalletTypes.Role.Primary));
    }

    function test_Agent_DirectSetAgentsReverts() public {
        (address[] memory aa, MERAWalletTypes.Role[] memory rr) = _mkAgents(agentAddr, MERAWalletTypes.Role.Primary);

        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setAgents(aa, rr);
    }

    function test_Agent_OutsiderCannotSetOrRemove() public {
        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(primary);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        _agentsCall(wallet, agentAddr, false);
    }

    function test_Agent_AgentCannotAssignAnotherAgent() public {
        address secondAgent = address(0xA62);

        vm.prank(primary);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(agentAddr);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        _agentsCall(wallet, secondAgent, true);
    }

    function test_Agent_SelfCallEmitsEffectiveCaller() public {
        vm.expectEmit(true, true, true, true, address(wallet));
        emit IBaseMERAWalletEvents.AgentUpdated(agentAddr, MERAWalletTypes.Role.Primary, 0, primary);

        vm.prank(primary);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Primary);
    }

    function test_Agent_PrimaryScoped_RemovedByPrimaryOrHigher() public {
        vm.prank(primary);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        _agentsCall(wallet, agentAddr, false);

        vm.prank(primary);
        _agentsCall(wallet, agentAddr, false);
        (MERAWalletTypes.Role roleAfterPrimary,) = wallet.agents(agentAddr);
        assertEq(uint256(roleAfterPrimary), uint256(MERAWalletTypes.Role.None));

        vm.prank(primary);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(backup);
        _agentsCall(wallet, agentAddr, false);
        (MERAWalletTypes.Role roleAfterBackup,) = wallet.agents(agentAddr);
        assertEq(uint256(roleAfterBackup), uint256(MERAWalletTypes.Role.None));
    }

    function test_Agent_EmergencyScoped_OnlyEmergencyRemoves() public {
        vm.prank(emergency);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Emergency);

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallExecutionFailed.selector,
                uint256(0),
                abi.encodeWithSelector(IBaseMERAWalletErrors.AgentRemovalNotAuthorized.selector)
            )
        );
        _agentsCall(wallet, agentAddr, false);

        vm.prank(backup);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallExecutionFailed.selector,
                uint256(0),
                abi.encodeWithSelector(IBaseMERAWalletErrors.AgentRemovalNotAuthorized.selector)
            )
        );
        _agentsCall(wallet, agentAddr, false);

        vm.prank(emergency);
        _agentsCall(wallet, agentAddr, false);
        (MERAWalletTypes.Role role,) = wallet.agents(agentAddr);
        assertEq(uint256(role), uint256(MERAWalletTypes.Role.None));
    }

    function test_Agent_BackupAssigned_OnlyBackupOrHigherRemoves() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Backup);

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallExecutionFailed.selector,
                uint256(0),
                abi.encodeWithSelector(IBaseMERAWalletErrors.AgentRemovalNotAuthorized.selector)
            )
        );
        _agentsCall(wallet, agentAddr, false);

        vm.prank(backup);
        _agentsCall(wallet, agentAddr, false);
        (MERAWalletTypes.Role role,) = wallet.agents(agentAddr);
        assertEq(uint256(role), uint256(MERAWalletTypes.Role.None));
    }

    function test_Agent_VetoAgent_VetoClearExecute_Lifecycle() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Backup);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 9));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Vetoed));

        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(operationId);
        vm.warp(executeAfter);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.OperationNotPending.selector, operationId));
        wallet.executePending(calls, 1);

        vm.prank(emergency);
        wallet.clearVeto(operationId);

        (,,,,, MERAWalletTypes.OperationStatus statusAfter,,,,,) = wallet.operations(operationId);
        assertEq(uint256(statusAfter), uint256(MERAWalletTypes.OperationStatus.Pending));

        vm.prank(primary);
        wallet.executePending(calls, 1);
        assertEq(receiver.value(), 9);
    }

    function test_ClearVeto_BackupMayClearPrimaryVetoedOp() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 11));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        vm.prank(backup);
        wallet.clearVeto(operationId);

        (,,,,, MERAWalletTypes.OperationStatus statusAfter,,,,,) = wallet.operations(operationId);
        assertEq(uint256(statusAfter), uint256(MERAWalletTypes.OperationStatus.Pending));
    }

    function test_ClearVeto_EmergencyMayClearBackupVetoedOp() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Backup);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 12));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        vm.prank(emergency);
        wallet.clearVeto(operationId);

        (,,,,, MERAWalletTypes.OperationStatus statusAfter,,,,,) = wallet.operations(operationId);
        assertEq(uint256(statusAfter), uint256(MERAWalletTypes.OperationStatus.Pending));
    }

    function test_ClearVeto_PrimaryCannotClearBackupVetoedOp() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Backup);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 12));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CannotClearVeto.selector, operationId));
        wallet.clearVeto(operationId);
    }

    function test_ClearVeto_PrimaryCannotClearOwnTierVetoedOp() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 13));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CannotClearVeto.selector, operationId));
        wallet.clearVeto(operationId);
    }

    function test_ClearVeto_BackupCannotClearOwnTierVetoedOp() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Backup);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 14));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        vm.prank(backup);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CannotClearVeto.selector, operationId));
        wallet.clearVeto(operationId);
    }

    function test_Agent_CanVetoEmergencyProposedOperation() public {
        vm.prank(emergency);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Emergency);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 7));

        vm.prank(emergency);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Vetoed));
    }

    function test_VetoPending_PrimaryAgentCannotVetoBackupCreatorOperation() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Primary);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 31));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CannotVetoOperation.selector, operationId));
        wallet.vetoPending(operationId);
    }

    function test_VetoPending_BackupAgentCanVetoBackupCreatorOperation() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Backup);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 32));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Vetoed));
    }

    function test_VetoPending_BackupOwnerCanVetoPrimaryCreatorOperation() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 33));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
        wallet.vetoPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Vetoed));
    }

    function test_VetoPending_BackupOwnerCanVetoBackupCreatorOperation() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 34));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
        wallet.vetoPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Vetoed));
    }

    function test_VetoPending_PrimaryOwnerCannotVetoBackupCreatorOperation() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 36));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CannotVetoOperation.selector, operationId));
        wallet.vetoPending(operationId);
    }

    function test_VetoPending_FrozenCoreOwnerCannotVeto() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 35));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(emergency);
        wallet.setFrozenBackup(true);

        vm.prank(backup);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Backup));
        wallet.vetoPending(operationId);
    }

    function test_EmergencyAgent_Expires() public {
        vm.startPrank(emergency);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Emergency);
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Emergency, uint256(1 days)),
            907
        );
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 7));

        vm.prank(emergency);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.warp(block.timestamp + wallet.emergencyAgentLifetime() + 1);

        vm.prank(agentAddr);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.AgentExpired.selector, agentAddr, 30 days + 1));
        wallet.vetoPending(operationId);
    }

    function test_Agent_CannotCancelPending() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 3));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        wallet.cancelPending(operationId);
    }

    function test_CancelPending_AfterVeto_Irreversible() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 21));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        vm.prank(primary);
        wallet.cancelPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Cancelled));
    }

    function test_Agent_CoreRoleUnaffectedByVetoSlotOnPrimaryAddress() public {
        vm.startPrank(emergency);
        _agentsCall(wallet, primary, true);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 7));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.TimelockRequired.selector, 1 days));
        wallet.executeTransaction(calls, 1);
    }

    function test_Agent_DisableWhenNotEnabled_Reverts() public {
        vm.prank(backup);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallExecutionFailed.selector,
                uint256(0),
                abi.encodeWithSelector(IBaseMERAWalletErrors.NoopAgent.selector)
            )
        );
        _agentsCall(wallet, agentAddr, false);
    }

    function test_SetRequiredChecker_RevertsForNoopConfig() public {
        vm.prank(emergency);
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(checkerNoHooks), true);
            _expectWalletSelfCallRevert(
                abi.encodeWithSelector(IBaseMERAWalletErrors.NoopCheckerConfig.selector),
                abi.encodeWithSelector(wallet.setRequiredCheckers.selector, __rqA, __rqB),
                908
            );
        }
    }

    function test_SetOptionalChecker_RevertsForNoopConfigOnNonZeroChecker() public {
        vm.prank(emergency);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.NoopCheckerConfig.selector),
            abi.encodeWithSelector(wallet.setOptionalCheckers.selector, _mkWl(address(checkerNoHooks), true, "")),
            909
        );
    }

    function test_SetOptionalChecker_AppliesSlippageCheckerAssetWhitelistConfig() public {
        MERAWalletUniswapV2OracleSlippageChecker slip =
            new MERAWalletUniswapV2OracleSlippageChecker(emergency, 100, 3600);
        MERAWalletUniswapV2AssetWhitelist aw = new MERAWalletUniswapV2AssetWhitelist(emergency);
        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg =
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({assetWhitelist: address(aw)});

        vm.startPrank(emergency);
        _setOptionalCheckers(_mkWl(address(slip), true, abi.encode(cfg)));
        vm.stopPrank();

        (address storedWl) = slip.walletSlippageCheckerConfig(address(wallet));
        assertEq(storedWl, address(aw));
    }

    function test_SetOptionalChecker_AppliesConfigToConfigurableChecker() public {
        bytes memory cfg = abi.encode(true, false);
        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(checkerBeforeOnly), true, cfg));
        assertTrue(checkerBeforeOnly.revertBefore());
        assertFalse(checkerBeforeOnly.revertAfter());
    }

    function test_ExecuteTransaction_RevertsWhenOptionalCheckerNotAllowed() public {
        MERAWalletTypes.Call[] memory calls = _singleCallWithChecker(
            address(receiver),
            0,
            abi.encodeWithSelector(ReceiverMock.setValue.selector, 123),
            address(checkerBothHooks),
            abi.encodePacked(uint256(42))
        );

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.OptionalCheckerNotAllowed.selector, address(checkerBothHooks), 0
            )
        );
        wallet.executeTransaction(calls, 1);
    }

    function test_ExecuteTransaction_RevertsWhenZeroOptionalCheckerNotAllowed() public {
        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(0), false, ""));

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 456));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.OptionalCheckerNotAllowed.selector, address(0), 0));
        wallet.executeTransaction(calls, 1);
    }

    function test_OptionalChecker_BeforeOnlyMode() public {
        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(checkerBeforeOnly), true, ""));

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
        wallet.executeTransaction(calls, 1);
    }

    function test_OptionalChecker_AfterOnlyMode() public {
        vm.prank(emergency);
        _setOptionalCheckers(_mkWl(address(checkerAfterOnly), true, ""));

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
        wallet.executeTransaction(calls, 1);

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

    function test_Freeze_PrimaryCanFreezeSelfButCannotUnfreezeSelf() public {
        vm.prank(primary);
        wallet.setFrozenPrimary(true);
        assertTrue(wallet.frozenPrimary());

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Primary));
        wallet.setFrozenPrimary(false);
    }

    function test_Freeze_BackupCanFreezeSelfButCannotUnfreezeSelf() public {
        vm.prank(backup);
        wallet.setFrozenBackup(true);
        assertTrue(wallet.frozenBackup());

        vm.prank(backup);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Backup));
        wallet.setFrozenBackup(false);
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
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Backup);

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

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setPrimary.selector, newPrimary), 919);

        vm.prank(backup);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setPrimary.selector, newPrimary), 920);
        assertEq(wallet.primary(), newPrimary);
    }

    function test_FrozenPrimary_PrimaryCannotSetAgent_BackupCan() public {
        vm.prank(backup);
        wallet.setFrozenPrimary(true);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Primary));
        _agentsCall(wallet, agentAddr, true);

        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);
        (MERAWalletTypes.Role role,) = wallet.agents(agentAddr);
        assertEq(uint256(role), uint256(MERAWalletTypes.Role.Primary));
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
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 8));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
        wallet.setFrozenPrimary(true);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Vetoed));
    }

    function test_FrozenPrimary_Emergency_ConfigUnaffected() public {
        vm.prank(backup);
        wallet.setFrozenPrimary(true);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(3 days);
        vm.stopPrank();
        assertEq(wallet.roleTimelock(MERAWalletTypes.Role.Primary), 3 days);
    }

    function test_FrozenPrimary_BackupExecutePending_AfterPrimaryProposed() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 99));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
        wallet.setFrozenPrimary(true);

        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(operationId);
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
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.NotAllowedRoleChange.selector),
            abi.encodeWithSelector(wallet.setBackup.selector, newBackup),
            921
        );

        vm.prank(backup);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RoleFrozen.selector, MERAWalletTypes.Role.Backup));
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setBackup.selector, newBackup), 922);

        vm.prank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setBackup.selector, newBackup), 923);
        assertEq(wallet.backup(), newBackup);
    }

    /// @dev `executePending` has `whenControllerCoreAvailable`, so outsiders cannot relay-execute.
    /// For non-{CoreExecute} relay policy, `_executePending` rejects core controllers (`CoreExecutorNotAllowed`).
    /// This test documents reachable reverts around relay execution.
    function test_ProposeWithRelay_Anyone_ExternalExecutorGetsReward() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 717));
        MERAWalletTypes.RelayProposeConfig memory relayConfig = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Anyone, address(0), bytes32(0), uint64(block.timestamp + 8 days)
        );

        vm.deal(primary, 1 ether);
        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransactionWithRelay{value: 1 ether}(calls, 1, relayConfig);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(operationId);
        vm.warp(executeAfter);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CoreExecutorNotAllowed.selector, primary));
        wallet.executePending(calls, 1);

        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        wallet.executePending(calls, 1);

        assertEq(receiver.value(), 0);
        assertEq(address(wallet).balance, 1 ether);
        (,,,,,,, uint256 relayReward,,,) = wallet.operations(operationId);
        assertEq(relayReward, 1 ether);
    }

    /// @dev See {test_ProposeWithRelay_Anyone_ExternalExecutorGetsReward}: only core controllers reach the body,
    /// non-core callers revert at gate; `{Designated}` path still rejects cores before `_validateRelayExecutor`.
    function test_ProposeWithRelay_Designated_OnlyDesignatedCanExecute() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        address designated = address(0xD3516);
        address randomRelayer = address(0xCA11);
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 808));
        MERAWalletTypes.RelayProposeConfig memory relayConfig = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Designated, designated, bytes32(0), uint64(block.timestamp + 8 days)
        );

        vm.deal(primary, 0.25 ether);
        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransactionWithRelay{value: 0.25 ether}(calls, 1, relayConfig);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(operationId);
        vm.warp(executeAfter);

        vm.prank(randomRelayer);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        wallet.executePending(calls, 1);

        vm.prank(backup);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CoreExecutorNotAllowed.selector, backup));
        wallet.executePending(calls, 1);

        vm.prank(designated);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        wallet.executePending(calls, 1);

        assertEq(receiver.value(), 0);
        assertEq(address(wallet).balance, 0.25 ether);
    }

    /// @dev Non-core callers never reach `{Whitelist}` relay checks (`Unauthorized` at entry); core callers hit
    /// `CoreExecutorNotAllowed` before `_validateRelayExecutor`.
    function test_ProposeWithRelay_Whitelist_ValidatesHashAndExecutor() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        address whitelistRelayerA = outsider;
        address whitelistRelayerB = address(0xBEEF);
        address[] memory whitelist = new address[](2);
        whitelist[0] = whitelistRelayerA;
        whitelist[1] = whitelistRelayerB;

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 909));
        MERAWalletTypes.RelayProposeConfig memory relayConfig = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Whitelist,
            address(0),
            keccak256(abi.encode(whitelist)),
            uint64(block.timestamp + 8 days)
        );

        vm.deal(primary, 0.4 ether);
        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransactionWithRelay{value: 0.4 ether}(calls, 1, relayConfig);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(operationId);
        vm.warp(executeAfter);

        address[] memory wrongWhitelist = new address[](2);
        wrongWhitelist[0] = whitelistRelayerB;
        wrongWhitelist[1] = whitelistRelayerA;
        vm.prank(whitelistRelayerA);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        wallet.executePending(calls, 1, wrongWhitelist);

        vm.prank(address(0xFA11));
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        wallet.executePending(calls, 1, whitelist);

        vm.prank(backup);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CoreExecutorNotAllowed.selector, backup));
        wallet.executePending(calls, 1, whitelist);

        assertEq(receiver.value(), 0);
        assertEq(address(wallet).balance, 0.4 ether);
    }

    function test_CancelPending_RefundsRelayRewardToCreator() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 123));
        MERAWalletTypes.RelayProposeConfig memory relayConfig = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Anyone, address(0), bytes32(0), uint64(block.timestamp + 8 days)
        );

        vm.deal(primary, 2 ether);
        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransactionWithRelay{value: 0.6 ether}(calls, 1, relayConfig);
        assertEq(address(wallet).balance, 0.6 ether);

        vm.prank(primary);
        wallet.cancelPending(operationId);

        assertEq(address(wallet).balance, 0);
        assertEq(primary.balance, 2 ether);
        (,,,,,,, uint256 relayReward,,,) = wallet.operations(operationId);
        assertEq(relayReward, 0);
    }

    function test_ProposeWithRelay_RelayDeadlineRequired_Reverts() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));
        MERAWalletTypes.RelayProposeConfig memory relayConfig =
            _relayConfig(MERAWalletTypes.RelayExecutorPolicy.Anyone, address(0), bytes32(0), uint64(0));

        vm.deal(primary, 1 ether);
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.RelayDeadlineRequired.selector);
        wallet.proposeTransactionWithRelay{value: 1 ether}(calls, 1, relayConfig);
    }

    function test_ProposeWithRelay_RelayDeadlineBeforeTimelock_Reverts() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        uint64 badDeadline = uint64(block.timestamp + 12 hours);
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));
        MERAWalletTypes.RelayProposeConfig memory relayConfig =
            _relayConfig(MERAWalletTypes.RelayExecutorPolicy.Anyone, address(0), bytes32(0), badDeadline);

        vm.deal(primary, 1 ether);
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.RelayDeadlineBeforeTimelock.selector,
                badDeadline,
                uint256(block.timestamp + 1 days)
            )
        );
        wallet.proposeTransactionWithRelay{value: 1 ether}(calls, 1, relayConfig);
    }

    function test_ProposeWithRelay_AfterRelayDeadline_Reverts() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        uint256 t0 = block.timestamp;
        uint64 relayDeadline = uint64(t0 + 1 days + 5);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 717));
        MERAWalletTypes.RelayProposeConfig memory relayConfig =
            _relayConfig(MERAWalletTypes.RelayExecutorPolicy.Anyone, address(0), bytes32(0), relayDeadline);

        vm.deal(primary, 1 ether);
        vm.prank(primary);
        wallet.proposeTransactionWithRelay{value: 1 ether}(calls, 1, relayConfig);

        vm.warp(t0 + 1 days + 6);

        // Core controller is required to pass `whenControllerCoreAvailable` (outsiders revert with `Unauthorized` first).
        vm.prank(backup);
        vm.expectRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.RelayExecutionExpired.selector, relayDeadline, t0 + 1 days + 6)
        );
        wallet.executePending(calls, 1);
    }

    function _callPathPolicy(uint56 primaryDelay, bool primaryForbidden, uint56 backupDelay, bool backupForbidden)
        internal
        pure
        returns (MERAWalletTypes.CallPathPolicy memory p)
    {
        return _callPathPolicy(primaryDelay, primaryForbidden, backupDelay, backupForbidden, 0);
    }

    function _callPathPolicy(
        uint56 primaryDelay,
        bool primaryForbidden,
        uint56 backupDelay,
        bool backupForbidden,
        uint56 emergencyDelay
    ) internal pure returns (MERAWalletTypes.CallPathPolicy memory p) {
        p.primary = MERAWalletTypes.RoleCallPolicy({delay: primaryDelay, forbidden: primaryForbidden});
        p.backup = MERAWalletTypes.RoleCallPolicy({delay: backupDelay, forbidden: backupForbidden});
        p.emergencyDelay = emergencyDelay;
        p.exists = true;
    }

    /// @dev Policies with `exists == false`.
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

    function _mkAgents(address a, MERAWalletTypes.Role role)
        internal
        pure
        returns (address[] memory aa, MERAWalletTypes.Role[] memory rr)
    {
        aa = new address[](1);
        rr = new MERAWalletTypes.Role[](1);
        aa[0] = a;
        rr[0] = role;
    }

    function _agentsCall(BaseMERAWallet w, address agent, bool enabled) internal {
        MERAWalletTypes.Role role = enabled ? MERAWalletTypes.Role.Primary : MERAWalletTypes.Role.None;
        _agentsCall(w, agent, role);
    }

    function _agentsCall(BaseMERAWallet w, address agent, MERAWalletTypes.Role role) internal {
        (address[] memory aa, MERAWalletTypes.Role[] memory rr) = _mkAgents(agent, role);
        _executeWalletSelfCallOn(w, abi.encodeWithSelector(w.setAgents.selector, aa, rr), 7501);
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

    function _setAllRoleTimelocksOn(BaseMERAWallet w, uint256 delay) internal {
        _executeWalletSelfCallOn(
            w, abi.encodeWithSelector(w.setRoleTimelock.selector, MERAWalletTypes.Role.Primary, delay), 7201
        );
        _executeWalletSelfCallOn(
            w, abi.encodeWithSelector(w.setRoleTimelock.selector, MERAWalletTypes.Role.Backup, delay), 7202
        );
        _executeWalletSelfCallOn(
            w, abi.encodeWithSelector(w.setRoleTimelock.selector, MERAWalletTypes.Role.Emergency, delay), 7203
        );
    }

    /// @dev Applies one target policy via `setTargetCallPolicies` (singleton batch).
    function _policyTarget(address target, MERAWalletTypes.CallPathPolicy memory pol) internal {
        address[] memory ts = new address[](1);
        MERAWalletTypes.CallPathPolicy[] memory ps = new MERAWalletTypes.CallPathPolicy[](1);
        ts[0] = target;
        ps[0] = pol;
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setTargetCallPolicies.selector, ts, ps), 7301);
    }

    /// @dev Applies one selector policy via `setSelectorCallPolicies`.
    function _policySelector(bytes4 sel, MERAWalletTypes.CallPathPolicy memory pol) internal {
        bytes4[] memory ss = new bytes4[](1);
        MERAWalletTypes.CallPathPolicy[] memory ps = new MERAWalletTypes.CallPathPolicy[](1);
        ss[0] = sel;
        ps[0] = pol;
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setSelectorCallPolicies.selector, ss, ps), 7302);
    }

    /// @dev Applies one (target, selector) pair policy via `setTargetSelectorCallPolicies`.
    function _policyPair(address target, bytes4 sel, MERAWalletTypes.CallPathPolicy memory pol) internal {
        address[] memory ts = new address[](1);
        bytes4[] memory ss = new bytes4[](1);
        MERAWalletTypes.CallPathPolicy[] memory ps = new MERAWalletTypes.CallPathPolicy[](1);
        ts[0] = target;
        ss[0] = sel;
        ps[0] = pol;
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setTargetSelectorCallPolicies.selector, ts, ss, ps), 7303);
    }

    function _mkWl(address checker, bool allowed, bytes memory config)
        internal
        pure
        returns (MERAWalletTypes.OptionalCheckerUpdate[] memory u)
    {
        u = new MERAWalletTypes.OptionalCheckerUpdate[](1);
        u[0] = MERAWalletTypes.OptionalCheckerUpdate({checker: checker, allowed: allowed, config: config});
    }

    function _setRequiredCheckers(address[] memory checkers, bool[] memory enabled) internal {
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setRequiredCheckers.selector, checkers, enabled), 7401);
    }

    function _setOptionalCheckers(MERAWalletTypes.OptionalCheckerUpdate[] memory updates) internal {
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setOptionalCheckers.selector, updates), 7402);
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

    function _executeWalletSelfCall(bytes memory data, uint256 salt) internal {
        wallet.executeTransaction(_singleCall(address(wallet), 0, data), salt);
    }

    function _executeWalletSelfCallOn(BaseMERAWallet w, bytes memory data, uint256 salt) internal {
        w.executeTransaction(_singleCall(address(w), 0, data), salt);
    }

    function _expectWalletSelfCallRevert(bytes memory innerRevertData, bytes memory data, uint256 salt) internal {
        vm.expectRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.CallExecutionFailed.selector, uint256(0), innerRevertData)
        );
        _executeWalletSelfCall(data, salt);
    }

    function _relayConfig(
        MERAWalletTypes.RelayExecutorPolicy relayPolicy,
        address designatedExecutor,
        bytes32 executorSetHash,
        uint64 relayExecuteBefore
    ) internal pure returns (MERAWalletTypes.RelayProposeConfig memory relayConfig) {
        relayConfig = MERAWalletTypes.RelayProposeConfig({
                relayPolicy: relayPolicy,
                designatedExecutor: designatedExecutor,
                executorSetHash: executorSetHash,
                relayExecuteBefore: relayExecuteBefore
            });
    }

    function _signDigest(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // ─── Migration Mode ───────────────────────────────────────────────────────

    function test_SetMigrationTarget_OnlyEmergency() public {
        address newTarget = address(0xCAFE);

        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.NotEmergency.selector);
        wallet.setMigrationTarget(newTarget);

        vm.prank(backup);
        vm.expectRevert(IBaseMERAWalletErrors.NotEmergency.selector);
        wallet.setMigrationTarget(newTarget);
    }

    function test_SetMigrationTarget_EmitsEvent() public {
        address newTarget = address(0xCAFE);
        vm.prank(emergency);
        vm.expectEmit(true, true, true, true);
        emit IBaseMERAWalletEvents.MigrationTargetUpdated(address(0), newTarget, emergency);
        wallet.setMigrationTarget(newTarget);
        assertEq(wallet.migrationTarget(), newTarget);
    }

    function test_SetMigrationTarget_Deactivate() public {
        address newTarget = address(0xCAFE);
        vm.startPrank(emergency);
        wallet.setMigrationTarget(newTarget);
        wallet.setMigrationTarget(address(0));
        vm.stopPrank();
        assertEq(wallet.migrationTarget(), address(0));
    }

    function test_LoginMigrationRegistryCalls_DefaultToEmergencyOnly() public {
        MERAWalletLoginRegistry registry = new MERAWalletLoginRegistry(address(this));
        registry.addFactory(address(this));

        BaseMERAWallet newWallet = new BaseMERAWallet(primary, backup, emergency, address(0), address(0));
        bytes32 oldSecret = keccak256("old");
        registry.commit(registry.makeCommitment("old", address(wallet), address(this), oldSecret, 0, keccak256("")));
        vm.warp(block.timestamp + registry.MIN_COMMITMENT_AGE());
        registry.registerLogin{value: registry.priceOf("old")}("old", address(wallet), oldSecret, 0, "");
        bytes32 newSecret = keccak256("new");
        registry.commit(registry.makeCommitment("new", address(newWallet), address(this), newSecret, 0, keccak256("")));
        vm.warp(block.timestamp + registry.MIN_COMMITMENT_AGE());
        registry.registerLogin{value: registry.priceOf("new")}("new", address(newWallet), newSecret, 0, "");

        vm.prank(emergency);
        _executeWalletSelfCallOn(
            newWallet, abi.encodeWithSelector(newWallet.setOptionalCheckers.selector, _mkWl(address(0), true, "")), 7601
        );

        MERAWalletTypes.Call[] memory requestCalls = _singleCall(
            address(registry),
            0,
            abi.encodeWithSelector(
                MERAWalletLoginRegistry.requestLoginMigration.selector, "old", "new", address(newWallet)
            )
        );

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallPathForbiddenForRole.selector, MERAWalletTypes.Role.Primary
            )
        );
        wallet.executeTransaction(requestCalls, 7602);

        vm.prank(backup);
        vm.expectRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.CallPathForbiddenForRole.selector, MERAWalletTypes.Role.Backup)
        );
        wallet.executeTransaction(requestCalls, 7603);

        vm.prank(emergency);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.TimelockRequired.selector,
                MERAWalletConstants.OWNERSHIP_AND_ROLE_GRANT_SELECTOR_EMERGENCY_DELAY
            )
        );
        wallet.executeTransaction(requestCalls, 7604);
        vm.prank(emergency);
        bytes32 requestOperationId = wallet.proposeTransaction(requestCalls, 7604);
        (,,, uint64 requestExecuteAfter,,,,,,,) = wallet.operations(requestOperationId);
        vm.warp(requestExecuteAfter);
        vm.prank(emergency);
        wallet.executePending(requestCalls, 7604);

        MERAWalletTypes.Call[] memory confirmCalls = _singleCall(
            address(registry), 0, abi.encodeWithSelector(MERAWalletLoginRegistry.confirmLoginMigration.selector, "old")
        );

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallPathForbiddenForRole.selector, MERAWalletTypes.Role.Primary
            )
        );
        newWallet.executeTransaction(confirmCalls, 7605);

        vm.prank(backup);
        vm.expectRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.CallPathForbiddenForRole.selector, MERAWalletTypes.Role.Backup)
        );
        newWallet.executeTransaction(confirmCalls, 7606);

        vm.prank(emergency);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.TimelockRequired.selector,
                MERAWalletConstants.OWNERSHIP_AND_ROLE_GRANT_SELECTOR_EMERGENCY_DELAY
            )
        );
        newWallet.executeTransaction(confirmCalls, 7607);
        vm.prank(emergency);
        bytes32 confirmOperationId = newWallet.proposeTransaction(confirmCalls, 7607);
        (,,, uint64 confirmExecuteAfter,,,,,,,) = newWallet.operations(confirmOperationId);
        vm.warp(confirmExecuteAfter);
        vm.prank(emergency);
        newWallet.executePending(confirmCalls, 7607);

        assertEq(registry.walletOf("old"), address(newWallet));
        assertEq(registry.walletOf("new"), address(wallet));
        assertEq(registry.loginHashByWallet(address(wallet)), keccak256(bytes("new")));
        assertEq(registry.loginHashByWallet(address(newWallet)), keccak256(bytes("old")));
    }

    function test_ExecuteMigration_NoTargetSet_Reverts() public {
        OwnableMock ext = new OwnableMock();
        address someTarget = address(0x1111);
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(ext), 0, abi.encodeWithSignature("transferOwnership(address)", someTarget));

        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.MigrationModeNotActive.selector);
        wallet.executeMigrationTransaction(calls, 1);
    }

    function test_ExecuteMigration_NonCoreController_Reverts() public {
        OwnableMock ext = new OwnableMock();
        address target = address(0x2222);
        vm.prank(emergency);
        wallet.setMigrationTarget(target);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(ext), 0, abi.encodeWithSignature("transferOwnership(address)", target));

        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        wallet.executeMigrationTransaction(calls, 1);
    }

    function test_ExecuteMigration_RevertsDuringSafeMode() public {
        OwnableMock ext = new OwnableMock();
        address target = address(0x2222);
        vm.startPrank(emergency);
        wallet.setMigrationTarget(target);
        wallet.enterSafeMode(30 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(ext), 0, abi.encodeWithSignature("transferOwnership(address)", target));

        vm.prank(emergency);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.SafeModeActive.selector, wallet.safeModeBefore()));
        wallet.executeMigrationTransaction(calls, 1);
    }

    function test_ExecuteMigration_TransferOwnership_Primary_Immediate() public {
        OwnableMock ext = new OwnableMock();
        address target = address(0x3333);

        vm.prank(emergency);
        wallet.setMigrationTarget(target);

        // global timelock set — migration should bypass it
        vm.startPrank(emergency);
        _setAllRoleTimelocks(7 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(ext), 0, abi.encodeWithSignature("transferOwnership(address)", target));

        vm.prank(primary);
        wallet.executeMigrationTransaction(calls, 1);

        assertEq(ext.owner(), target);
    }

    function test_ExecuteMigration_TransferOwnership_Backup_Immediate() public {
        OwnableMock ext = new OwnableMock();
        address target = address(0x4444);

        vm.prank(emergency);
        wallet.setMigrationTarget(target);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(ext), 0, abi.encodeWithSignature("transferOwnership(address)", target));

        vm.prank(backup);
        wallet.executeMigrationTransaction(calls, 1);

        assertEq(ext.owner(), target);
    }

    function test_ExecuteMigration_TransferOwnership_Emergency_Immediate() public {
        OwnableMock ext = new OwnableMock();
        address target = address(0x5555);

        vm.prank(emergency);
        wallet.setMigrationTarget(target);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(ext), 0, abi.encodeWithSignature("transferOwnership(address)", target));

        vm.prank(emergency);
        wallet.executeMigrationTransaction(calls, 1);

        assertEq(ext.owner(), target);
    }

    function test_ExecuteMigration_GrantRole_Immediate() public {
        AccessControlMock ac = new AccessControlMock();
        bytes32 role = keccak256("ADMIN_ROLE");
        address target = address(0x6666);

        vm.prank(emergency);
        wallet.setMigrationTarget(target);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(ac), 0, abi.encodeWithSignature("grantRole(bytes32,address)", role, target));

        vm.prank(primary);
        wallet.executeMigrationTransaction(calls, 1);

        assertTrue(ac.roles(role, target));
    }

    function test_ExecuteMigration_WrongRecipient_Reverts() public {
        OwnableMock ext = new OwnableMock();
        address target = address(0x7777);
        address wrong = address(0x8888);

        vm.prank(emergency);
        wallet.setMigrationTarget(target);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(ext), 0, abi.encodeWithSignature("transferOwnership(address)", wrong));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.MigrationCallNotAllowed.selector, uint256(0)));
        wallet.executeMigrationTransaction(calls, 1);
    }

    function test_ExecuteMigration_UnknownSelector_Reverts() public {
        OwnableMock ext = new OwnableMock();
        address target = address(0x9999);

        vm.prank(emergency);
        wallet.setMigrationTarget(target);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(ext), 0, abi.encodeWithSignature("someOtherFn(address)", target));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.MigrationCallNotAllowed.selector, uint256(0)));
        wallet.executeMigrationTransaction(calls, 1);
    }

    function test_ExecuteMigration_DeactivateTarget_Reverts() public {
        OwnableMock ext = new OwnableMock();
        address target = address(0xAAAA);

        vm.startPrank(emergency);
        wallet.setMigrationTarget(target);
        wallet.setMigrationTarget(address(0));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(ext), 0, abi.encodeWithSignature("transferOwnership(address)", target));

        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.MigrationModeNotActive.selector);
        wallet.executeMigrationTransaction(calls, 1);
    }

    function test_ExecuteMigration_Reusable() public {
        OwnableMock ext1 = new OwnableMock();
        OwnableMock ext2 = new OwnableMock();
        address target1 = address(0xBBBB);
        address target2 = address(0xCCCC);

        vm.prank(emergency);
        wallet.setMigrationTarget(target1);

        MERAWalletTypes.Call[] memory calls1 =
            _singleCall(address(ext1), 0, abi.encodeWithSignature("transferOwnership(address)", target1));
        vm.prank(primary);
        wallet.executeMigrationTransaction(calls1, 1);
        assertEq(ext1.owner(), target1);

        vm.prank(emergency);
        wallet.setMigrationTarget(target2);

        MERAWalletTypes.Call[] memory calls2 =
            _singleCall(address(ext2), 0, abi.encodeWithSignature("transferOwnership(address)", target2));
        vm.prank(primary);
        wallet.executeMigrationTransaction(calls2, 2);
        assertEq(ext2.owner(), target2);
    }

    function test_ExecuteMigration_EmitsEvent() public {
        OwnableMock ext = new OwnableMock();
        address target = address(0xDDDD);

        vm.prank(emergency);
        wallet.setMigrationTarget(target);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(ext), 0, abi.encodeWithSignature("transferOwnership(address)", target));

        bytes32 expectedOpId = wallet.getOperationId(calls, 1);

        vm.prank(primary);
        vm.expectEmit(true, false, true, true);
        emit IBaseMERAWalletEvents.MigrationTransactionExecuted(expectedOpId, 1, primary);
        wallet.executeMigrationTransaction(calls, 1);
    }
}

contract OwnableMock {
    address public owner;

    function transferOwnership(address newOwner) external {
        owner = newOwner;
    }
}

contract AccessControlMock {
    mapping(bytes32 => mapping(address => bool)) public roles;

    function grantRole(bytes32 role, address account) external {
        roles[role][account] = true;
    }
}
