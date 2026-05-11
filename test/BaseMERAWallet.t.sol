// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {IBaseMERAWalletErrors} from "../src/interfaces/IBaseMERAWalletErrors.sol";
import {MERAWalletConstants} from "../src/constants/MERAWalletConstants.sol";
import {MERAWalletLoginRegistryConstants} from "../src/constants/MERAWalletLoginRegistryConstants.sol";
import {MERAWalletLoginRegistry} from "../src/MERAWalletLoginRegistry.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletUniswapV2OracleSlippageChecker} from "../src/checkers/MERAWalletUniswapV2OracleSlippageChecker.sol";
import {MERAWalletAssetWhiteList} from "../src/checkers/whitelists/MERAWalletAssetWhiteList.sol";
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

    function exposedCallWithExecutionContext(MERAWalletTypes.Call calldata callData, MERAWalletTypes.Role contextRole)
        external
        returns (bool success, bytes memory result)
    {
        return _callWithExecutionContext(callData, contextRole);
    }

    function exposedSetAgent(address agent, MERAWalletTypes.Role roleLevel) external {
        _setAgent(agent, roleLevel);
    }

    function exposedSetFrozenRole(MERAWalletTypes.Role targetRole, bool frozen) external {
        _setFrozenRole(targetRole, frozen);
    }

    function exposedRemoveMissingAfterChecker(address checker) external {
        _removeChecker(requiredAfterCheckers, _requiredAfterIndexPlusOne, checker);
    }

    function exposedRoleRank(MERAWalletTypes.Role role) external pure returns (uint256) {
        return _roleRank(role);
    }

    function exposedRolePolicySlice(MERAWalletTypes.CallPathPolicy calldata policy, MERAWalletTypes.Role role)
        external
        pure
        returns (MERAWalletTypes.RoleCallPolicy memory)
    {
        return _rolePolicySlice(policy, role);
    }

    function exposedValidateRelayConfig(MERAWalletTypes.RelayProposeConfig calldata relayConfig, uint256 reward)
        external
        pure
    {
        _validateRelayConfig(relayConfig, reward);
    }
}

contract BaseMERAWalletTest is Test {
    uint256 internal constant PRIMARY_PK = 0xA11CE;
    uint256 internal constant BACKUP_PK = 0xB0B;
    uint256 internal constant EMERGENCY_PK = 0xE911;
    uint256 internal constant DEFAULT_MAX_ORACLE_NEGATIVE_DEVIATION_BPS = 100;
    uint256 internal constant DEFAULT_MAX_ORACLE_STALE_SECONDS = 3600;
    uint256 internal constant ROLE_TIMELOCK_PRIMARY_SALT = 7101;
    uint256 internal constant ROLE_TIMELOCK_BACKUP_SALT = 7102;
    uint256 internal constant ROLE_TIMELOCK_EMERGENCY_SALT = 7103;

    uint256 internal primaryPk = PRIMARY_PK;
    uint256 internal backupPk = BACKUP_PK;
    uint256 internal emergencyPk = EMERGENCY_PK;

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
        _executeEmergencyWalletSelfCallTimelocked(
            abi.encodeWithSelector(wallet.setOptionalCheckers.selector, _mkWl(address(0), true, "")), 7001
        );
        vm.stopPrank();
    }

    /// @dev Nested public `executeTransaction` from a self-call in the same batch must revert (reentrancy guard).
    function test_Reentrancy_BlocksNestedExecuteTransaction() public {
        MERAWalletTypes.Call[] memory inner =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));
        bytes memory innerTx = abi.encodeWithSelector(BaseMERAWallet.executeTransaction.selector, inner, uint256(999));
        MERAWalletTypes.Call[] memory outer = _singleCall(address(wallet), 0, innerTx);
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallExecutionFailed.selector,
                uint256(0),
                abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector)
            )
        );
        wallet.executeTransaction(outer, 12_001);
    }

    /// @dev Nested `proposeTransaction` from within `executeTransaction` must revert before body (same guard).
    function test_Reentrancy_BlocksNestedProposeTransaction() public {
        MERAWalletTypes.Call[] memory inner =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));
        bytes memory innerPropose =
            abi.encodeWithSelector(BaseMERAWallet.proposeTransaction.selector, inner, uint256(42));
        MERAWalletTypes.Call[] memory outer = _singleCall(address(wallet), 0, innerPropose);
        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallExecutionFailed.selector,
                uint256(0),
                abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector)
            )
        );
        wallet.executeTransaction(outer, 12_002);
    }

    function test_SetPrimary_DirectPrimaryReverts() public {
        address newPrimary = address(0x9999);
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setPrimary(newPrimary);
    }

    function test_SetPrimary_SelfCallEmitsUpdatedEvent() public {
        address newPrimary = address(0x9999);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit IBaseMERAWalletEvents.PrimaryUpdated(primary, newPrimary);
        vm.prank(primary);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setPrimary.selector, newPrimary), 910);
        assertEq(wallet.primary(), newPrimary);
    }

    function test_SetPrimary_SelfCallRevertsForWalletAddress() public {
        vm.prank(primary);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.WalletCannotBeCoreRole.selector),
            abi.encodeWithSelector(wallet.setPrimary.selector, address(wallet)),
            9101
        );
    }

    function test_SetPrimary_SelfCallRevertsDuringSafeMode() public {
        BaseMERAWalletHarness h = new BaseMERAWalletHarness(primary, backup, emergency, address(0), address(0));
        vm.prank(emergency);
        h.enterSafeMode(MERAWalletConstants.SAFE_MODE_MIN_DURATION);

        MERAWalletTypes.Call memory callData = MERAWalletTypes.Call({
            target: address(h),
            value: 0,
            data: abi.encodeWithSelector(h.setPrimary.selector, address(0x9999)),
            checker: address(0),
            checkerData: ""
        });

        (bool success, bytes memory result) = h.exposedCallWithExecutionContext(callData, MERAWalletTypes.Role.Primary);

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

    function test_SetBackup_SelfCallRevertsForWalletAddress() public {
        vm.prank(backup);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.WalletCannotBeCoreRole.selector),
            abi.encodeWithSelector(wallet.setBackup.selector, address(wallet)),
            9121
        );
    }

    function test_SetBackup_SelfCallRevertsDuringSafeMode() public {
        BaseMERAWalletHarness h = new BaseMERAWalletHarness(primary, backup, emergency, address(0), address(0));
        vm.prank(emergency);
        h.enterSafeMode(MERAWalletConstants.SAFE_MODE_MIN_DURATION);

        MERAWalletTypes.Call memory callData = MERAWalletTypes.Call({
            target: address(h),
            value: 0,
            data: abi.encodeWithSelector(h.setBackup.selector, address(0xBEEF)),
            checker: address(0),
            checkerData: ""
        });

        (bool success, bytes memory result) = h.exposedCallWithExecutionContext(callData, MERAWalletTypes.Role.Backup);

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

    function test_SetEmergency_SelfCallEmitsUpdatedEvent() public {
        address newEmergency = address(0xE2E2);

        vm.expectEmit(true, true, true, true, address(wallet));
        emit IBaseMERAWalletEvents.EmergencyUpdated(emergency, newEmergency);
        vm.prank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setEmergency.selector, newEmergency), 925);

        assertEq(wallet.emergency(), newEmergency);
    }

    function test_SetEmergency_SelfCallRevertsForWalletAddress() public {
        vm.prank(emergency);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.WalletCannotBeCoreRole.selector),
            abi.encodeWithSelector(wallet.setEmergency.selector, address(wallet)),
            9251
        );
    }

    function test_SetEmergency_ResetsPendingTransactionsInvalidBeforeAndCount() public {
        vm.prank(emergency);
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Primary, uint256(1 days)), 929
        );

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));

        vm.prank(primary);
        wallet.proposeTransaction(calls, 1);
        assertEq(wallet.pendingTransactionsCount(), 1);

        uint256 resetAt = block.timestamp + 10;
        vm.warp(resetAt);
        address newEmergency = address(0xE2E3);

        vm.prank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setEmergency.selector, newEmergency), 930);

        assertEq(wallet.emergency(), newEmergency);
        assertEq(wallet.pendingTransactionsInvalidBefore(), resetAt);
        assertEq(wallet.pendingTransactionsCount(), 0);
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

        assertEq(w.roleTimelock(MERAWalletTypes.Role.Primary), MERAWalletConstants.DEFAULT_PRIMARY_TIMELOCK);
        assertEq(w.roleTimelock(MERAWalletTypes.Role.Backup), MERAWalletConstants.DEFAULT_BACKUP_TIMELOCK);
        assertEq(w.roleTimelock(MERAWalletTypes.Role.Emergency), MERAWalletConstants.DEFAULT_EMERGENCY_TIMELOCK);
        assertEq(w.emergencyAgentLifetime(), MERAWalletConstants.DEFAULT_EMERGENCY_AGENT_LIFETIME);
    }

    function test_DefaultAdminSelectorPolicies_EmergencyHasNoTimelock_PrimaryAndBackupForbidden() public view {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = wallet.setTargetCallPolicies.selector;
        selectors[1] = wallet.setSelectorCallPolicies.selector;
        selectors[2] = wallet.setTargetSelectorCallPolicies.selector;
        selectors[3] = wallet.setRequiredCheckers.selector;
        selectors[4] = wallet.setOptionalCheckers.selector;

        for (uint256 i = 0; i < selectors.length;) {
            (
                MERAWalletTypes.RoleCallPolicy memory primaryPolicy,
                MERAWalletTypes.RoleCallPolicy memory backupPolicy,
                uint256 emergencyDelay,
                bool exists
            ) = wallet.callPolicyBySelector(selectors[i]);
            assertTrue(exists);
            assertTrue(primaryPolicy.forbidden);
            assertTrue(backupPolicy.forbidden);
            assertEq(primaryPolicy.delay, 0);
            assertEq(backupPolicy.delay, 0);
            assertEq(emergencyDelay, 0);
            unchecked {
                ++i;
            }
        }
    }

    function test_DefaultAdminSelectorPolicies_SetOptionalCheckers_EmergencyExecutesWithoutTimelock() public {
        MERAWalletTypes.Call[] memory calls = _singleCall(
            address(wallet), 0, abi.encodeWithSelector(wallet.setOptionalCheckers.selector, _mkWl(address(0), true, ""))
        );

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallPathForbiddenForRole.selector, MERAWalletTypes.Role.Primary
            )
        );
        wallet.executeTransaction(calls, 6011);

        vm.prank(backup);
        vm.expectRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.CallPathForbiddenForRole.selector, MERAWalletTypes.Role.Backup)
        );
        wallet.executeTransaction(calls, 6012);

        vm.prank(emergency);
        wallet.executeTransaction(calls, 6013);
    }

    function test_GuardianCanEnterSafeModeAndRotationClearsIt() public {
        address guardianAddr = vm.addr(0xCAFE);
        BaseMERAWallet w = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddr);

        // safeModeBefore is the timestamp when restrictions lift (entered + duration).
        uint256 expectedExpiry = block.timestamp + MERAWalletConstants.SAFE_MODE_MIN_DURATION;
        vm.prank(guardianAddr);
        w.enterSafeMode(MERAWalletConstants.SAFE_MODE_MIN_DURATION);
        assertTrue(w.safeModeUsed());
        assertEq(w.safeModeBefore(), expectedExpiry);

        address newEmergency = address(0xE2E2);
        vm.prank(guardianAddr);
        w.setEmergency(newEmergency);

        assertEq(w.emergency(), newEmergency);
        // Guardian rotation zeroes the deadline; the one-shot flag clears only via resetSafeMode.
        assertTrue(w.safeModeUsed());
        assertEq(w.safeModeBefore(), 0);
        vm.startPrank(newEmergency);
        _executeWalletSelfCallOn(w, abi.encodeWithSelector(w.resetSafeMode.selector), 2891);
        vm.stopPrank();
        assertFalse(w.safeModeUsed());
        assertEq(w.safeModeBefore(), 0);
    }

    function test_ResetSafeMode_DirectEmergencyCallRevertsNotSelf() public {
        address guardianAddr = vm.addr(0xCAFE);
        BaseMERAWallet w = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddr);

        vm.prank(guardianAddr);
        w.enterSafeMode(MERAWalletConstants.SAFE_MODE_MIN_DURATION);
        vm.warp(w.safeModeBefore() + 1);

        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        w.resetSafeMode();
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

    function test_SetRoleTimelock_RevertsWhenCallerRankBelowTargetRole() public {
        vm.prank(primary);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.RoleTimelockChangeNotAuthorized.selector,
                MERAWalletTypes.Role.Primary,
                MERAWalletTypes.Role.Backup
            ),
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Backup, uint256(1 hours)),
            9100
        );
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

    function test_MaxTimelockDelay_EqualsNinetyDays() public pure {
        // Anchor: enforce timelock cap of 90 days
        assertEq(MERAWalletConstants.MAX_TIMELOCK_DELAY, 90 days);
    }

    function test_MaxEmergencyAgentLifetime_EqualsNinetyDays() public pure {
        assertEq(MERAWalletConstants.MAX_EMERGENCY_AGENT_LIFETIME, 90 days);
    }

    function test_SetEmergencyAgentLifetime_EmergencySelfCallSetsMax() public {
        vm.prank(emergency);
        _executeWalletSelfCall(
            abi.encodeWithSelector(
                wallet.setEmergencyAgentLifetime.selector, MERAWalletConstants.MAX_EMERGENCY_AGENT_LIFETIME
            ),
            9201
        );
        assertEq(wallet.emergencyAgentLifetime(), MERAWalletConstants.MAX_EMERGENCY_AGENT_LIFETIME);
    }

    function test_SetEmergencyAgentLifetime_PrimaryBackupSelfCallRevertsNotEmergency() public {
        vm.prank(primary);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.NotEmergency.selector),
            abi.encodeWithSelector(
                wallet.setEmergencyAgentLifetime.selector, MERAWalletConstants.MAX_EMERGENCY_AGENT_LIFETIME
            ),
            9202
        );

        vm.prank(backup);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.NotEmergency.selector),
            abi.encodeWithSelector(
                wallet.setEmergencyAgentLifetime.selector, MERAWalletConstants.MAX_EMERGENCY_AGENT_LIFETIME
            ),
            9203
        );
    }

    function test_SetEmergencyAgentLifetime_AboveMaxReverts() public {
        vm.prank(emergency);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.EmergencyAgentLifetimeTooLarge.selector,
                MERAWalletConstants.MAX_EMERGENCY_AGENT_LIFETIME + 1,
                MERAWalletConstants.MAX_EMERGENCY_AGENT_LIFETIME
            ),
            abi.encodeWithSelector(
                wallet.setEmergencyAgentLifetime.selector, MERAWalletConstants.MAX_EMERGENCY_AGENT_LIFETIME + 1
            ),
            9204
        );
    }

    function test_SetEmergencyAgentLifetime_LifeControlExpiredRevertsUntilHeartbeat() public {
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
            abi.encodeWithSelector(
                wallet.setEmergencyAgentLifetime.selector, MERAWalletConstants.MAX_EMERGENCY_AGENT_LIFETIME
            ),
            9205
        );

        vm.prank(emergency);
        wallet.confirmAlive();

        vm.prank(emergency);
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setEmergencyAgentLifetime.selector, uint256(45 days)), 9206
        );
        assertEq(wallet.emergencyAgentLifetime(), 45 days);
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
        address[] memory ts = new address[](1);
        bytes4[] memory ss = new bytes4[](1);
        MERAWalletTypes.CallPathPolicy[] memory ps = new MERAWalletTypes.CallPathPolicy[](1);
        ts[0] = address(receiver);
        ss[0] = ReceiverMock.setValue.selector;
        ps[0] = _inactiveCallPathPolicy(0, false, 0, false);
        bytes memory data = abi.encodeWithSelector(wallet.setTargetSelectorCallPolicies.selector, ts, ss, ps);
        _expectEmergencyWalletSelfCallTimelockedRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.NoopTargetSelectorCallPolicy.selector), data, 7309
        );
    }

    function test_CallPolicyByTargetSelector_PublicGetter_ReturnsStored() public {
        MERAWalletTypes.CallPathPolicy memory stored = _pairCallPathPolicy(uint56(9 days), false, uint56(1 days), true);
        vm.startPrank(emergency);
        _policyPair(address(receiver), ReceiverMock.setValue.selector, stored);
        vm.stopPrank();

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

    function test_PendingTransactionsCount_ProposeAndExecute() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory callsA =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 100));
        MERAWalletTypes.Call[] memory callsB =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 200));

        vm.prank(primary);
        wallet.proposeTransaction(callsA, 1);
        assertEq(wallet.pendingTransactionsCount(), 1);

        vm.prank(primary);
        wallet.proposeTransaction(callsB, 2);
        assertEq(wallet.pendingTransactionsCount(), 2);

        vm.warp(block.timestamp + 1 days);
        vm.prank(primary);
        wallet.executePending(callsA, 1);
        assertEq(wallet.pendingTransactionsCount(), 1);

        vm.prank(primary);
        wallet.executePending(callsB, 2);
        assertEq(wallet.pendingTransactionsCount(), 0);
    }

    function test_PendingTransactionsCount_RelayCancelDecrements() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 123));
        MERAWalletTypes.RelayProposeConfig memory relayConfig = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Anyone, address(0), bytes32(0), uint64(block.timestamp + 8 days)
        );

        vm.deal(primary, 1 ether);
        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransactionWithRelay{value: 0.25 ether}(calls, 1, relayConfig);
        assertEq(wallet.pendingTransactionsCount(), 1);

        vm.prank(primary);
        wallet.cancelPending(operationId);

        assertEq(wallet.pendingTransactionsCount(), 0);
        assertEq(primary.balance, 0.75 ether);
        assertEq(address(wallet).balance, 0.25 ether);
    }

    function test_PendingTransactionsCount_VetoAndClearDoNotChange() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Backup);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 9));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);
        assertEq(wallet.pendingTransactionsCount(), 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);
        assertEq(wallet.pendingTransactionsCount(), 1);

        vm.prank(emergency);
        wallet.clearVeto(operationId);
        assertEq(wallet.pendingTransactionsCount(), 1);

        vm.prank(backup);
        wallet.cancelPending(operationId);
        assertEq(wallet.pendingTransactionsCount(), 0);
    }

    function test_InvalidatePendingTransactions_TimelockedSelfCallResetsCounter() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory oldCalls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));

        vm.prank(primary);
        wallet.proposeTransaction(oldCalls, 1);
        assertEq(wallet.pendingTransactionsCount(), 1);

        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.invalidatePendingTransactionsBeforeCurrentTimestamp();

        MERAWalletTypes.Call[] memory invalidateCalls = _singleCall(
            address(wallet),
            0,
            abi.encodeWithSelector(wallet.invalidatePendingTransactionsBeforeCurrentTimestamp.selector)
        );

        vm.prank(primary);
        wallet.proposeTransaction(invalidateCalls, 2);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(wallet.getOperationId(invalidateCalls, 2));
        assertEq(wallet.pendingTransactionsCount(), 2);

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.TimelockNotExpired.selector, uint256(executeAfter), block.timestamp
            )
        );
        wallet.executePending(invalidateCalls, 2);

        vm.warp(executeAfter);
        vm.prank(primary);
        wallet.executePending(invalidateCalls, 2);

        assertEq(wallet.pendingTransactionsInvalidBefore(), uint256(executeAfter));
        assertEq(wallet.pendingTransactionsCount(), 0);
    }

    function test_InvalidatePendingTransactions_OlderOperationCannotExecute() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory oldCalls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));
        MERAWalletTypes.Call[] memory invalidateCalls = _singleCall(
            address(wallet),
            0,
            abi.encodeWithSelector(wallet.invalidatePendingTransactionsBeforeCurrentTimestamp.selector)
        );

        vm.prank(primary);
        bytes32 oldOperationId = wallet.proposeTransaction(oldCalls, 1);

        vm.prank(primary);
        wallet.proposeTransaction(invalidateCalls, 2);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(wallet.getOperationId(invalidateCalls, 2));

        vm.warp(executeAfter);
        vm.prank(primary);
        wallet.executePending(invalidateCalls, 2);

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.PendingTransactionInvalidated.selector, oldOperationId)
        );
        wallet.executePending(oldCalls, 1);
        assertEq(wallet.pendingTransactionsCount(), 0);
    }

    function test_InvalidatePendingTransactions_SameTimestampOperationCanExecute() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory invalidateCalls = _singleCall(
            address(wallet),
            0,
            abi.encodeWithSelector(wallet.invalidatePendingTransactionsBeforeCurrentTimestamp.selector)
        );

        vm.prank(primary);
        wallet.proposeTransaction(invalidateCalls, 1);
        (,,, uint64 invalidateExecuteAfter,,,,,,,) = wallet.operations(wallet.getOperationId(invalidateCalls, 1));

        vm.warp(invalidateExecuteAfter);
        MERAWalletTypes.Call[] memory callsBeforeReset =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 555));

        vm.prank(primary);
        bytes32 beforeResetOperationId = wallet.proposeTransaction(callsBeforeReset, 2);
        (,, uint64 beforeResetCreatedAt, uint64 beforeResetExecuteAfter,,,,,,,) =
            wallet.operations(beforeResetOperationId);

        vm.prank(primary);
        wallet.executePending(invalidateCalls, 1);

        assertEq(uint256(beforeResetCreatedAt), wallet.pendingTransactionsInvalidBefore());
        assertEq(wallet.pendingTransactionsCount(), 0);

        vm.warp(beforeResetExecuteAfter);
        vm.prank(primary);
        wallet.executePending(callsBeforeReset, 2);

        assertEq(receiver.value(), 555);
        assertEq(wallet.pendingTransactionsCount(), 0);
    }

    function test_InvalidatePendingTransactions_SameTimestampOperationAfterResetCanExecute() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory invalidateCalls = _singleCall(
            address(wallet),
            0,
            abi.encodeWithSelector(wallet.invalidatePendingTransactionsBeforeCurrentTimestamp.selector)
        );

        vm.prank(primary);
        wallet.proposeTransaction(invalidateCalls, 1);
        (,,, uint64 invalidateExecuteAfter,,,,,,,) = wallet.operations(wallet.getOperationId(invalidateCalls, 1));

        vm.warp(invalidateExecuteAfter);
        vm.prank(primary);
        wallet.executePending(invalidateCalls, 1);

        MERAWalletTypes.Call[] memory callsAfterReset =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 777));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(callsAfterReset, 2);
        (,, uint64 createdAt, uint64 executeAfter,,,,,,,) = wallet.operations(operationId);

        assertEq(uint256(createdAt), wallet.pendingTransactionsInvalidBefore());
        assertEq(wallet.pendingTransactionsCount(), 1);

        vm.warp(executeAfter);
        vm.prank(primary);
        wallet.executePending(callsAfterReset, 2);

        assertEq(receiver.value(), 777);
        assertEq(wallet.pendingTransactionsCount(), 0);
    }

    function test_GetOperationId_DiffersBySalt() public view {
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 501));

        bytes32 operationIdA = wallet.getOperationId(calls, 10);
        bytes32 operationIdB = wallet.getOperationId(calls, 11);

        assertTrue(operationIdA != operationIdB);
    }

    function test_CancelPending_BackupMayCancelPrimaryOperation() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 9));

        vm.prank(primary);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
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

    function test_CancelPending_PrimaryCannotCancelBackupOperation() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 88));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

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

    function test_CancelPending_BackupCannotCancelEmergencyOperation() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 56));

        vm.prank(emergency);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(backup);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CannotCancelOperation.selector, operationId));
        wallet.cancelPending(operationId);
    }

    function test_CancelPending_EmergencyMayCancelBackupOperation() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 57));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(emergency);
        wallet.cancelPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Cancelled));
    }

    function test_IsValidSignature_RequiresDedicatedSigner() public {
        bytes32 digest = keccak256("mera-wallet");

        bytes memory primarySignature = _signDigest(primaryPk, digest);
        bytes memory backupSignature = _signDigest(backupPk, digest);

        // No EIP-1271 signer configured: always reject (invalid magic).
        assertEq(uint256(uint32(wallet.isValidSignature(digest, primarySignature))), uint256(uint32(0xffffffff)));
        assertEq(uint256(uint32(wallet.isValidSignature(digest, backupSignature))), uint256(uint32(0xffffffff)));

        vm.prank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.set1271Signer.selector, MERAWalletTypes.Role.Backup), 906);

        assertEq(uint256(uint32(wallet.isValidSignature(digest, backupSignature))), uint256(uint32(0x1626ba7e)));
        assertEq(uint256(uint32(wallet.isValidSignature(digest, primarySignature))), uint256(uint32(0xffffffff)));
    }

    function test_SetRequiredChecker_OnlyEmergencyAndSupportsBothMode() public {
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setRequiredCheckers(_mkReq(address(checkerBothHooks), true, ""));

        vm.startPrank(emergency);
        _setRequiredCheckers(_mkReq(address(checkerBothHooks), true, ""));
        vm.stopPrank();

        (address[] memory beforeList, address[] memory afterList) = wallet.getRequiredCheckers();
        assertEq(beforeList.length, 1);
        assertEq(afterList.length, 1);
        assertEq(beforeList[0], address(checkerBothHooks));
        assertEq(afterList[0], address(checkerBothHooks));
    }

    function test_AfterChecker_RevertsAndRollsBackExecution() public {
        vm.startPrank(emergency);
        _setRequiredCheckers(_mkReq(address(checkerAfterOnly), true, ""));
        vm.stopPrank();

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
        _setRequiredCheckers(_mkReq(address(checkerBeforeOnly), true, ""));
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

    function test_Agent_SelfCallEmitsUpdatedEvent() public {
        vm.expectEmit(true, true, true, true, address(wallet));
        emit IBaseMERAWalletEvents.AgentUpdated(agentAddr, MERAWalletTypes.Role.Primary, 0);

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

    function test_VetoPending_EmergencyCoreCannotVetoEmergencyCreatorOperation() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 7));

        vm.prank(emergency);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(emergency);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CannotVetoOperation.selector, operationId));
        wallet.vetoPending(operationId);
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

        (, uint64 activeFromBefore) = wallet.agents(agentAddr);
        assertEq(activeFromBefore, 0);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 7));

        vm.prank(emergency);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        (, uint64 activeFrom) = wallet.agents(agentAddr);
        assertGt(activeFrom, 0);

        uint256 expiresAt = uint256(activeFrom) + wallet.emergencyAgentLifetime();

        MERAWalletTypes.Call[] memory calls2 =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 8));

        vm.prank(emergency);
        bytes32 operationId2 = wallet.proposeTransaction(calls2, 2);

        vm.warp(expiresAt + 1);

        vm.prank(agentAddr);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.AgentExpired.selector, agentAddr, expiresAt));
        wallet.vetoPending(operationId2);
    }

    function test_EmergencyAgent_EnterSafeMode_StartsLifetime() public {
        vm.prank(emergency);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Emergency);

        (, uint64 activeFromBefore) = wallet.agents(agentAddr);
        assertEq(activeFromBefore, 0);

        uint256 lifetimeBefore = wallet.emergencyAgentLifetime();

        vm.prank(agentAddr);
        wallet.enterSafeMode(MERAWalletConstants.SAFE_MODE_MIN_DURATION);

        assertEq(wallet.emergencyAgentLifetime(), lifetimeBefore + MERAWalletConstants.SAFE_MODE_MIN_DURATION);

        (, uint64 activeFromAfter) = wallet.agents(agentAddr);
        assertGt(activeFromAfter, 0);
    }

    /// @dev Safe mode adds `duration` to global `emergencyAgentLifetime`; already-active agents expire at activeFrom + new lifetime.
    function test_EmergencyAgent_SafeModeExtendsLifetimeForAlreadyActiveAgent() public {
        vm.startPrank(emergency);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls1 =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 41));

        vm.prank(primary);
        bytes32 operationId1 = wallet.proposeTransaction(calls1, 301);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId1);

        (, uint64 activeFrom) = wallet.agents(agentAddr);
        uint256 lifetimeBefore = wallet.emergencyAgentLifetime();
        uint256 previousExpiry = uint256(activeFrom) + lifetimeBefore;

        MERAWalletTypes.Call[] memory calls2 =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 42));

        vm.prank(primary);
        bytes32 operationId2 = wallet.proposeTransaction(calls2, 302);

        vm.prank(emergency);
        wallet.enterSafeMode(MERAWalletConstants.SAFE_MODE_MIN_DURATION);

        assertEq(wallet.emergencyAgentLifetime(), lifetimeBefore + MERAWalletConstants.SAFE_MODE_MIN_DURATION);

        // Past the pre-safe-mode expiry window, but still within extended lifetime.
        vm.warp(previousExpiry + 1);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId2);
    }

    function test_EmergencyAgent_Freeze_StartsLifetime() public {
        vm.prank(emergency);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Emergency);

        (, uint64 activeFromBefore) = wallet.agents(agentAddr);
        assertEq(activeFromBefore, 0);

        vm.prank(agentAddr);
        wallet.setFrozenPrimary(true);

        (, uint64 activeFromAfter) = wallet.agents(agentAddr);
        assertGt(activeFromAfter, 0);
    }

    function test_EmergencyAgent_SecondAction_DoesNotExtendLifetime() public {
        vm.startPrank(emergency);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls1 =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 11));

        vm.prank(primary);
        bytes32 operationId1 = wallet.proposeTransaction(calls1, 101);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId1);

        (, uint64 activeFromFirst) = wallet.agents(agentAddr);
        assertGt(activeFromFirst, 0);

        MERAWalletTypes.Call[] memory calls2 =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 12));

        vm.prank(primary);
        bytes32 operationId2 = wallet.proposeTransaction(calls2, 102);

        vm.warp(block.timestamp + 1 hours);

        vm.prank(agentAddr);
        wallet.vetoPending(operationId2);

        (, uint64 activeFromSecond) = wallet.agents(agentAddr);
        assertEq(activeFromSecond, activeFromFirst);
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

    /// @dev Primary cannot use immediate execute when non-zero role timelocks apply.
    function test_Agent_CoreRoleUnaffectedByVetoSlotOnPrimaryAddress() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 7));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.TimelockRequired.selector, 1 days));
        wallet.executeTransaction(calls, 1);
    }

    function test_Agent_WalletAddressCannotBeAppointed() public {
        (address[] memory aa, MERAWalletTypes.Role[] memory rr) =
            _mkAgents(address(wallet), MERAWalletTypes.Role.Primary);
        vm.prank(primary);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.WalletCannotBeAgent.selector),
            abi.encodeWithSelector(wallet.setAgents.selector, aa, rr),
            7510
        );
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
        _expectEmergencyWalletSelfCallTimelockedRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.NoopCheckerConfig.selector),
            abi.encodeWithSelector(wallet.setRequiredCheckers.selector, _mkReq(address(checkerNoHooks), true, "")),
            908
        );
    }

    function test_SetRequiredChecker_AppliesConfigToConfigurableChecker() public {
        bytes memory cfg = abi.encode(true, false);
        vm.startPrank(emergency);
        _setRequiredCheckers(_mkReq(address(checkerBeforeOnly), true, cfg));
        vm.stopPrank();
        assertTrue(checkerBeforeOnly.revertBefore());
        assertFalse(checkerBeforeOnly.revertAfter());
    }

    function test_SetOptionalChecker_RevertsForNoopConfigOnNonZeroChecker() public {
        _expectEmergencyWalletSelfCallTimelockedRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.NoopCheckerConfig.selector),
            abi.encodeWithSelector(wallet.setOptionalCheckers.selector, _mkWl(address(checkerNoHooks), true, "")),
            909
        );
    }

    function test_SetOptionalChecker_AppliesSlippageCheckerAssetWhitelistConfig() public {
        MERAWalletUniswapV2OracleSlippageChecker slip = new MERAWalletUniswapV2OracleSlippageChecker(
            emergency, DEFAULT_MAX_ORACLE_NEGATIVE_DEVIATION_BPS, DEFAULT_MAX_ORACLE_STALE_SECONDS, true
        );
        MERAWalletAssetWhiteList aw = new MERAWalletAssetWhiteList(emergency);
        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory cfg =
            MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig({
                assetWhitelist: address(aw),
                maxOracleNegativeDeviationBps: 0,
                maxOracleStaleSeconds: 0,
                whitelistRouter: address(0)
            });

        vm.startPrank(emergency);
        _setOptionalCheckers(_mkWl(address(slip), true, abi.encode(cfg)));
        vm.stopPrank();

        (address storedWl,,,) = slip.walletSlippageCheckerConfig(address(wallet));
        assertEq(storedWl, address(aw));
    }

    function test_SetOptionalChecker_AppliesConfigToConfigurableChecker() public {
        bytes memory cfg = abi.encode(true, false);
        vm.startPrank(emergency);
        _setOptionalCheckers(_mkWl(address(checkerBeforeOnly), true, cfg));
        vm.stopPrank();
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
        vm.startPrank(emergency);
        _setOptionalCheckers(_mkWl(address(0), false, ""));
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 456));

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.OptionalCheckerNotAllowed.selector, address(0), 0));
        wallet.executeTransaction(calls, 1);
    }

    function test_OptionalChecker_BeforeOnlyMode() public {
        vm.startPrank(emergency);
        _setOptionalCheckers(_mkWl(address(checkerBeforeOnly), true, ""));
        vm.stopPrank();

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
        vm.startPrank(emergency);
        _setOptionalCheckers(_mkWl(address(checkerAfterOnly), true, ""));
        vm.stopPrank();

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

    /// @dev Agent veto is authorized while safe mode is active.
    function test_SafeMode_AgentVetoPending_Allowed() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, MERAWalletTypes.Role.Backup);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 42));

        vm.prank(backup);
        bytes32 operationId = wallet.proposeTransaction(calls, 1);

        vm.prank(emergency);
        wallet.enterSafeMode(MERAWalletConstants.SAFE_MODE_MIN_DURATION);
        assertLt(block.timestamp, wallet.safeModeBefore());

        vm.prank(agentAddr);
        wallet.vetoPending(operationId);

        (,,,,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Vetoed));
    }

    function test_SafeMode_AgentSetFrozenPrimary_Allowed() public {
        vm.prank(backup);
        _agentsCall(wallet, agentAddr, true);

        vm.prank(emergency);
        wallet.enterSafeMode(MERAWalletConstants.SAFE_MODE_MIN_DURATION);
        assertLt(block.timestamp, wallet.safeModeBefore());

        vm.prank(agentAddr);
        wallet.setFrozenPrimary(true);
        assertTrue(wallet.frozenPrimary());
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

    /// @dev `executePending` has `whenControllerCoreAvailable`, so outsiders cannot relay-execute (`Unauthorized`).
    /// With relay policy `Anyone`, a core controller passes `_validateRelayExecutor` and receives the relay reward.
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

        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        wallet.executePending(calls, 1);

        vm.prank(primary);
        uint256 primaryBalBefore = primary.balance;
        wallet.executePending(calls, 1);

        assertEq(receiver.value(), 717);
        assertEq(address(wallet).balance, 0);
        (,,,,,,, uint256 relayReward,,,) = wallet.operations(operationId);
        assertEq(relayReward, 0);
        assertEq(primary.balance, primaryBalBefore + 1 ether);
    }

    /// @dev See {test_ProposeWithRelay_Anyone_ExternalExecutorGetsReward}: non-core callers revert at gate.
    /// `{Designated}`: a core controller who is not the designated executor hits `RelayExecutorNotAllowed`.
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
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RelayExecutorNotAllowed.selector, backup));
        wallet.executePending(calls, 1);

        vm.prank(designated);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        wallet.executePending(calls, 1);

        assertEq(receiver.value(), 0);
        assertEq(address(wallet).balance, 0.25 ether);
    }

    /// @dev Non-core callers never reach `{Whitelist}` relay checks (`Unauthorized` at entry); a core controller
    /// not in the whitelist hits `RelayExecutorNotAllowed` inside `_validateRelayExecutor`.
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
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.RelayExecutorNotAllowed.selector, backup));
        wallet.executePending(calls, 1, whitelist);

        assertEq(receiver.value(), 0);
        assertEq(address(wallet).balance, 0.4 ether);
    }

    function test_CancelPending_KeepsRelayRewardOnWallet() public {
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

        assertEq(address(wallet).balance, 0.6 ether);
        assertEq(primary.balance, 1.4 ether);
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
        _setAllRoleTimelocks(MERAWalletConstants.DEFAULT_PRIMARY_TIMELOCK);
        vm.stopPrank();

        uint64 badDeadline = uint64(block.timestamp + MERAWalletConstants.DEFAULT_PRIMARY_TIMELOCK / 2);
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

    function _mkReq(address checker, bool enabled, bytes memory config)
        internal
        pure
        returns (MERAWalletTypes.RequiredCheckerUpdate[] memory u)
    {
        u = new MERAWalletTypes.RequiredCheckerUpdate[](1);
        u[0] = MERAWalletTypes.RequiredCheckerUpdate({checker: checker, enabled: enabled, config: config});
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
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Primary, delay),
            ROLE_TIMELOCK_PRIMARY_SALT
        );
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Backup, delay),
            ROLE_TIMELOCK_BACKUP_SALT
        );
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Emergency, delay),
            ROLE_TIMELOCK_EMERGENCY_SALT
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
        _executeEmergencyWalletSelfCallTimelocked(
            abi.encodeWithSelector(wallet.setTargetCallPolicies.selector, ts, ps), 7301
        );
    }

    /// @dev Applies one selector policy via `setSelectorCallPolicies`.
    function _policySelector(bytes4 sel, MERAWalletTypes.CallPathPolicy memory pol) internal {
        bytes4[] memory ss = new bytes4[](1);
        MERAWalletTypes.CallPathPolicy[] memory ps = new MERAWalletTypes.CallPathPolicy[](1);
        ss[0] = sel;
        ps[0] = pol;
        _executeEmergencyWalletSelfCallTimelocked(
            abi.encodeWithSelector(wallet.setSelectorCallPolicies.selector, ss, ps), 7302
        );
    }

    /// @dev Applies one (target, selector) pair policy via `setTargetSelectorCallPolicies`.
    function _policyPair(address target, bytes4 sel, MERAWalletTypes.CallPathPolicy memory pol) internal {
        address[] memory ts = new address[](1);
        bytes4[] memory ss = new bytes4[](1);
        MERAWalletTypes.CallPathPolicy[] memory ps = new MERAWalletTypes.CallPathPolicy[](1);
        ts[0] = target;
        ss[0] = sel;
        ps[0] = pol;
        _executeEmergencyWalletSelfCallTimelocked(
            abi.encodeWithSelector(wallet.setTargetSelectorCallPolicies.selector, ts, ss, ps), 7303
        );
    }

    function _mkWl(address checker, bool allowed, bytes memory config)
        internal
        pure
        returns (MERAWalletTypes.OptionalCheckerUpdate[] memory u)
    {
        u = new MERAWalletTypes.OptionalCheckerUpdate[](1);
        u[0] = MERAWalletTypes.OptionalCheckerUpdate({checker: checker, allowed: allowed, config: config});
    }

    function _setRequiredCheckers(MERAWalletTypes.RequiredCheckerUpdate[] memory updates) internal {
        _executeEmergencyWalletSelfCallTimelocked(
            abi.encodeWithSelector(wallet.setRequiredCheckers.selector, updates), 7401
        );
    }

    function _setOptionalCheckers(MERAWalletTypes.OptionalCheckerUpdate[] memory updates) internal {
        _executeEmergencyWalletSelfCallTimelocked(
            abi.encodeWithSelector(wallet.setOptionalCheckers.selector, updates), 7402
        );
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

    /// @dev Self-calls whose selector is timelocked for emergency (e.g. policy / checker setters).
    /// @dev Caller must have `msg.sender == emergency` for both inner txs (e.g. wrap with `vm.startPrank(emergency)`).
    function _executeEmergencyWalletSelfCallTimelocked(bytes memory data, uint256 salt) internal {
        MERAWalletTypes.Call[] memory calls = _singleCall(address(wallet), 0, data);
        if (wallet.getRequiredDelay(calls) == 0) {
            wallet.executeTransaction(calls, salt);
            return;
        }
        bytes32 opId = wallet.proposeTransaction(calls, salt);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(opId);
        vm.warp(executeAfter);
        wallet.executePending(calls, salt);
    }

    function _executeWalletSelfCallOn(BaseMERAWallet w, bytes memory data, uint256 salt) internal {
        w.executeTransaction(_singleCall(address(w), 0, data), salt);
    }

    function _executeEmergencyWalletSelfCallTimelockedOn(BaseMERAWallet w, bytes memory data, uint256 salt) internal {
        MERAWalletTypes.Call[] memory calls = _singleCall(address(w), 0, data);
        if (w.getRequiredDelay(calls) == 0) {
            w.executeTransaction(calls, salt);
            return;
        }
        bytes32 opId = w.proposeTransaction(calls, salt);
        (,,, uint64 executeAfter,,,,,,,) = w.operations(opId);
        vm.warp(executeAfter);
        w.executePending(calls, salt);
    }

    function _expectWalletSelfCallRevert(bytes memory innerRevertData, bytes memory data, uint256 salt) internal {
        vm.expectRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.CallExecutionFailed.selector, uint256(0), innerRevertData)
        );
        _executeWalletSelfCall(data, salt);
    }

    /// @dev Like `_expectWalletSelfCallRevert` for self-calls that require the emergency selector timelock.
    function _expectEmergencyWalletSelfCallTimelockedRevert(
        bytes memory innerRevertData,
        bytes memory data,
        uint256 salt
    ) internal {
        vm.startPrank(emergency);
        MERAWalletTypes.Call[] memory calls = _singleCall(address(wallet), 0, data);
        if (wallet.getRequiredDelay(calls) == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(IBaseMERAWalletErrors.CallExecutionFailed.selector, uint256(0), innerRevertData)
            );
            wallet.executeTransaction(calls, salt);
        } else {
            bytes32 opId = wallet.proposeTransaction(calls, salt);
            (,,, uint64 executeAfter,,,,,,,) = wallet.operations(opId);
            vm.warp(executeAfter);
            vm.expectRevert(
                abi.encodeWithSelector(IBaseMERAWalletErrors.CallExecutionFailed.selector, uint256(0), innerRevertData)
            );
            wallet.executePending(calls, salt);
        }
        vm.stopPrank();
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
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setMigrationTarget(newTarget);

        vm.prank(backup);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setMigrationTarget(newTarget);
    }

    function test_SetMigrationTarget_DirectEmergencyCallRevertsNotSelf() public {
        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setMigrationTarget(address(0xCAFE));
    }

    function test_SetMigrationTarget_EmitsEvent() public {
        address newTarget = address(0xCAFE);
        vm.prank(emergency);
        vm.expectEmit(true, true, true, true);
        emit IBaseMERAWalletEvents.MigrationTargetUpdated(address(0), newTarget);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, newTarget), 29801);
        assertEq(wallet.migrationTarget(), newTarget);
    }

    function test_SetMigrationTarget_Deactivate() public {
        address newTarget = address(0xCAFE);
        vm.startPrank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, newTarget), 29802);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, address(0)), 29803);
        vm.stopPrank();
        assertEq(wallet.migrationTarget(), address(0));
    }

    function test_LoginMigrationRegistryCalls_DefaultToEmergencyOnly() public {
        MERAWalletLoginRegistry registry = new MERAWalletLoginRegistry(address(this), false);
        registry.addFactory(address(this));

        BaseMERAWallet newWallet = new BaseMERAWallet(primary, backup, emergency, address(0), address(0));
        bytes32 oldSecret = keccak256("old");
        registry.commit(registry.makeCommitment("old", address(wallet), address(this), oldSecret, 0, keccak256(""), ""));
        skip(MERAWalletLoginRegistryConstants.MIN_COMMITMENT_AGE);
        registry.registerLogin{value: registry.priceOf("old")}("old", address(wallet), oldSecret, 0, "", "");
        bytes32 newSecret = keccak256("new");
        registry.commit(
            registry.makeCommitment("new", address(newWallet), address(this), newSecret, 0, keccak256(""), "")
        );
        skip(MERAWalletLoginRegistryConstants.MIN_COMMITMENT_AGE);
        registry.registerLogin{value: registry.priceOf("new")}("new", address(newWallet), newSecret, 0, "", "");

        vm.startPrank(emergency);
        _executeEmergencyWalletSelfCallTimelockedOn(
            newWallet, abi.encodeWithSelector(newWallet.setOptionalCheckers.selector, _mkWl(address(0), true, "")), 7601
        );
        vm.stopPrank();

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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, target), 31180);

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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, target), 31290);
        wallet.enterSafeMode(MERAWalletConstants.SAFE_MODE_MIN_DURATION);
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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, target), 31490);

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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, target), 31710);

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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, target), 31860);

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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, target), 32030);

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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, target), 32200);

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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, target), 32350);

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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, target), 32510);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, address(0)), 32511);
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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, target1), 32690);

        MERAWalletTypes.Call[] memory calls1 =
            _singleCall(address(ext1), 0, abi.encodeWithSignature("transferOwnership(address)", target1));
        vm.prank(primary);
        wallet.executeMigrationTransaction(calls1, 1);
        assertEq(ext1.owner(), target1);

        vm.prank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, target2), 32790);

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
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, target), 32930);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(ext), 0, abi.encodeWithSignature("transferOwnership(address)", target));

        bytes32 expectedOpId = wallet.getOperationId(calls, 1);

        vm.prank(primary);
        vm.expectEmit(true, false, true, true);
        emit IBaseMERAWalletEvents.MigrationTransactionExecuted(expectedOpId, 1);
        wallet.executeMigrationTransaction(calls, 1);
    }

    // Coverage: _setLifeController early-return when controller already has the desired state
    function test_SetLifeControllers_NoopWhenAlreadyEnabled() public {
        assertTrue(wallet.isLifeController(emergency));
        address[] memory controllers = new address[](1);
        controllers[0] = emergency;
        vm.prank(emergency);
        wallet.setLifeControllers(controllers, true); // emergency already enabled → early return
        assertTrue(wallet.isLifeController(emergency)); // unchanged
    }

    // Coverage: constructor reverts when an essential address is zero
    function test_Constructor_ZeroPrimaryReverts() public {
        vm.expectRevert(IBaseMERAWalletErrors.InvalidAddress.selector);
        new BaseMERAWallet(address(0), backup, emergency, address(0), address(0));
    }

    // Coverage: _set1271Signer reverts when initialSigner is not address(0)/primary/backup/emergency
    function test_Constructor_InvalidSignerReverts() public {
        address badSigner = address(0xBAD5163);
        vm.expectRevert(IBaseMERAWalletErrors.InvalidSigner.selector);
        new BaseMERAWallet(primary, backup, emergency, badSigner, address(0));
    }

    // Coverage: setPrimary(address(0)) reverts
    function test_SetPrimary_ZeroAddressReverts() public {
        vm.prank(primary);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.InvalidAddress.selector),
            abi.encodeWithSelector(wallet.setPrimary.selector, address(0)),
            10100
        );
    }

    // Coverage: eip1271Signer==previousPrimary → signer auto-updated on setPrimary
    function test_SetPrimary_Updates1271SignerWhenSet() public {
        vm.prank(primary);
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.set1271Signer.selector, MERAWalletTypes.Role.Primary), 10101
        );
        assertEq(wallet.eip1271Signer(), primary);
        address newPrimary = address(0x110001);
        vm.prank(primary);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setPrimary.selector, newPrimary), 10102);
        assertEq(wallet.eip1271Signer(), newPrimary);
    }

    // Coverage: setBackup(address(0)) reverts
    function test_SetBackup_ZeroAddressReverts() public {
        vm.prank(backup);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.InvalidAddress.selector),
            abi.encodeWithSelector(wallet.setBackup.selector, address(0)),
            10103
        );
    }

    // Coverage: eip1271Signer==previousBackup → signer auto-updated on setBackup
    function test_SetBackup_Updates1271SignerWhenSet() public {
        vm.prank(backup);
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.set1271Signer.selector, MERAWalletTypes.Role.Backup), 10104
        );
        assertEq(wallet.eip1271Signer(), backup);
        address newBackup = address(0x120001);
        vm.prank(backup);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setBackup.selector, newBackup), 10105);
        assertEq(wallet.eip1271Signer(), newBackup);
    }

    // Coverage: setEmergency(address(0)) reverts
    function test_SetEmergency_ZeroAddressReverts() public {
        vm.prank(emergency);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.InvalidAddress.selector),
            abi.encodeWithSelector(wallet.setEmergency.selector, address(0)),
            10106
        );
    }

    // Coverage: eip1271Signer==previousEmergency → signer auto-updated on setEmergency
    function test_SetEmergency_Updates1271SignerWhenSet() public {
        vm.startPrank(emergency);
        _executeEmergencyWalletSelfCallTimelocked(
            abi.encodeWithSelector(wallet.set1271Signer.selector, MERAWalletTypes.Role.Emergency), 10107
        );
        assertEq(wallet.eip1271Signer(), emergency);
        address newEmergency = address(0x130001);
        _executeEmergencyWalletSelfCallTimelocked(
            abi.encodeWithSelector(wallet.setEmergency.selector, newEmergency), 10108
        );
        vm.stopPrank();
        assertEq(wallet.eip1271Signer(), newEmergency);
    }

    // Coverage: setRoleTimelock(Role.None, ...) reverts
    function test_SetRoleTimelock_NoneRoleReverts() public {
        vm.prank(emergency);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.InvalidRole.selector),
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.None, uint256(1 hours)),
            10109
        );
    }

    // Coverage: setLifeControl from non-emergency reverts
    function test_SetLifeControl_NotEmergencyReverts() public {
        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.NotEmergency.selector);
        wallet.setLifeControl(true, 1 hours);
    }

    // Coverage: setLifeControllers from non-emergency reverts
    function test_SetLifeControllers_NotEmergencyReverts() public {
        address[] memory controllers = new address[](1);
        controllers[0] = outsider;
        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.NotEmergency.selector);
        wallet.setLifeControllers(controllers, true);
    }

    // Coverage: setLifeControllers with zero controller reverts
    function test_SetLifeControllers_ZeroControllerReverts() public {
        address[] memory controllers = new address[](1);
        controllers[0] = address(0);
        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.InvalidAddress.selector);
        wallet.setLifeControllers(controllers, true);
    }

    // Coverage: setLifeControllers with enabled=false and controller==emergency reverts
    function test_SetLifeControllers_DisableEmergencyReverts() public {
        address[] memory controllers = new address[](1);
        controllers[0] = emergency;
        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.EmergencyMustStayLifeController.selector);
        wallet.setLifeControllers(controllers, false);
    }

    // Coverage: branch: setLifeControllers with enabled=false on a non-emergency controller (success)
    function test_SetLifeControllers_DisableNonEmergencyController() public {
        address controller = address(0x1337);
        address[] memory enableList = new address[](1);
        enableList[0] = controller;
        vm.prank(emergency);
        wallet.setLifeControllers(enableList, true);
        assertTrue(wallet.isLifeController(controller));
        vm.prank(emergency);
        wallet.setLifeControllers(enableList, false);
        assertFalse(wallet.isLifeController(controller));
    }

    // Coverage: confirmAlive from non-life-controller reverts
    function test_ConfirmAlive_NotLifeControllerReverts() public {
        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.NotLifeController.selector);
        wallet.confirmAlive();
    }

    // Coverage: setTargetCallPolicies with mismatched array lengths reverts
    // Note: setTargetCallPolicies forbids primary/backup by default, must use emergency.
    function test_SetTargetCallPolicies_LengthMismatchReverts() public {
        address[] memory targets = new address[](2);
        targets[0] = address(receiver);
        targets[1] = address(0xDEAD);
        MERAWalletTypes.CallPathPolicy[] memory policies = new MERAWalletTypes.CallPathPolicy[](1);
        policies[0] = MERAWalletTypes.CallPathPolicy({
            primary: MERAWalletTypes.RoleCallPolicy({delay: 0, forbidden: false}),
            backup: MERAWalletTypes.RoleCallPolicy({delay: 0, forbidden: false}),
            emergencyDelay: 0,
            exists: true
        });
        vm.startPrank(emergency);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.ArrayLengthMismatch.selector, 2, 1),
            abi.encodeWithSelector(wallet.setTargetCallPolicies.selector, targets, policies),
            10120
        );
        vm.stopPrank();
    }

    // Coverage: setSelectorCallPolicies with mismatched lengths reverts
    function test_SetSelectorCallPolicies_LengthMismatchReverts() public {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(0x12345678);
        selectors[1] = bytes4(0x87654321);
        MERAWalletTypes.CallPathPolicy[] memory policies = new MERAWalletTypes.CallPathPolicy[](1);
        policies[0] = MERAWalletTypes.CallPathPolicy({
            primary: MERAWalletTypes.RoleCallPolicy({delay: 0, forbidden: false}),
            backup: MERAWalletTypes.RoleCallPolicy({delay: 0, forbidden: false}),
            emergencyDelay: 0,
            exists: true
        });
        vm.startPrank(emergency);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.ArrayLengthMismatch.selector, 2, 1),
            abi.encodeWithSelector(wallet.setSelectorCallPolicies.selector, selectors, policies),
            10121
        );
        vm.stopPrank();
    }

    // Coverage: setTargetSelectorCallPolicies with mismatched lengths reverts
    function test_SetTargetSelectorCallPolicies_LengthMismatchReverts() public {
        address[] memory targets = new address[](2);
        targets[0] = address(receiver);
        targets[1] = address(0xDEAD);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(0x12345678);
        MERAWalletTypes.CallPathPolicy[] memory policies = new MERAWalletTypes.CallPathPolicy[](1);
        policies[0] = MERAWalletTypes.CallPathPolicy({
            primary: MERAWalletTypes.RoleCallPolicy({delay: 0, forbidden: false}),
            backup: MERAWalletTypes.RoleCallPolicy({delay: 0, forbidden: false}),
            emergencyDelay: 0,
            exists: true
        });
        vm.startPrank(emergency);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.ArrayLengthMismatch.selector, 2, 1),
            abi.encodeWithSelector(wallet.setTargetSelectorCallPolicies.selector, targets, selectors, policies),
            10122
        );
        vm.stopPrank();
    }

    // Coverage: setAgents with mismatched array lengths reverts
    function test_SetAgents_LengthMismatchReverts() public {
        address[] memory agentAddresses = new address[](2);
        agentAddresses[0] = address(0xA1);
        agentAddresses[1] = address(0xA2);
        MERAWalletTypes.Role[] memory roleLevels = new MERAWalletTypes.Role[](1);
        roleLevels[0] = MERAWalletTypes.Role.Primary;
        vm.prank(primary);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.ArrayLengthMismatch.selector, 2, 1),
            abi.encodeWithSelector(wallet.setAgents.selector, agentAddresses, roleLevels),
            10123
        );
    }

    // Coverage: enterSafeMode reverts when safe mode already active (SafeModeAlreadyUsed)
    function test_EnterSafeMode_AlreadyActivReverts() public {
        uint256 duration = MERAWalletConstants.SAFE_MODE_MIN_DURATION;
        vm.prank(emergency);
        wallet.enterSafeMode(duration);
        vm.prank(emergency);
        vm.expectRevert(IBaseMERAWalletErrors.SafeModeAlreadyUsed.selector);
        wallet.enterSafeMode(duration);
    }

    // Coverage: resetSafeMode reverts when safeModeUsed=false
    function test_ResetSafeMode_NotUsedReverts() public {
        vm.prank(emergency);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.SafeModeNotUsed.selector),
            abi.encodeWithSelector(wallet.resetSafeMode.selector),
            10124
        );
    }

    // Coverage: resetSafeMode's SafeModeStillActive check is structurally unreachable —
    // _onlySelfAsEmergency calls _requireNotSafeMode() which guards the same condition first.
    function test_ResetSafeMode_AfterSafeModeExpiresSucceeds() public {
        vm.prank(emergency);
        wallet.enterSafeMode(MERAWalletConstants.SAFE_MODE_MIN_DURATION);
        uint256 safeModeBefore = wallet.safeModeBefore();
        vm.warp(safeModeBefore + 1);

        vm.prank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.resetSafeMode.selector), 10125);

        assertFalse(wallet.safeModeUsed());
        assertEq(wallet.safeModeBefore(), 0);
    }

    // Coverage: executeMigrationTransaction from non-core-controller reverts
    function test_ExecuteMigration_NonCoreControllerReverts() public {
        vm.prank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, address(receiver)), 10126);
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 99));
        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.Unauthorized.selector);
        wallet.executeMigrationTransaction(calls, 10127);
    }

    // Coverage: executeMigrationTransaction rejects calls outside the migration allowlist.
    function test_ExecuteMigration_InvalidCallReverts() public {
        vm.prank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, address(receiver)), 10128);
        MERAWalletTypes.Call[] memory calls = _singleCall(address(0), 1, "");
        vm.deal(address(wallet), 1);
        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.MigrationCallNotAllowed.selector, uint256(0)));
        wallet.executeMigrationTransaction(calls, 10129);
    }

    function test_ExecuteMigration_AllowedCallFailureRevertsWithCallExecutionFailed() public {
        RevertingOwnableMock ext = new RevertingOwnableMock();
        address target = address(0xB0D418);

        vm.prank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, target), 101_418);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(ext), 0, abi.encodeWithSignature("transferOwnership(address)", target));

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.CallExecutionFailed.selector,
                0,
                abi.encodeWithSelector(RevertingOwnableMock.TransferOwnershipFailed.selector)
            )
        );
        wallet.executeMigrationTransaction(calls, 101_419);
    }

    // Coverage: vetoPending on non-pending operation reverts
    function test_VetoPending_NotPendingReverts() public {
        bytes32 fakeId = keccak256("nonexistent");
        vm.prank(emergency);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.OperationNotPending.selector, fakeId));
        wallet.vetoPending(fakeId);
    }

    // Coverage: clearVeto on non-vetoed operation reverts
    function test_ClearVeto_NotVetoedReverts() public {
        bytes32 fakeId = keccak256("nonexistent");
        vm.prank(emergency);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.OperationNotVetoed.selector, fakeId));
        wallet.clearVeto(fakeId);
    }

    // Coverage: executeMigrationTransaction with empty calls reverts
    function test_ExecuteMigration_EmptyCallsReverts() public {
        vm.prank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, address(receiver)), 10130);
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](0);
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.EmptyCalls.selector);
        wallet.executeMigrationTransaction(calls, 10131);
    }

    // Coverage: validateCalls with empty calls in executeTransaction reverts
    function test_ExecuteTransaction_EmptyCallsReverts() public {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](0);
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.EmptyCalls.selector);
        wallet.executeTransaction(calls, 10132);
    }

    // Coverage: _setFrozenRole with invalid role is structurally unreachable via the external API.
    // setFrozenPrimary/setFrozenBackup hardcode Primary/Backup respectively, so InvalidRole cannot trigger.

    // Coverage: setFrozenBackup noop when already at same value (no state change → no emit)
    function test_SetFrozenBackup_NoopWhenAlreadySameFrozen() public {
        assertFalse(wallet.frozenBackup());
        // Freeze backup first
        vm.prank(emergency);
        wallet.setFrozenBackup(true);
        assertTrue(wallet.frozenBackup());
        // Set again to the same value — hits line 1387 early return
        vm.prank(emergency);
        wallet.setFrozenBackup(true);
        assertTrue(wallet.frozenBackup());
    }

    // Coverage: set1271Signer when current signer is already set (current != address(0))
    function test_Set1271Signer_WithExistingSigner_AllowsHigherRank() public {
        // Set backup as signer (lower rank)
        vm.prank(backup);
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.set1271Signer.selector, MERAWalletTypes.Role.Backup), 10140
        );
        assertEq(wallet.eip1271Signer(), backup);
        // Emergency (higher rank) overrides — covers line 528 true path
        vm.startPrank(emergency);
        _executeEmergencyWalletSelfCallTimelocked(
            abi.encodeWithSelector(wallet.set1271Signer.selector, MERAWalletTypes.Role.Emergency), 10141
        );
        vm.stopPrank();
        assertEq(wallet.eip1271Signer(), emergency);
    }

    // Coverage: set1271Signer with Role.None and Role.Primary
    function test_Set1271Signer_NoneAndPrimaryPaths() public {
        // Role.Primary path (line 536)
        vm.prank(primary);
        _executeWalletSelfCall(
            abi.encodeWithSelector(wallet.set1271Signer.selector, MERAWalletTypes.Role.Primary), 10142
        );
        assertEq(wallet.eip1271Signer(), primary);
        // Role.None path (line 534) - clears it
        vm.prank(primary);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.set1271Signer.selector, MERAWalletTypes.Role.None), 10143);
        assertEq(wallet.eip1271Signer(), address(0));
    }

    // Coverage: (Role.Emergency = else branch)
    function test_Set1271Signer_EmergencyPath() public {
        vm.startPrank(emergency);
        _executeEmergencyWalletSelfCallTimelocked(
            abi.encodeWithSelector(wallet.set1271Signer.selector, MERAWalletTypes.Role.Emergency), 10144
        );
        vm.stopPrank();
        assertEq(wallet.eip1271Signer(), emergency);
    }

    // Coverage: isValidSignature when recovered == address(0) (invalid/malformed sig)
    function test_IsValidSignature_InvalidSigReturnsInvalid() public view {
        bytes32 hash = keccak256("test");
        bytes memory badSig = abi.encodePacked(bytes32(0), bytes32(0), uint8(0));
        bytes4 result = wallet.isValidSignature(hash, badSig);
        assertEq(uint32(result), uint32(0xffffffff));
    }

    // Coverage: _extractSelectorFromCalldataBytes with data < 4 bytes returns bytes4(0)
    // Covered indirectly by isValidSignature call with short selector data, but let's cover via proposeTransaction
    // with a call whose data is 0 bytes (will be validateCheckerWhitelist → selector == bytes4(0))
    function test_ProposeTransaction_ZeroByteDataAllowed() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();
        // Call with empty data (0 bytes) — _extractSelectorFromCalldataBytes returns bytes4(0)
        MERAWalletTypes.Call[] memory calls = _singleCall(address(receiver), 0, "");
        vm.prank(primary);
        wallet.proposeTransaction(calls, 10145);
    }

    // Coverage: _recoverSigner with malformed sig → ECDSA error → returns address(0)
    // already covered by test_IsValidSignature_InvalidSigReturnsInvalid above (same code path via isValidSignature)

    // Coverage: relay config Anyone with non-zero designatedExecutor reverts
    function test_ProposeWithRelay_AnyoneWithDesignatedExecutorReverts() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));
        MERAWalletTypes.RelayProposeConfig memory cfg = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Anyone,
            address(0xD), // non-zero → invalid for Anyone
            bytes32(0),
            uint64(block.timestamp + 8 days)
        );
        vm.deal(primary, 1 ether);
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.InvalidRelayConfig.selector);
        wallet.proposeTransactionWithRelay{value: 1 ether}(calls, 10150, cfg);
    }

    // Coverage: relay config Designated with zero designatedExecutor reverts
    function test_ProposeWithRelay_DesignatedWithZeroExecutorReverts() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 2));
        MERAWalletTypes.RelayProposeConfig memory cfg = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Designated,
            address(0), // zero → invalid for Designated
            bytes32(0),
            uint64(block.timestamp + 8 days)
        );
        vm.deal(primary, 1 ether);
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.InvalidRelayConfig.selector);
        wallet.proposeTransactionWithRelay{value: 1 ether}(calls, 10151, cfg);
    }

    // Coverage: setTargetSelectorCallPolicies where targets.length==selectors.length but !=policies.length
    function test_SetTargetSelectorCallPolicies_PoliciesLengthMismatchReverts() public {
        address[] memory targets = new address[](1);
        targets[0] = address(receiver);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(0x11223344);
        MERAWalletTypes.CallPathPolicy[] memory policies = new MERAWalletTypes.CallPathPolicy[](2);
        policies[0] = MERAWalletTypes.CallPathPolicy({
            primary: MERAWalletTypes.RoleCallPolicy({delay: 0, forbidden: false}),
            backup: MERAWalletTypes.RoleCallPolicy({delay: 0, forbidden: false}),
            emergencyDelay: 0,
            exists: true
        });
        policies[1] = policies[0];
        vm.startPrank(emergency);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.ArrayLengthMismatch.selector, 1, 2),
            abi.encodeWithSelector(wallet.setTargetSelectorCallPolicies.selector, targets, selectors, policies),
            10200
        );
        vm.stopPrank();
    }

    // Coverage: enterSafeMode from outsider (not emergency/guardian/emergency-agent) reverts
    function test_EnterSafeMode_OutsiderReverts() public {
        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.SafeModeNotAuthorized.selector);
        wallet.enterSafeMode(MERAWalletConstants.SAFE_MODE_MIN_DURATION);
    }

    // Coverage: enterSafeMode with duration below minimum reverts
    function test_EnterSafeMode_DurationOutOfRangeReverts() public {
        vm.prank(emergency);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.SafeModeDurationOutOfRange.selector,
                MERAWalletConstants.SAFE_MODE_MIN_DURATION - 1
            )
        );
        wallet.enterSafeMode(MERAWalletConstants.SAFE_MODE_MIN_DURATION - 1);
    }

    // Coverage: executeMigrationTransaction rejects unknown selectors.
    function test_ExecuteMigration_UnknownSelectorReverts() public {
        vm.prank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setMigrationTarget.selector, address(receiver)), 10210);
        MERAWalletTypes.Call[] memory calls = _singleCall(address(receiver), 0, hex"deadbeef00");
        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.MigrationCallNotAllowed.selector, uint256(0)));
        wallet.executeMigrationTransaction(calls, 10211);
    }

    // Coverage: cancelPending with non-existent operation (status == None, not Pending/Vetoed)
    function test_CancelPending_NonExistentOperationReverts() public {
        bytes32 fakeId = keccak256("non-existent-cancel");
        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.OperationNotPending.selector, fakeId));
        wallet.cancelPending(fakeId);
    }

    // Coverage: set1271Signer when current signer is higher-rank than caller → Set1271SignerNotAuthorized
    function test_Set1271Signer_LowerRankCallerCannotOverrideHigherRank() public {
        // First set emergency as the eip1271Signer (high rank)
        vm.startPrank(emergency);
        _executeEmergencyWalletSelfCallTimelocked(
            abi.encodeWithSelector(wallet.set1271Signer.selector, MERAWalletTypes.Role.Emergency), 10220
        );
        vm.stopPrank();
        assertEq(wallet.eip1271Signer(), emergency);

        // Now primary (lower rank) tries to override → Set1271SignerNotAuthorized
        vm.prank(primary);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.Set1271SignerNotAuthorized.selector,
                MERAWalletTypes.Role.Primary,
                MERAWalletTypes.Role.Emergency
            ),
            abi.encodeWithSelector(wallet.set1271Signer.selector, MERAWalletTypes.Role.Primary),
            10221
        );
    }

    // Coverage: setRequiredCheckers with checker=address(0) reverts
    function test_SetRequiredCheckers_ZeroCheckerReverts() public {
        MERAWalletTypes.RequiredCheckerUpdate[] memory updates = new MERAWalletTypes.RequiredCheckerUpdate[](1);
        updates[0] = MERAWalletTypes.RequiredCheckerUpdate({checker: address(0), enabled: true, config: ""});
        vm.startPrank(emergency);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.InvalidCheckerAddress.selector),
            abi.encodeWithSelector(wallet.setRequiredCheckers.selector, updates),
            10230
        );
        vm.stopPrank();
    }

    function test_SetRequiredCheckers_DisableUnconfiguredCheckerReverts() public {
        MERAWalletTypes.RequiredCheckerUpdate[] memory updates = new MERAWalletTypes.RequiredCheckerUpdate[](1);
        updates[0] =
            MERAWalletTypes.RequiredCheckerUpdate({checker: address(checkerBeforeOnly), enabled: false, config: ""});

        vm.startPrank(emergency);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.NoopCheckerConfig.selector),
            abi.encodeWithSelector(wallet.setRequiredCheckers.selector, updates),
            10229
        );
        vm.stopPrank();
    }

    // Coverage: setRequiredCheckers disabling an already-configured checker
    function test_SetRequiredCheckers_DisableConfiguredChecker() public {
        // Enable checkerBothHooks as a required checker first
        MERAWalletTypes.RequiredCheckerUpdate[] memory enableUpdates = new MERAWalletTypes.RequiredCheckerUpdate[](1);
        enableUpdates[0] =
            MERAWalletTypes.RequiredCheckerUpdate({checker: address(checkerBothHooks), enabled: true, config: ""});
        vm.startPrank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setRequiredCheckers.selector, enableUpdates), 10231);

        // Now disable it — covers line 662 (!enabled) path
        MERAWalletTypes.RequiredCheckerUpdate[] memory disableUpdates = new MERAWalletTypes.RequiredCheckerUpdate[](1);
        disableUpdates[0] =
            MERAWalletTypes.RequiredCheckerUpdate({checker: address(checkerBothHooks), enabled: false, config: ""});
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setRequiredCheckers.selector, disableUpdates), 10232);
        vm.stopPrank();
    }

    function test_SetRequiredCheckers_DisableBeforeOnlyCheckerHitsMissingAfterListEarlyReturn() public {
        MERAWalletTypes.RequiredCheckerUpdate[] memory enableUpdates = new MERAWalletTypes.RequiredCheckerUpdate[](1);
        enableUpdates[0] =
            MERAWalletTypes.RequiredCheckerUpdate({checker: address(checkerBeforeOnly), enabled: true, config: ""});
        MERAWalletTypes.RequiredCheckerUpdate[] memory disableUpdates = new MERAWalletTypes.RequiredCheckerUpdate[](1);
        disableUpdates[0] =
            MERAWalletTypes.RequiredCheckerUpdate({checker: address(checkerBeforeOnly), enabled: false, config: ""});

        vm.startPrank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setRequiredCheckers.selector, enableUpdates), 10233);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setRequiredCheckers.selector, disableUpdates), 10234);
        vm.stopPrank();
    }

    function test_SetRequiredCheckers_RemoveFirstCheckerSwapsLastCheckerIntoSlot() public {
        ConfigurableTransactionChecker extraBeforeOnly =
            new ConfigurableTransactionChecker(true, false, address(wallet));
        MERAWalletTypes.RequiredCheckerUpdate[] memory updates = new MERAWalletTypes.RequiredCheckerUpdate[](2);
        updates[0] =
            MERAWalletTypes.RequiredCheckerUpdate({checker: address(checkerBeforeOnly), enabled: true, config: ""});
        updates[1] =
            MERAWalletTypes.RequiredCheckerUpdate({checker: address(extraBeforeOnly), enabled: true, config: ""});
        MERAWalletTypes.RequiredCheckerUpdate[] memory disableUpdates = new MERAWalletTypes.RequiredCheckerUpdate[](1);
        disableUpdates[0] =
            MERAWalletTypes.RequiredCheckerUpdate({checker: address(checkerBeforeOnly), enabled: false, config: ""});

        vm.startPrank(emergency);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setRequiredCheckers.selector, updates), 10235);
        _executeWalletSelfCall(abi.encodeWithSelector(wallet.setRequiredCheckers.selector, disableUpdates), 10236);
        vm.stopPrank();

        (address[] memory beforeCheckers,) = wallet.getRequiredCheckers();
        assertEq(beforeCheckers.length, 1);
        assertEq(beforeCheckers[0], address(extraBeforeOnly));
    }

    function test_SetRequiredCheckers_RemoveMissingAfterCheckerReturnsThroughHarness() public {
        BaseMERAWalletHarness h = new BaseMERAWalletHarness(primary, backup, emergency, address(0), address(0));

        h.exposedRemoveMissingAfterChecker(address(checkerBeforeOnly));
    }

    function test_SetAgents_WithoutEffectiveCoreRoleRevertsAtInternalGuard() public {
        BaseMERAWalletHarness h = new BaseMERAWalletHarness(primary, backup, emergency, address(0), address(0));

        vm.expectRevert(IBaseMERAWalletErrors.NotCoreController.selector);
        h.exposedSetAgent(agentAddr, MERAWalletTypes.Role.Primary);
    }

    // Coverage: setAgents with agent=address(0) reverts
    function test_SetAgents_ZeroAgentReverts() public {
        address[] memory agents_ = new address[](1);
        agents_[0] = address(0);
        MERAWalletTypes.Role[] memory roles = new MERAWalletTypes.Role[](1);
        roles[0] = MERAWalletTypes.Role.Primary;
        vm.prank(primary);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.InvalidAddress.selector),
            abi.encodeWithSelector(wallet.setAgents.selector, agents_, roles),
            10240
        );
    }

    // Coverage: setAgents where roleLevel exceeds callerCore rank → AgentRemovalNotAuthorized
    function test_SetAgents_RoleTooHighReverts() public {
        address[] memory agents_ = new address[](1);
        agents_[0] = agentAddr;
        MERAWalletTypes.Role[] memory roles = new MERAWalletTypes.Role[](1);
        roles[0] = MERAWalletTypes.Role.Emergency; // Primary cannot grant Emergency-level agent
        vm.prank(primary);
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.AgentRemovalNotAuthorized.selector),
            abi.encodeWithSelector(wallet.setAgents.selector, agents_, roles),
            10241
        );
    }

    // Coverage: proposeTransaction with zero required delay reverts (timelocks=0 in setUp)
    function test_ProposeTransaction_ZeroDelayReverts() public {
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.ZeroDelayNotProposable.selector);
        wallet.proposeTransaction(calls, 10245);
    }

    // Coverage: executePending with CoreExecute policy and non-empty executor whitelist reverts
    function test_ExecutePending_CoreExecuteWithNonEmptyWhitelistReverts() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 8));
        MERAWalletTypes.RelayProposeConfig memory cfg = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.CoreExecute, address(0), bytes32(0), uint64(block.timestamp + 8 days)
        );
        vm.prank(primary);
        wallet.proposeTransactionWithRelay(calls, 10246, cfg);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(wallet.getOperationId(calls, 10246));
        vm.warp(executeAfter);

        address[] memory nonEmptyList = new address[](1);
        nonEmptyList[0] = primary;
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.InvalidExecutorWhitelist.selector);
        wallet.executePending(calls, 10246, nonEmptyList);
    }

    // Coverage: TooManyRequiredCheckers — add MAX_REQUIRED_CHECKERS_PER_LIST+1 checkers
    function test_SetRequiredCheckers_TooManyReverts() public {
        uint256 maxCheckers = MERAWalletConstants.MAX_REQUIRED_CHECKERS_PER_LIST;
        // Add maxCheckers checkers (each needs a unique address)
        vm.startPrank(emergency);
        for (uint256 i = 0; i < maxCheckers; i++) {
            ConfigurableTransactionChecker c = new ConfigurableTransactionChecker(true, false, address(wallet));
            MERAWalletTypes.RequiredCheckerUpdate[] memory updates = new MERAWalletTypes.RequiredCheckerUpdate[](1);
            updates[0] = MERAWalletTypes.RequiredCheckerUpdate({checker: address(c), enabled: true, config: ""});
            _executeWalletSelfCall(abi.encodeWithSelector(wallet.setRequiredCheckers.selector, updates), 10250 + i);
        }
        // Now adding one more should revert
        ConfigurableTransactionChecker extra = new ConfigurableTransactionChecker(true, false, address(wallet));
        MERAWalletTypes.RequiredCheckerUpdate[] memory lastUpdate = new MERAWalletTypes.RequiredCheckerUpdate[](1);
        lastUpdate[0] = MERAWalletTypes.RequiredCheckerUpdate({checker: address(extra), enabled: true, config: ""});
        _expectWalletSelfCallRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.TooManyRequiredCheckers.selector, maxCheckers + 1, maxCheckers
            ),
            abi.encodeWithSelector(wallet.setRequiredCheckers.selector, lastUpdate),
            10258
        );
        vm.stopPrank();
    }

    // Coverage: SafeModeActive in _requireNotSafeMode — called via executeTransaction during active safe mode
    function test_ExecuteTransaction_DuringSafeModeReverts() public {
        uint256 dur = MERAWalletConstants.SAFE_MODE_MIN_DURATION;
        vm.prank(emergency);
        wallet.enterSafeMode(dur);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 1));
        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.SafeModeActive.selector, wallet.safeModeBefore()));
        wallet.executeTransaction(calls, 10260);
    }

    function test_ExecuteTransaction_AfterSafeModeDeadlinePasses() public {
        vm.prank(emergency);
        wallet.enterSafeMode(MERAWalletConstants.SAFE_MODE_MIN_DURATION);
        vm.warp(wallet.safeModeBefore() + 1);

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 60));
        vm.prank(primary);
        wallet.executeTransaction(calls, 10261);

        assertEq(receiver.value(), 60);
    }

    function test_SetFrozenRole_InvalidRoleRevertsThroughHarness() public {
        BaseMERAWalletHarness h = new BaseMERAWalletHarness(primary, backup, emergency, address(0), address(0));

        vm.expectRevert(IBaseMERAWalletErrors.InvalidRole.selector);
        h.exposedSetFrozenRole(MERAWalletTypes.Role.None, true);
    }

    // Coverage: executePending with Anyone policy + non-empty whitelist → InvalidExecutorWhitelist
    function test_ExecutePending_AnyoneWithNonEmptyWhitelistReverts() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 42));
        MERAWalletTypes.RelayProposeConfig memory cfg = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Anyone, address(0), bytes32(0), uint64(block.timestamp + 8 days)
        );
        vm.deal(primary, 1 ether);
        vm.prank(primary);
        wallet.proposeTransactionWithRelay{value: 1 ether}(calls, 10270, cfg);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(wallet.getOperationId(calls, 10270));
        vm.warp(executeAfter);

        address[] memory nonEmpty = new address[](1);
        nonEmpty[0] = primary;
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.InvalidExecutorWhitelist.selector);
        wallet.executePending(calls, 10270, nonEmpty);
    }

    // Coverage: executePending with Designated policy + non-empty whitelist → InvalidExecutorWhitelist
    function test_ExecutePending_DesignatedWithNonEmptyWhitelistReverts() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 43));
        MERAWalletTypes.RelayProposeConfig memory cfg = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Designated, primary, bytes32(0), uint64(block.timestamp + 8 days)
        );
        vm.deal(primary, 1 ether);
        vm.prank(primary);
        wallet.proposeTransactionWithRelay{value: 1 ether}(calls, 10271, cfg);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(wallet.getOperationId(calls, 10271));
        vm.warp(executeAfter);

        address[] memory nonEmpty = new address[](1);
        nonEmpty[0] = primary;
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.InvalidExecutorWhitelist.selector);
        wallet.executePending(calls, 10271, nonEmpty);
    }

    // Coverage: branch 1: Designated executor (a core controller) successfully executes
    function test_ExecutePending_DesignatedExecutorSucceeds() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 44));
        MERAWalletTypes.RelayProposeConfig memory cfg = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Designated, primary, bytes32(0), uint64(block.timestamp + 8 days)
        );
        vm.prank(primary);
        wallet.proposeTransactionWithRelay(calls, 10272, cfg);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(wallet.getOperationId(calls, 10272));
        vm.warp(executeAfter);

        vm.prank(primary);
        wallet.executePending(calls, 10272);
        assertEq(receiver.value(), 44);
    }

    // Coverage: Whitelist policy with wrong hash → InvalidExecutorWhitelist
    function test_ExecutePending_WhitelistWrongHashReverts() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        address[] memory whitelist = new address[](1);
        whitelist[0] = primary;
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 45));
        MERAWalletTypes.RelayProposeConfig memory cfg = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Whitelist,
            address(0),
            keccak256(abi.encode(whitelist)),
            uint64(block.timestamp + 8 days)
        );
        vm.deal(primary, 1 ether);
        vm.prank(primary);
        wallet.proposeTransactionWithRelay{value: 1 ether}(calls, 10273, cfg);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(wallet.getOperationId(calls, 10273));
        vm.warp(executeAfter);

        address[] memory wrongList = new address[](1);
        wrongList[0] = backup; // Different from stored hash
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.InvalidExecutorWhitelist.selector);
        wallet.executePending(calls, 10273, wrongList);
    }

    // Coverage: Whitelist executor found → successful execution
    function test_ExecutePending_WhitelistExecutorFoundSucceeds() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();

        address[] memory whitelist = new address[](1);
        whitelist[0] = primary;
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 46));
        MERAWalletTypes.RelayProposeConfig memory cfg = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Whitelist,
            address(0),
            keccak256(abi.encode(whitelist)),
            uint64(block.timestamp + 8 days)
        );
        vm.deal(primary, 1 ether);
        vm.prank(primary);
        wallet.proposeTransactionWithRelay{value: 1 ether}(calls, 10274, cfg);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(wallet.getOperationId(calls, 10274));
        vm.warp(executeAfter);

        vm.prank(primary);
        wallet.executePending(calls, 10274, whitelist);
        assertEq(receiver.value(), 46);
    }

    // Coverage: relay config Whitelist with zero executorSetHash reverts
    function test_ProposeWithRelay_WhitelistWithZeroExecutorSetHashReverts() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 3));
        MERAWalletTypes.RelayProposeConfig memory cfg = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Whitelist,
            address(0),
            bytes32(0), // zero hash → invalid for Whitelist
            uint64(block.timestamp + 8 days)
        );
        vm.deal(primary, 1 ether);
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.InvalidRelayConfig.selector);
        wallet.proposeTransactionWithRelay{value: 1 ether}(calls, 10152, cfg);
    }

    function test_ProposeWithRelay_CoreExecuteRewardReverts() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 4));
        MERAWalletTypes.RelayProposeConfig memory cfg = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.CoreExecute, address(0), bytes32(0), uint64(block.timestamp + 8 days)
        );
        vm.deal(primary, 1 ether);
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.RelayRewardNotAllowed.selector);
        wallet.proposeTransactionWithRelay{value: 1 ether}(calls, 10153, cfg);
    }

    function test_ProposeWithRelay_CoreExecuteDesignatedExecutorReverts() public {
        vm.startPrank(emergency);
        _setAllRoleTimelocks(1 days);
        vm.stopPrank();
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 5));
        MERAWalletTypes.RelayProposeConfig memory cfg = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.CoreExecute,
            address(0xC0DE),
            bytes32(0),
            uint64(block.timestamp + 8 days)
        );
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.InvalidRelayConfig.selector);
        wallet.proposeTransactionWithRelay(calls, 10154, cfg);
    }

    function test_ExecutePending_RelayRewardTransferFailureReverts() public {
        RejectingRelayExecutor rejectingPrimary = new RejectingRelayExecutor();
        BaseMERAWallet w = new BaseMERAWallet(address(rejectingPrimary), backup, emergency, address(0), address(0));
        ReceiverMock r = new ReceiverMock();

        vm.startPrank(emergency);
        _setAllRoleTimelocksOn(w, 1 days);
        _executeEmergencyWalletSelfCallTimelockedOn(
            w, abi.encodeWithSelector(w.setOptionalCheckers.selector, _mkWl(address(0), true, "")), 10156
        );
        vm.stopPrank();

        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(r), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 6));
        MERAWalletTypes.RelayProposeConfig memory cfg = _relayConfig(
            MERAWalletTypes.RelayExecutorPolicy.Anyone, address(0), bytes32(0), uint64(block.timestamp + 8 days)
        );

        vm.deal(address(rejectingPrimary), 1 ether);
        vm.prank(address(rejectingPrimary));
        bytes32 operationId = w.proposeTransactionWithRelay{value: 1 ether}(calls, 10155, cfg);
        (,,, uint64 executeAfter,,,,,,,) = w.operations(operationId);
        vm.warp(executeAfter);

        vm.prank(address(rejectingPrimary));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.RelayRewardTransferFailed.selector, address(rejectingPrimary), 1 ether
            )
        );
        w.executePending(calls, 10155);
    }

    // ── Required-checker calldata loop body (lines 973-976, 994) ─────────────
    // Both _invokeBeforeRequiredCheckers and _invokeAfterRequiredCheckers must
    // iterate at least once through a successful checker call to an external target.

    function test_RequiredChecker_CalldataPath_LoopBodyReached() public {
        // checkerBothHooks: hookModes()=(true,true), revertBefore=false, revertAfter=false
        vm.startPrank(emergency);
        _setRequiredCheckers(_mkReq(address(checkerBothHooks), true, ""));
        vm.stopPrank();

        // executeTransaction -> _executeCallsWithHooks (calldata path) -> both loops
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 999));
        vm.prank(primary);
        wallet.executeTransaction(calls, 10_201);

        assertEq(receiver.value(), 999);
    }

    // ── Dead-branch coverage: _roleRank(Role.None) → ROLE_RANK_NONE (line 1591) ─
    // Role.None (value 0) is a valid enum value so this is callable through the harness.

    function test_DeadBranch_RoleRankNone_ReturnsZero() public {
        BaseMERAWalletHarness h = new BaseMERAWalletHarness(primary, backup, emergency, address(0), address(0));
        assertEq(h.exposedRoleRank(MERAWalletTypes.Role.None), 0);
    }

    // ── Dead-branch coverage: _rolePolicySlice(policy, Role.None) → revert InvalidRole (line 1483) ─
    // Role.None (value 0) falls through all three if-branches → revert InvalidRole().

    function test_DeadBranch_RolePolicySliceNone_RevertsInvalidRole() public {
        BaseMERAWalletHarness h = new BaseMERAWalletHarness(primary, backup, emergency, address(0), address(0));
        MERAWalletTypes.CallPathPolicy memory policy;
        policy.exists = true;
        vm.expectRevert(IBaseMERAWalletErrors.InvalidRole.selector);
        h.exposedRolePolicySlice(policy, MERAWalletTypes.Role.None);
    }
}

contract OwnableMock {
    address public owner;

    function transferOwnership(address newOwner) external {
        owner = newOwner;
    }
}

contract RevertingOwnableMock {
    error TransferOwnershipFailed();

    function transferOwnership(address) external pure {
        revert TransferOwnershipFailed();
    }
}

contract AccessControlMock {
    mapping(bytes32 => mapping(address => bool)) public roles;

    function grantRole(bytes32 role, address account) external {
        roles[role][account] = true;
    }
}

contract RejectingRelayExecutor {
    receive() external payable {
        revert("reject reward");
    }
}
