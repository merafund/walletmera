// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletConstants} from "./constants/MERAWalletConstants.sol";
import {MERAWalletTypes} from "./types/MERAWalletTypes.sol";
import {IBaseMERAWallet} from "./interfaces/IBaseMERAWallet.sol";
import {IBaseMERAWalletErrors} from "./interfaces/IBaseMERAWalletErrors.sol";
import {IBaseMERAWalletEvents} from "./interfaces/IBaseMERAWalletEvents.sol";
import {IMERAWalletTransactionChecker} from "./interfaces/extensions/IMERAWalletTransactionChecker.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract BaseMERAWallet is IBaseMERAWallet, IBaseMERAWalletEvents, IBaseMERAWalletErrors {
    address public primary;
    address public backup;
    address public emergency;
    address public eip1271Signer;

    uint256 public globalTimelock;
    mapping(address target => MERAWalletTypes.CallPathPolicy policy) public callPolicyByTarget;
    mapping(bytes4 selector => MERAWalletTypes.CallPathPolicy policy) public callPolicyBySelector;
    mapping(bytes32 operationId => MERAWalletTypes.PendingOperation operation) public operations;
    mapping(address checker => MERAWalletTypes.WhitelistChecker) public whitelistedChecker;

    address[] internal _requiredBeforeList;
    address[] internal _requiredAfterList;

    mapping(address checker => uint256 indexPlusOne) internal _requiredBeforeIndexPlusOne;
    mapping(address checker => uint256 indexPlusOne) internal _requiredAfterIndexPlusOne;

    /// @dev Emergency may call directly; the wallet may call itself (e.g. batched executeTransaction) for gated config.
    modifier onlyEmergencyOrSelf() {
        require(msg.sender == emergency || msg.sender == address(this), NotEmergency());
        _;
    }

    constructor(address initialPrimary, address initialBackup, address initialEmergency, address initialSigner) {
        require(
            initialPrimary != address(0) && initialBackup != address(0) && initialEmergency != address(0),
            InvalidAddress()
        );

        primary = initialPrimary;
        backup = initialBackup;
        emergency = initialEmergency;

        _set1271Signer(initialSigner);
    }

    receive() external payable override {}

    function setPrimary(address newPrimary) external override {
        require(newPrimary != address(0), InvalidAddress());

        require(msg.sender == primary || msg.sender == backup || msg.sender == emergency, Unauthorized());

        address previousPrimary = primary;
        primary = newPrimary;
        emit PrimaryUpdated(previousPrimary, newPrimary, msg.sender);
    }

    function setBackup(address newBackup) external override {
        require(newBackup != address(0), InvalidAddress());

        require(msg.sender == backup || msg.sender == emergency, NotAllowedRoleChange());

        address previousBackup = backup;
        backup = newBackup;
        emit BackupUpdated(previousBackup, newBackup, msg.sender);
    }

    function setEmergency(address newEmergency) external override {
        _onlyEmergency();
        require(newEmergency != address(0), InvalidAddress());

        address previousEmergency = emergency;
        emergency = newEmergency;
        emit EmergencyUpdated(previousEmergency, newEmergency, msg.sender);
    }

    function setGlobalTimelock(uint256 delay) external override onlyEmergencyOrSelf {
        uint256 previousDelay = globalTimelock;
        globalTimelock = delay;
        emit GlobalTimelockUpdated(previousDelay, delay, msg.sender);
    }

    function setTargetCallPolicy(address target, MERAWalletTypes.CallPathPolicy calldata policy)
        external
        override
        onlyEmergencyOrSelf
    {
        MERAWalletTypes.CallPathPolicy memory previousPolicy = callPolicyByTarget[target];
        callPolicyByTarget[target] = policy;
        emit TargetCallPolicyUpdated(target, previousPolicy, policy, msg.sender);
    }

    function setSelectorCallPolicy(bytes4 selector, MERAWalletTypes.CallPathPolicy calldata policy)
        external
        override
        onlyEmergencyOrSelf
    {
        MERAWalletTypes.CallPathPolicy memory previousPolicy = callPolicyBySelector[selector];
        callPolicyBySelector[selector] = policy;
        emit SelectorCallPolicyUpdated(selector, previousPolicy, policy, msg.sender);
    }

    function setRequiredChecker(address checker, bool enabled) external override onlyEmergencyOrSelf {
        require(checker != address(0), InvalidCheckerAddress());

        bool wasConfigured = _requiredBeforeIndexPlusOne[checker] != 0 || _requiredAfterIndexPlusOne[checker] != 0;

        if (!enabled) {
            require(wasConfigured, NoopCheckerConfig());
            _setRequiredBeforeChecker(checker, false);
            _setRequiredAfterChecker(checker, false);
            emit RequiredCheckerUpdated(checker, false, false, msg.sender);
            return;
        }

        (bool enableBefore, bool enableAfter) = IMERAWalletTransactionChecker(checker).hookModes();
        require(enableBefore || enableAfter || wasConfigured, NoopCheckerConfig());

        _setRequiredBeforeChecker(checker, enableBefore);
        _setRequiredAfterChecker(checker, enableAfter);

        emit RequiredCheckerUpdated(checker, enableBefore, enableAfter, msg.sender);
    }

    function setWhitelistedChecker(address checker, bool allowed) external override onlyEmergencyOrSelf {
        if (!allowed) {
            delete whitelistedChecker[checker];
            emit WhitelistCheckerUpdated(checker, false, false, false, msg.sender);
            return;
        }

        if (checker == address(0)) {
            whitelistedChecker[checker] =
                MERAWalletTypes.WhitelistChecker({allowed: true, enableBefore: false, enableAfter: false});
            emit WhitelistCheckerUpdated(checker, true, false, false, msg.sender);
            return;
        }

        (bool enableBefore, bool enableAfter) = IMERAWalletTransactionChecker(checker).hookModes();
        require(enableBefore || enableAfter, NoopCheckerConfig());

        whitelistedChecker[checker] =
            MERAWalletTypes.WhitelistChecker({allowed: true, enableBefore: enableBefore, enableAfter: enableAfter});
        emit WhitelistCheckerUpdated(checker, true, enableBefore, enableAfter, msg.sender);
    }

    function getRequiredBeforeCheckers() external view override returns (address[] memory) {
        return _requiredBeforeList;
    }

    function getRequiredAfterCheckers() external view override returns (address[] memory) {
        return _requiredAfterList;
    }

    function executeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 nonce) external payable override {
        MERAWalletTypes.Role callerRole = _requireController();
        MERAWalletTypes.Call[] memory memoryCalls = calls;

        _validateCalls(memoryCalls);

        bytes32 operationId = _computeOperationId(memoryCalls, nonce);
        uint256 requiredDelay = _getRequiredDelay(callerRole, memoryCalls);

        require(requiredDelay == 0, TimelockRequired(requiredDelay));

        _executeCallsWithHooks(memoryCalls, operationId);

        emit ImmediateTransactionExecuted(operationId, nonce, msg.sender);
    }

    function proposeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 nonce)
        external
        override
        returns (bytes32 operationId)
    {
        MERAWalletTypes.Role callerRole = _requireController();
        MERAWalletTypes.Call[] memory memoryCalls = calls;

        _validateCalls(memoryCalls);

        operationId = _computeOperationId(memoryCalls, nonce);
        uint256 requiredDelay = _getRequiredDelay(callerRole, memoryCalls);
        require(requiredDelay != 0, ZeroDelayNotProposable());

        require(
            operations[operationId].status != MERAWalletTypes.OperationStatus.Pending,
            OperationAlreadyPending(operationId)
        );

        uint256 executeAfter = block.timestamp + requiredDelay;
        operations[operationId] = MERAWalletTypes.PendingOperation({
            creator: msg.sender,
            creatorRole: callerRole,
            createdAt: uint64(block.timestamp),
            executeAfter: uint64(executeAfter),
            nonce: nonce,
            status: MERAWalletTypes.OperationStatus.Pending
        });

        _beforePropose(memoryCalls, operationId);

        emit TransactionProposed(operationId, nonce, msg.sender, callerRole, executeAfter, requiredDelay);
    }

    function executePending(MERAWalletTypes.Call[] calldata calls, uint256 nonce) external payable override {
        _requireController();
        MERAWalletTypes.Call[] memory memoryCalls = calls;
        _validateCalls(memoryCalls);

        bytes32 operationId = _computeOperationId(memoryCalls, nonce);
        MERAWalletTypes.PendingOperation storage operation = operations[operationId];

        require(operation.status == MERAWalletTypes.OperationStatus.Pending, OperationNotPending(operationId));
        require(block.timestamp >= operation.executeAfter, TimelockNotExpired(operation.executeAfter, block.timestamp));

        operation.status = MERAWalletTypes.OperationStatus.Executed;

        _executeCallsWithHooks(memoryCalls, operationId);

        emit PendingTransactionExecuted(operationId, nonce, msg.sender);
    }

    function cancelPending(bytes32 operationId) external override {
        MERAWalletTypes.Role callerRole = _requireController();
        MERAWalletTypes.PendingOperation storage operation = operations[operationId];
        require(operation.status == MERAWalletTypes.OperationStatus.Pending, OperationNotPending(operationId));

        bool isCreator = operation.creator == msg.sender;
        require(isCreator || _canOverrideRole(callerRole, operation.creatorRole), CannotCancelOperation(operationId));

        operation.status = MERAWalletTypes.OperationStatus.Cancelled;
        emit PendingTransactionCancelled(operationId, operation.nonce, msg.sender);
    }

    function getOperationId(MERAWalletTypes.Call[] calldata calls, uint256 nonce)
        external
        view
        override
        returns (bytes32)
    {
        MERAWalletTypes.Call[] memory memoryCalls = calls;
        _validateCalls(memoryCalls);
        return _computeOperationId(memoryCalls, nonce);
    }

    function getRequiredDelay(MERAWalletTypes.Call[] calldata calls) external view override returns (uint256) {
        MERAWalletTypes.Role callerRole = _roleOf(msg.sender);
        require(callerRole != MERAWalletTypes.Role.None, Unauthorized());

        MERAWalletTypes.Call[] memory memoryCalls = calls;
        _validateCalls(memoryCalls);
        return _getRequiredDelay(callerRole, memoryCalls);
    }

    function set1271Signer(address signer) external override onlyEmergencyOrSelf {
        _set1271Signer(signer);
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        address recovered = _recoverSigner(hash, signature);
        if (recovered == address(0)) {
            return MERAWalletConstants.EIP1271_INVALID;
        }

        if (eip1271Signer != address(0)) {
            return
                recovered == eip1271Signer
                    ? MERAWalletConstants.EIP1271_MAGICVALUE
                    : MERAWalletConstants.EIP1271_INVALID;
        }

        return MERAWalletConstants.EIP1271_INVALID;
    }

    function _executeSingleCall(
        address target,
        uint256 value,
        bytes memory data,
        address checker,
        bytes memory checkerData,
        uint256 nonce
    ) internal {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: target, value: value, data: data, checker: checker, checkerData: checkerData
        });
        _executeImmediateFromCalls(calls, nonce);
    }

    function _executeImmediateFromCalls(MERAWalletTypes.Call[] memory calls, uint256 nonce) internal {
        MERAWalletTypes.Role callerRole = _requireController();
        _validateCalls(calls);

        bytes32 operationId = _computeOperationId(calls, nonce);
        uint256 requiredDelay = _getRequiredDelay(callerRole, calls);
        require(requiredDelay == 0, TimelockRequired(requiredDelay));

        _executeCallsWithHooks(calls, operationId);

        emit ImmediateTransactionExecuted(operationId, nonce, msg.sender);
    }

    function _validateCalls(MERAWalletTypes.Call[] memory calls) internal view {
        require(calls.length > 0, EmptyCalls());
        _validateCallWhitelist(calls);
    }

    function _computeOperationId(MERAWalletTypes.Call[] memory calls, uint256 nonce) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), calls, nonce));
    }

    function _getRequiredDelay(MERAWalletTypes.Role callerRole, MERAWalletTypes.Call[] memory calls)
        internal
        view
        returns (uint256 requiredDelay)
    {
        if (callerRole == MERAWalletTypes.Role.Emergency) {
            return 0;
        }

        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength;) {
            uint256 callDelay = _getCallDelay(callerRole, calls[i]);
            if (callDelay > requiredDelay) {
                requiredDelay = callDelay;
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Required delay for one call: if neither target nor selector sets a role delay, use `globalTimelock`;
    ///      otherwise use max(target role delay, selector role delay). Reverts if path forbidden for role.
    function _getCallDelay(MERAWalletTypes.Role callerRole, MERAWalletTypes.Call memory callData)
        internal
        view
        returns (uint256)
    {
        MERAWalletTypes.CallPathPolicy memory targetPolicy = callPolicyByTarget[callData.target];
        bytes4 selector = _extractSelector(callData.data);
        MERAWalletTypes.CallPathPolicy memory selectorPolicy = callPolicyBySelector[selector];

        MERAWalletTypes.RoleCallPolicy memory targetRole = _rolePolicySlice(targetPolicy, callerRole);
        MERAWalletTypes.RoleCallPolicy memory selectorRole = _rolePolicySlice(selectorPolicy, callerRole);

        require(!targetRole.forbidden && !selectorRole.forbidden, CallPathForbiddenForRole(callerRole));

        uint256 a = uint256(targetRole.delay);
        uint256 b = uint256(selectorRole.delay);
        if (a == 0 && b == 0) {
            return globalTimelock;
        }
        return a > b ? a : b;
    }

    function _rolePolicySlice(MERAWalletTypes.CallPathPolicy memory policy, MERAWalletTypes.Role callerRole)
        internal
        pure
        returns (MERAWalletTypes.RoleCallPolicy memory)
    {
        if (callerRole == MERAWalletTypes.Role.Primary) {
            return policy.primary;
        }
        if (callerRole == MERAWalletTypes.Role.Backup) {
            return policy.backup;
        }
        revert InvalidRole();
    }

    /// @dev Runs before/after hooks and the external call for each entry in order so checkers observe post-state incrementally.
    function _executeCallsWithHooks(MERAWalletTypes.Call[] memory calls, bytes32 operationId) internal {
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength;) {
            MERAWalletTypes.Call memory callData = calls[i];
            _beforeExecute(callData, operationId, i);
            (bool success, bytes memory result) = callData.target.call{value: callData.value}(callData.data);
            require(success, CallExecutionFailed(i, result));
            _afterExecute(callData, operationId, i);
            unchecked {
                ++i;
            }
        }
    }

    function _setRequiredBeforeChecker(address checker, bool enabled) internal {
        bool current = _requiredBeforeIndexPlusOne[checker] != 0;
        if (current == enabled) {
            return;
        }

        if (enabled) {
            _addChecker(_requiredBeforeList, _requiredBeforeIndexPlusOne, checker);
            return;
        }
        _removeChecker(_requiredBeforeList, _requiredBeforeIndexPlusOne, checker);
    }

    function _setRequiredAfterChecker(address checker, bool enabled) internal {
        bool current = _requiredAfterIndexPlusOne[checker] != 0;
        if (current == enabled) {
            return;
        }

        if (enabled) {
            _addChecker(_requiredAfterList, _requiredAfterIndexPlusOne, checker);
            return;
        }
        _removeChecker(_requiredAfterList, _requiredAfterIndexPlusOne, checker);
    }

    function _addChecker(
        address[] storage checkerList,
        mapping(address checker => uint256) storage indexMap,
        address checker
    ) internal {
        checkerList.push(checker);
        indexMap[checker] = checkerList.length;
    }

    function _removeChecker(
        address[] storage checkerList,
        mapping(address checker => uint256) storage indexMap,
        address checker
    ) internal {
        uint256 indexPlusOne = indexMap[checker];
        if (indexPlusOne == 0) {
            return;
        }

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = checkerList.length - 1;
        if (index != lastIndex) {
            address lastChecker = checkerList[lastIndex];
            checkerList[index] = lastChecker;
            indexMap[lastChecker] = index + 1;
        }

        checkerList.pop();
        delete indexMap[checker];
    }

    function _validateCallWhitelist(MERAWalletTypes.Call[] memory calls) internal view {
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength;) {
            address checker = calls[i].checker;
            require(whitelistedChecker[checker].allowed, CheckerNotWhitelisted(checker, i));
            unchecked {
                ++i;
            }
        }
    }

    function _invokeBeforeRequiredCheckers(MERAWalletTypes.Call memory callData, bytes32 operationId, uint256 callId)
        internal
        view
    {
        uint256 checkersLength = _requiredBeforeList.length;
        if (checkersLength == 0) {
            return;
        }
        for (uint256 i = 0; i < checkersLength;) {
            IMERAWalletTransactionChecker(_requiredBeforeList[i]).checkBefore(callData, operationId, callId);
            unchecked {
                ++i;
            }
        }
    }

    function _invokeAfterRequiredCheckers(MERAWalletTypes.Call memory callData, bytes32 operationId, uint256 callId)
        internal
        view
    {
        uint256 checkersLength = _requiredAfterList.length;
        if (checkersLength == 0) {
            return;
        }
        for (uint256 i = 0; i < checkersLength;) {
            IMERAWalletTransactionChecker(_requiredAfterList[i]).checkAfter(callData, operationId, callId);
            unchecked {
                ++i;
            }
        }
    }

    function _invokeBeforeWhitelistedChecker(MERAWalletTypes.Call memory callData, bytes32 operationId, uint256 callId)
        internal
        view
    {
        address checker = callData.checker;
        if (checker == address(0) || !whitelistedChecker[checker].enableBefore) {
            return;
        }
        IMERAWalletTransactionChecker(checker).checkBefore(callData, operationId, callId);
    }

    function _invokeAfterWhitelistedChecker(MERAWalletTypes.Call memory callData, bytes32 operationId, uint256 callId)
        internal
        view
    {
        address checker = callData.checker;
        if (checker == address(0) || !whitelistedChecker[checker].enableAfter) {
            return;
        }
        IMERAWalletTransactionChecker(checker).checkAfter(callData, operationId, callId);
    }

    function _set1271Signer(address signer) internal {
        require(signer == address(0) || signer == primary || signer == backup || signer == emergency, InvalidSigner());

        address previousSigner = eip1271Signer;
        eip1271Signer = signer;
        emit EIP1271SignerUpdated(previousSigner, signer, msg.sender);
    }

    // Consider refactoring low-level helpers (bytes selector reads, ECDSA, etc.) to Solady where it fits.
    function _extractSelector(bytes memory data) internal pure returns (bytes4 selector) {
        if (data.length < 4) {
            return bytes4(0);
        }
        // The first 4 bytes in calldata-encoded call data are always the function selector.
        assembly {
            selector := mload(add(data, 32))
        }
    }

    /// @dev OpenZeppelin ECDSA on calldata; zero address on invalid signature (no revert, for EIP-1271).
    function _recoverSigner(bytes32 hash, bytes calldata signature) internal pure returns (address) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecoverCalldata(hash, signature);
        if (err != ECDSA.RecoverError.NoError) {
            return address(0);
        }
        return recovered;
    }

    function _requireController() internal view returns (MERAWalletTypes.Role role) {
        role = _roleOf(msg.sender);
        require(role != MERAWalletTypes.Role.None, Unauthorized());
    }

    function _onlyEmergency() internal view {
        require(msg.sender == emergency, NotEmergency());
    }

    function _roleOf(address account) internal view returns (MERAWalletTypes.Role) {
        if (account == primary) {
            return MERAWalletTypes.Role.Primary;
        }
        if (account == backup) {
            return MERAWalletTypes.Role.Backup;
        }
        if (account == emergency) {
            return MERAWalletTypes.Role.Emergency;
        }
        return MERAWalletTypes.Role.None;
    }

    function _canOverrideRole(MERAWalletTypes.Role callerRole, MERAWalletTypes.Role creatorRole)
        internal
        pure
        returns (bool)
    {
        return (callerRole == MERAWalletTypes.Role.Backup && creatorRole == MERAWalletTypes.Role.Primary)
            || (callerRole == MERAWalletTypes.Role.Emergency
                && (creatorRole == MERAWalletTypes.Role.Primary || creatorRole == MERAWalletTypes.Role.Backup));
    }

    function _beforePropose(MERAWalletTypes.Call[] memory calls, bytes32 operationId) internal virtual {}

    function _beforeExecute(MERAWalletTypes.Call memory callData, bytes32 operationId, uint256 callId)
        internal
        virtual
    {
        _invokeBeforeRequiredCheckers(callData, operationId, callId);
        _invokeBeforeWhitelistedChecker(callData, operationId, callId);
    }

    function _afterExecute(MERAWalletTypes.Call memory callData, bytes32 operationId, uint256 callId) internal virtual {
        _invokeAfterRequiredCheckers(callData, operationId, callId);
        _invokeAfterWhitelistedChecker(callData, operationId, callId);
    }
}
