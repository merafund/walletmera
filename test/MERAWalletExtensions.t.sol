// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MERAWalletNative} from "../src/extensions/MERAWalletNative.sol";
import {MERAWalletERC20} from "../src/extensions/token/ERC20/MERAWalletERC20.sol";
import {IBaseMERAWalletErrors} from "../src/interfaces/IBaseMERAWalletErrors.sol";
import {MERAWalletConstants} from "../src/constants/MERAWalletConstants.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {ConfigurableTransactionChecker} from "./mocks/ConfigurableTransactionChecker.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ReceiverMock} from "./mocks/ReceiverMock.sol";
import {MERAWalletTestBase} from "./helpers/MERAWalletTestBase.sol";

contract MERAWalletExtensionsHarness is MERAWalletNative, MERAWalletERC20 {
    constructor(address primary_, address backup_, address emergency_)
        BaseMERAWallet(primary_, backup_, emergency_, address(0), address(0))
    {}

    function exposedExtractSelector(bytes memory data) external pure returns (bytes4) {
        return _extractSelectorFromMemoryBytes(data);
    }

    function exposedValidateEmptyCalls() external view {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](0);
        _validateCallsMemory(calls);
    }

    function exposedValidateTooManyCalls() external view {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](MERAWalletConstants.MAX_CALLS_PER_BATCH + 1);
        _validateCallsMemory(calls);
    }

    function exposedValidateSelfCallWithUnallowedChecker(address checker) external view {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        _setSingleCallMemory(calls, address(this), 0, "", checker, "");
        _validateCallsMemory(calls);
    }

    function exposedValidateExternalCallWithUnallowedChecker(address target, address checker) external view {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        _setSingleCallMemory(calls, target, 0, "", checker, "");
        _validateCallsMemory(calls);
    }

    function exposedOperationIdForTransfer(address target, uint256 value, uint256 salt)
        external
        view
        returns (bytes32)
    {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        _setSingleCallMemory(calls, target, value, "", address(0), "");
        return _computeOperationIdMemory(calls, salt);
    }

    function exposedOperationIdForERC20Transfer(address token, address to, uint256 amount, uint256 salt)
        external
        view
        returns (bytes32)
    {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        _setSingleCallMemory(
            calls, token, 0, abi.encodeWithSelector(IERC20.transfer.selector, to, amount), address(0), ""
        );
        return _computeOperationIdMemory(calls, salt);
    }

    function exposedProposeNative(address payable target, uint256 value, uint256 salt) external returns (bytes32) {
        return _proposeSingleCallMemory(target, value, "", address(0), "", salt);
    }

    function exposedSetRelayOperation(
        bytes32 operationId,
        MERAWalletTypes.RelayExecutorPolicy policy,
        address designatedExecutor,
        bytes32 executorSetHash,
        uint64 relayExecuteBefore
    ) external {
        _relayOperations[operationId] = MERAWalletTypes.RelayOperation({
            relayPolicy: policy,
            relayReward: 0,
            designatedExecutor: designatedExecutor,
            executorSetHash: executorSetHash,
            relayExecuteBefore: relayExecuteBefore
        });
    }

    function exposedExecutePendingTransferWithWhitelist(
        address payable target,
        uint256 value,
        uint256 salt,
        address[] memory executorWhitelist
    ) external {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        _setSingleCallMemory(calls, target, value, "", address(0), "");
        _executePendingFromMemory(calls, salt, executorWhitelist);
    }
}

contract MERAWalletExtensionsTest is MERAWalletTestBase {
    address internal primary = vm.addr(PRIMARY_PK);
    address internal backup = vm.addr(BACKUP_PK);
    address internal emergency = vm.addr(EMERGENCY_PK);
    address internal outsider = OUTSIDER_ADDRESS;

    MERAWalletExtensionsHarness internal wallet;
    ReceiverMock internal receiver;
    ERC20Mock internal token;
    ConfigurableTransactionChecker internal checkerBothHooks;

    function setUp() public {
        wallet = new MERAWalletExtensionsHarness(primary, backup, emergency);
        receiver = new ReceiverMock();
        token = new ERC20Mock();
        checkerBothHooks = new ConfigurableTransactionChecker(true, true, address(wallet));

        vm.deal(address(wallet), 10 ether);
        token.mint(address(wallet), 100 ether);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(wallet, 0);
        _setOptionalChecker(address(0), true, "");
        vm.stopPrank();
    }

    function test_ExtractSelector_ShortMemoryDataReturnsZero() public view {
        assertEq(wallet.exposedExtractSelector(hex"010203"), bytes4(0));
    }

    function test_ExtractSelector_FourByteMemoryDataReturnsSelector() public view {
        assertEq(wallet.exposedExtractSelector(hex"01020304"), bytes4(0x01020304));
    }

    function test_ValidateCallsMemory_EmptyCallsReverts() public {
        vm.expectRevert(IBaseMERAWalletErrors.EmptyCalls.selector);
        wallet.exposedValidateEmptyCalls();
    }

    function test_ValidateCallsMemory_TooManyCallsReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.TooManyCalls.selector,
                MERAWalletConstants.MAX_CALLS_PER_BATCH + 1,
                MERAWalletConstants.MAX_CALLS_PER_BATCH
            )
        );
        wallet.exposedValidateTooManyCalls();
    }

    function test_ValidateCallsMemory_SelfCallSkipsOptionalCheckerWhitelist() public view {
        wallet.exposedValidateSelfCallWithUnallowedChecker(address(checkerBothHooks));
    }

    function test_ValidateCallsMemory_ExternalUnallowedCheckerReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.OptionalCheckerNotAllowed.selector, address(checkerBothHooks), uint256(0)
            )
        );
        wallet.exposedValidateExternalCallWithUnallowedChecker(address(receiver), address(checkerBothHooks));
    }

    function test_TransferNative_ImmediateExternalCallSucceeds() public {
        vm.prank(primary);
        wallet.transferNative(payable(address(receiver)), 1 ether, 1001);

        assertEq(address(receiver).balance, 1 ether);
    }

    function test_CallExternal_SelfCallUsesMemoryExecutionContext() public {
        vm.prank(emergency);
        wallet.callExternal(
            address(wallet),
            0,
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Primary, 1),
            1002
        );

        assertEq(wallet.roleTimelock(MERAWalletTypes.Role.Primary), 1);
    }

    function test_CallExternal_FailedExternalCallReverts() public {
        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CallExecutionFailed.selector, uint256(0), ""));
        wallet.callExternal(address(receiver), 0, hex"deadbeef", 1003);
    }

    function test_TransferNative_WithAllowedOptionalCheckerRunsHooks() public {
        vm.prank(emergency);
        _setOptionalChecker(address(checkerBothHooks), true, "");

        vm.prank(primary);
        wallet.transferNative(payable(address(receiver)), 1 ether, address(checkerBothHooks), "", 1004);

        assertEq(address(receiver).balance, 1 ether);
    }

    function test_TransferERC20_ImmediateTransferSucceeds() public {
        vm.prank(primary);
        wallet.transferERC20(address(token), address(receiver), 2 ether, address(0), "", 1005);

        assertEq(token.balanceOf(address(receiver)), 2 ether);
    }

    function test_TransferERC20_WhenTimelockedReverts() public {
        vm.prank(emergency);
        _setRoleTimelock(MERAWalletTypes.Role.Primary, 1 days);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.TimelockRequired.selector, 1 days));
        wallet.transferERC20(address(token), address(receiver), 1 ether, address(0), "", 1006);
    }

    function test_ProposeTransferERC20_WhenDelayZeroReverts() public {
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.ZeroDelayNotProposable.selector);
        wallet.proposeTransferERC20(address(token), address(receiver), 1 ether, address(0), "", 1007);
    }

    function test_ProposeTransferERC20_WithDelayStoresPendingOperation() public {
        vm.prank(emergency);
        _setRoleTimelock(MERAWalletTypes.Role.Primary, 1 days);

        vm.prank(primary);
        bytes32 operationId =
            wallet.proposeTransferERC20(address(token), address(receiver), 1 ether, address(0), "", 1008);

        (,,, uint64 executeAfter,, MERAWalletTypes.OperationStatus status,,,,,) = wallet.operations(operationId);
        assertEq(uint256(status), uint256(MERAWalletTypes.OperationStatus.Pending));
        assertEq(executeAfter, block.timestamp + 1 days);
    }

    function test_ProposeTransferERC20_SameOperationTwiceReverts() public {
        vm.prank(emergency);
        _setRoleTimelock(MERAWalletTypes.Role.Primary, 1 days);

        vm.prank(primary);
        wallet.proposeTransferERC20(address(token), address(receiver), 1 ether, address(0), "", 1009);

        bytes32 operationId =
            wallet.exposedOperationIdForERC20Transfer(address(token), address(receiver), 1 ether, 1009);
        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.OperationAlreadyUsed.selector, operationId));
        wallet.proposeTransferERC20(address(token), address(receiver), 1 ether, address(0), "", 1009);
    }

    function test_ExecutePendingTransferERC20_NotPendingReverts() public {
        bytes32 operationId =
            wallet.exposedOperationIdForERC20Transfer(address(token), address(receiver), 1 ether, 1010);
        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.OperationNotPending.selector, operationId));
        wallet.executePendingTransferERC20(address(token), address(receiver), 1 ether, address(0), "", 1010);
    }

    function test_ExecutePendingTransferERC20_BeforeTimelockReverts() public {
        vm.prank(emergency);
        _setRoleTimelock(MERAWalletTypes.Role.Primary, 1 days);

        vm.prank(primary);
        bytes32 operationId =
            wallet.proposeTransferERC20(address(token), address(receiver), 1 ether, address(0), "", 1011);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(operationId);

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(IBaseMERAWalletErrors.TimelockNotExpired.selector, executeAfter, block.timestamp)
        );
        wallet.executePendingTransferERC20(address(token), address(receiver), 1 ether, address(0), "", 1011);
    }

    function test_ExecutePendingTransferERC20_CoreExecuteSucceedsAfterTimelock() public {
        vm.prank(emergency);
        _setRoleTimelock(MERAWalletTypes.Role.Primary, 1 days);

        vm.prank(primary);
        wallet.proposeTransferERC20(address(token), address(receiver), 1 ether, address(0), "", 1012);
        vm.warp(block.timestamp + 1 days);

        vm.prank(primary);
        wallet.executePendingTransferERC20(address(token), address(receiver), 1 ether, address(0), "", 1012);

        assertEq(token.balanceOf(address(receiver)), 1 ether);
    }

    function test_ExecutePendingFromMemory_CoreExecuteRejectsWhitelist() public {
        vm.prank(emergency);
        _setRoleTimelock(MERAWalletTypes.Role.Primary, 1 days);

        vm.prank(primary);
        wallet.exposedProposeNative(payable(address(receiver)), 1 ether, 1013);
        vm.warp(block.timestamp + 1 days);

        address[] memory whitelist = _oneAddress(primary);
        vm.prank(primary);
        vm.expectRevert(IBaseMERAWalletErrors.InvalidExecutorWhitelist.selector);
        wallet.exposedExecutePendingTransferWithWhitelist(payable(address(receiver)), 1 ether, 1013, whitelist);
    }

    function test_ExecutePendingFromMemory_AnyoneRelayRejectsCoreExecutor() public {
        vm.prank(emergency);
        _setRoleTimelock(MERAWalletTypes.Role.Primary, 1 days);

        vm.prank(primary);
        wallet.exposedProposeNative(payable(address(receiver)), 1 ether, 1014);
        bytes32 operationId = wallet.exposedOperationIdForTransfer(payable(address(receiver)), 1 ether, 1014);
        wallet.exposedSetRelayOperation(
            operationId,
            MERAWalletTypes.RelayExecutorPolicy.Anyone,
            address(0),
            bytes32(0),
            uint64(block.timestamp + 2 days)
        );
        vm.warp(block.timestamp + 1 days);

        address[] memory whitelist = new address[](0);
        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IBaseMERAWalletErrors.CoreExecutorNotAllowed.selector, primary));
        wallet.exposedExecutePendingTransferWithWhitelist(payable(address(receiver)), 1 ether, 1014, whitelist);
    }

    function test_ExecutePendingFromMemory_AnyoneRelayAllowsExternalExecutor() public {
        vm.prank(emergency);
        _setRoleTimelock(MERAWalletTypes.Role.Primary, 1 days);

        vm.prank(primary);
        wallet.exposedProposeNative(payable(address(receiver)), 1 ether, 1015);
        bytes32 operationId = wallet.exposedOperationIdForTransfer(payable(address(receiver)), 1 ether, 1015);
        wallet.exposedSetRelayOperation(
            operationId,
            MERAWalletTypes.RelayExecutorPolicy.Anyone,
            address(0),
            bytes32(0),
            uint64(block.timestamp + 2 days)
        );
        vm.warp(block.timestamp + 1 days);

        address[] memory whitelist = new address[](0);
        vm.prank(outsider);
        wallet.exposedExecutePendingTransferWithWhitelist(payable(address(receiver)), 1 ether, 1015, whitelist);
    }

    function _setRoleTimelock(MERAWalletTypes.Role role, uint256 delay) internal {
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(wallet), 0, abi.encodeWithSelector(wallet.setRoleTimelock.selector, role, delay));
        wallet.executeTransaction(calls, uint256(role) * 100_000 + delay + 1);
    }

    function _setOptionalChecker(address checker, bool allowed, bytes memory config) internal {
        MERAWalletTypes.OptionalCheckerUpdate[] memory updates = _mkOptionalCheckerUpdate(checker, allowed, config);
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(wallet), 0, abi.encodeWithSelector(wallet.setOptionalCheckers.selector, updates));
        wallet.executeTransaction(calls, 900_000 + uint160(checker));
    }

    function _setRequiredChecker(address checker, bool enabled) internal {
        MERAWalletTypes.RequiredCheckerUpdate[] memory updates = new MERAWalletTypes.RequiredCheckerUpdate[](1);
        updates[0] = MERAWalletTypes.RequiredCheckerUpdate({checker: checker, enabled: enabled, config: ""});
        MERAWalletTypes.Call[] memory calls =
            _singleCall(address(wallet), 0, abi.encodeWithSelector(wallet.setRequiredCheckers.selector, updates));
        wallet.executeTransaction(calls, 800_000 + uint160(checker));
    }

    // ── MERAWalletNative: callExternal overload with checker ──────────────────

    function test_CallExternal_WithCheckerOverload_RunsHooks() public {
        vm.prank(emergency);
        _setOptionalChecker(address(checkerBothHooks), true, "");

        vm.prank(primary);
        wallet.callExternal(
            address(receiver),
            0,
            abi.encodeWithSelector(ReceiverMock.setValue.selector, 42),
            address(checkerBothHooks),
            "",
            2001
        );
        assertEq(receiver.value(), 42);
    }

    function test_CallExternalWithChecker_Works() public {
        vm.prank(emergency);
        _setOptionalChecker(address(checkerBothHooks), true, "");

        vm.prank(primary);
        wallet.callExternalWithChecker(
            address(receiver),
            0,
            abi.encodeWithSelector(ReceiverMock.setValue.selector, 77),
            address(checkerBothHooks),
            "",
            2002
        );
        assertEq(receiver.value(), 77);
    }

    // ── MERAWalletERC20: proposeApproveERC20 / executePendingApproveERC20 ─────

    function test_ProposeApproveERC20_StoresPendingOperation() public {
        address spender = PAUSE_AGENT;
        vm.prank(emergency);
        _setRoleTimelock(MERAWalletTypes.Role.Primary, 1 days);

        vm.prank(primary);
        bytes32 opId = wallet.proposeApproveERC20(address(token), spender, 500 ether, address(0), "", 2003);
        assertTrue(opId != bytes32(0));
    }

    function test_ExecutePendingApproveERC20_Works() public {
        address spender = PAUSE_AGENT;
        vm.prank(emergency);
        _setRoleTimelock(MERAWalletTypes.Role.Primary, 1 days);

        vm.prank(primary);
        wallet.proposeApproveERC20(address(token), spender, 500 ether, address(0), "", 2004);
        vm.warp(block.timestamp + 1 days);

        vm.prank(primary);
        wallet.executePendingApproveERC20(address(token), spender, 500 ether, address(0), "", 2004);

        assertEq(token.allowance(address(wallet), spender), 500 ether);
    }

    // ── Required checkers: memory-path loop body coverage ────────────────────
    // Covers BaseMERAWallet._invokeBeforeRequiredCheckersWithCallMemory (lines 1037-1040)
    // and _invokeAfterRequiredCheckersWithCallMemory (lines 1057-1060)

    function test_RequiredChecker_MemoryPath_LoopBodyReached() public {
        // checkerBothHooks has hookModes() = (true, true): both before & after required hooks
        vm.startPrank(emergency);
        _setRequiredChecker(address(checkerBothHooks), true);
        vm.stopPrank();

        // callExternal uses memory path; target is external (not address(this))
        vm.prank(primary);
        wallet.callExternal(address(receiver), 0, abi.encodeWithSelector(ReceiverMock.setValue.selector, 55), 2005);
        assertEq(receiver.value(), 55);
    }
}
