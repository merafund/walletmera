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
    /// @dev Optional recovery / multisig; address(0) disables guardian-only path for {setEmergency}.
    address public immutable GUARDIAN;

    address public primary;
    address public backup;
    address public emergency;
    address public eip1271Signer;

    uint256 public globalTimelock;
    uint256 public lifeHeartbeatTimeout;
    uint256 public lastLifeHeartbeatAt;
    bool public lifeControlEnabled;
    bool public frozenPrimary;
    bool public frozenBackup;
    uint256 public safeModeBefore;
    bool public safeModeUsed;
    mapping(address target => MERAWalletTypes.CallPathPolicy policy) public callPolicyByTarget;
    mapping(bytes4 selector => MERAWalletTypes.CallPathPolicy policy) public callPolicyBySelector;
    mapping(address target => mapping(bytes4 selector => MERAWalletTypes.CallPathPolicy policy)) public
        callPolicyByTargetSelector;
    mapping(bytes32 operationId => MERAWalletTypes.PendingOperation operation) internal _operations;
    mapping(bytes32 operationId => MERAWalletTypes.RelayOperation relayOperation) internal _relayOperations;
    mapping(address checker => MERAWalletTypes.OptionalChecker) public whitelistOptionalChecker;
    mapping(address agent => MERAWalletTypes.ControllerAgent) public controllerAgents;

    address[] internal requiredBeforeCheckers;
    address[] internal requiredAfterCheckers;

    mapping(address checker => uint256 indexPlusOne) internal _requiredBeforeIndexPlusOne;
    mapping(address checker => uint256 indexPlusOne) internal _requiredAfterIndexPlusOne;
    mapping(address controller => bool) internal _isLifeController;

    /// @dev When GUARDIAN is unset, emergency may call directly; when set, only self-calls (e.g. batched execute) may reach gated config.
    modifier onlyEmergencyOrSelf() {
        _onlyEmergencyOrSelf();
        _;
    }
    modifier whenLifeAlive() {
        _requireLifeAliveForStateChanges();
        _;
    }

    /// @dev Caller must be a core controller and not frozen for Primary/Backup.
    modifier whenControllerCoreUnfrozen() {
        _requireControllerCoreUnfrozen();
        _;
    }

    constructor(
        address initialPrimary,
        address initialBackup,
        address initialEmergency,
        address initialSigner,
        address initialGuardian
    ) {
        require(
            initialPrimary != address(0) && initialBackup != address(0) && initialEmergency != address(0),
            InvalidAddress()
        );

        GUARDIAN = initialGuardian;

        primary = initialPrimary;
        backup = initialBackup;
        emergency = initialEmergency;
        _setLifeController(initialEmergency, true, msg.sender);
        lastLifeHeartbeatAt = block.timestamp;

        _set1271Signer(initialSigner);
    }

    receive() external payable override {}

    function setPrimary(address newPrimary) external override whenLifeAlive {
        require(newPrimary != address(0), InvalidAddress());

        _requireCoreRoleNotFrozen(_coreRole(msg.sender));

        require(msg.sender == primary || msg.sender == backup || msg.sender == emergency, Unauthorized());

        address previousPrimary = primary;
        primary = newPrimary;
        if (eip1271Signer == previousPrimary) {
            _set1271Signer(newPrimary);
        }
        emit PrimaryUpdated(previousPrimary, newPrimary, msg.sender);
    }

    function setBackup(address newBackup) external override whenLifeAlive {
        require(newBackup != address(0), InvalidAddress());

        _requireCoreRoleNotFrozen(_coreRole(msg.sender));

        require(msg.sender == backup || msg.sender == emergency, NotAllowedRoleChange());

        address previousBackup = backup;
        backup = newBackup;
        if (eip1271Signer == previousBackup) {
            _set1271Signer(newBackup);
        }
        emit BackupUpdated(previousBackup, newBackup, msg.sender);
    }

    function setEmergency(address newEmergency) external override {
        require(_canSetEmergency(msg.sender), NotEmergency());
        require(newEmergency != address(0), InvalidAddress());

        address previousEmergency = emergency;
        emergency = newEmergency;
        if (previousEmergency != newEmergency) {
            _setLifeController(previousEmergency, false, msg.sender);
            _setLifeController(newEmergency, true, msg.sender);
        }
        if (eip1271Signer == previousEmergency) {
            _set1271Signer(newEmergency);
        }
        emit EmergencyUpdated(previousEmergency, newEmergency, msg.sender);
    }

    function setGlobalTimelock(uint256 delay) external override onlyEmergencyOrSelf whenLifeAlive {
        require(
            delay <= MERAWalletConstants.MAX_TIMELOCK_DELAY,
            TimelockDelayTooLarge(delay, MERAWalletConstants.MAX_TIMELOCK_DELAY)
        );
        uint256 previousDelay = globalTimelock;
        globalTimelock = delay;
        emit GlobalTimelockUpdated(previousDelay, delay, msg.sender);
    }

    function setLifeControl(bool enabled, uint256 timeout) external override {
        require(msg.sender == emergency, NotEmergency());
        if (enabled) {
            require(timeout != 0, LifeHeartbeatTimeoutZero());
            _setLifeController(emergency, true, msg.sender);
            if (!lifeControlEnabled) {
                lastLifeHeartbeatAt = block.timestamp;
            }
        }

        lifeControlEnabled = enabled;
        lifeHeartbeatTimeout = timeout;
        emit LifeControlUpdated(enabled, timeout, msg.sender);
    }

    function setLifeControllers(address[] calldata controllers, bool enabled) external override {
        require(msg.sender == emergency, NotEmergency());
        uint256 controllersLength = controllers.length;
        for (uint256 i = 0; i < controllersLength;) {
            address controller = controllers[i];
            require(controller != address(0), InvalidAddress());

            if (enabled) {
                _setLifeController(controller, true, msg.sender);
            } else {
                require(controller != emergency, EmergencyMustStayLifeController());
                _setLifeController(controller, false, msg.sender);
            }

            unchecked {
                ++i;
            }
        }
    }

    function confirmAlive() external override {
        require(_isLifeController[msg.sender], NotLifeController());
        lastLifeHeartbeatAt = block.timestamp;
        emit LifeHeartbeatConfirmed(msg.sender, block.timestamp);
    }

    function setTargetCallPolicies(address[] calldata targets, MERAWalletTypes.CallPathPolicy[] calldata policies)
        external
        override
        onlyEmergencyOrSelf
        whenLifeAlive
    {
        uint256 n = targets.length;
        require(n == policies.length, ArrayLengthMismatch(n, policies.length));
        for (uint256 i = 0; i < n;) {
            _setTargetCallPolicy(targets[i], policies[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setSelectorCallPolicies(bytes4[] calldata selectors, MERAWalletTypes.CallPathPolicy[] calldata policies)
        external
        override
        onlyEmergencyOrSelf
        whenLifeAlive
    {
        uint256 n = selectors.length;
        require(n == policies.length, ArrayLengthMismatch(n, policies.length));
        for (uint256 i = 0; i < n;) {
            _setSelectorCallPolicy(selectors[i], policies[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setTargetSelectorCallPolicies(
        address[] calldata targets,
        bytes4[] calldata selectors,
        MERAWalletTypes.CallPathPolicy[] calldata policies
    ) external override onlyEmergencyOrSelf whenLifeAlive {
        uint256 n = targets.length;
        require(n == selectors.length, ArrayLengthMismatch(n, selectors.length));
        require(n == policies.length, ArrayLengthMismatch(n, policies.length));
        for (uint256 i = 0; i < n;) {
            _setTargetSelectorCallPolicy(targets[i], selectors[i], policies[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setRequiredCheckers(address[] calldata checkers, bool[] calldata enabled)
        external
        override
        onlyEmergencyOrSelf
        whenLifeAlive
    {
        uint256 n = checkers.length;
        require(n == enabled.length, ArrayLengthMismatch(n, enabled.length));
        for (uint256 i = 0; i < n;) {
            _setRequiredChecker(checkers[i], enabled[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setOptionalCheckers(MERAWalletTypes.OptionalCheckerUpdate[] calldata updates)
        external
        override
        onlyEmergencyOrSelf
        whenLifeAlive
    {
        uint256 n = updates.length;
        for (uint256 i = 0; i < n;) {
            MERAWalletTypes.OptionalCheckerUpdate calldata u = updates[i];
            _setOptionalChecker(u.checker, u.allowed, u.config);
            unchecked {
                ++i;
            }
        }
    }

    function setControllerAgents(address[] calldata agents, bool[] calldata enabled) external override whenLifeAlive {
        uint256 n = agents.length;
        require(n == enabled.length, ArrayLengthMismatch(n, enabled.length));
        for (uint256 i = 0; i < n;) {
            _setControllerAgent(agents[i], enabled[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Backup or Emergency may toggle primary freeze; enabled controller agents may set freeze to true only.
    function setFrozenPrimary(bool frozen) external override {
        MERAWalletTypes.Role callerCore = _coreRole(msg.sender);
        bool allowed = callerCore == MERAWalletTypes.Role.Backup || callerCore == MERAWalletTypes.Role.Emergency;
        if (!allowed) {
            MERAWalletTypes.ControllerAgent storage agent = controllerAgents[msg.sender];
            allowed = agent.enabled && frozen;
        }
        require(allowed, FreezeActionNotAuthorized());

        frozenPrimary = frozen;
        emit PrimaryFreezeUpdated(frozen, msg.sender);
    }

    /// @dev Emergency may toggle backup freeze. Backup-scoped controller agents may set freeze to true only (same pattern as {setFrozenPrimary} for agents).
    function setFrozenBackup(bool frozen) external override {
        MERAWalletTypes.Role callerCore = _coreRole(msg.sender);
        bool allowed = callerCore == MERAWalletTypes.Role.Emergency;
        if (!allowed) {
            MERAWalletTypes.ControllerAgent storage agent = controllerAgents[msg.sender];
            allowed = agent.enabled && frozen && agent.roleLevel == MERAWalletTypes.Role.Backup;
        }
        require(allowed, FreezeActionNotAuthorized());
        if (frozenBackup == frozen) {
            return;
        }
        frozenBackup = frozen;
        emit BackupFreezeUpdated(frozen, msg.sender);
    }

    function enterSafeMode(uint256 duration) external override {
        require(
            msg.sender == emergency
                || (controllerAgents[msg.sender].enabled
                    && controllerAgents[msg.sender].roleLevel == MERAWalletTypes.Role.Emergency),
            SafeModeNotAuthorized()
        );
        require(!safeModeUsed, SafeModeAlreadyUsed());
        require(
            duration >= MERAWalletConstants.SAFE_MODE_MIN_DURATION
                && duration <= MERAWalletConstants.SAFE_MODE_MAX_DURATION,
            SafeModeDurationOutOfRange(duration)
        );

        safeModeUsed = true;
        safeModeBefore = block.timestamp + duration;
        emit SafeModeEntered(safeModeBefore, msg.sender);
    }

    function resetSafeMode() external override {
        require(msg.sender == emergency, NotEmergency());
        require(safeModeUsed, SafeModeNotUsed());
        require(block.timestamp > safeModeBefore, SafeModeStillActive(safeModeBefore));

        safeModeUsed = false;
        safeModeBefore = 0;
        emit SafeModeReset(msg.sender);
    }

    function executeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        external
        payable
        override
        whenLifeAlive
        whenControllerCoreUnfrozen
    {
        _validateCalls(calls);

        bytes32 operationId = _computeOperationId(calls, salt);
        uint256 requiredDelay = _getRequiredDelay(_coreRole(msg.sender), calls);

        require(requiredDelay == 0, TimelockRequired(requiredDelay));

        _executeCallsWithHooks(calls, operationId);

        emit ImmediateTransactionExecuted(operationId, salt, msg.sender);
    }

    function proposeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        external
        override
        whenLifeAlive
        returns (bytes32 operationId)
    {
        (operationId,,,) = _proposeTransaction(calls, salt);
    }

    function proposeTransactionWithRelay(
        MERAWalletTypes.Call[] calldata calls,
        uint256 salt,
        MERAWalletTypes.RelayProposeConfig calldata relayConfig
    ) external payable override whenLifeAlive returns (bytes32 operationId) {
        _validateRelayConfig(relayConfig, msg.value);

        uint256 executeAfter;
        (operationId,, executeAfter,) = _proposeTransaction(calls, salt);
        require(
            uint256(relayConfig.relayExecuteBefore) >= executeAfter,
            RelayDeadlineBeforeTimelock(relayConfig.relayExecuteBefore, executeAfter)
        );
        _saveRelayOperation(operationId, relayConfig, msg.value);
    }

    function executePending(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        external
        payable
        override
        whenLifeAlive
    {
        _executePending(calls, salt, new address[](0));
    }

    function executePending(MERAWalletTypes.Call[] calldata calls, uint256 salt, address[] calldata executorWhitelist)
        external
        payable
        override
        whenLifeAlive
    {
        _executePending(calls, salt, executorWhitelist);
    }

    function vetoPending(bytes32 operationId) external override {
        require(controllerAgents[msg.sender].enabled, Unauthorized());
        require(_coreRole(msg.sender) == MERAWalletTypes.Role.None, Unauthorized());

        MERAWalletTypes.PendingOperation storage operation = _operations[operationId];
        require(operation.status != MERAWalletTypes.OperationStatus.Vetoed, OperationAlreadyVetoed(operationId));
        require(operation.status == MERAWalletTypes.OperationStatus.Pending, OperationNotPending(operationId));

        require(operation.creatorRole != MERAWalletTypes.Role.Emergency, AgentCannotVetoEmergencyOperation());

        operation.status = MERAWalletTypes.OperationStatus.Vetoed;
        emit PendingTransactionVetoed(operationId, operation.salt, msg.sender);
    }

    /// @notice Resume a vetoed timelock op: unfrozen core controller; uses {_roleRank} (Primary=1 .. Emergency=3). Requires caller rank >= operation creator rank (same or higher numeric rank).
    function clearVeto(bytes32 operationId) external override whenLifeAlive whenControllerCoreUnfrozen {
        MERAWalletTypes.PendingOperation storage operation = _operations[operationId];
        require(operation.status == MERAWalletTypes.OperationStatus.Vetoed, OperationNotVetoed(operationId));

        require(_roleRank(_coreRole(msg.sender)) >= _roleRank(operation.creatorRole), CannotClearVeto(operationId));

        operation.status = MERAWalletTypes.OperationStatus.Pending;
        emit PendingTransactionVetoCleared(operationId, operation.salt, msg.sender);
    }

    /// @notice Irreversible cancel: unfrozen core controller; uses {_roleRank} (Primary=1 .. Emergency=3). Cancel if caller rank is at most creator rank (stronger or same tier). Refund still goes to the proposer. Agents cannot call.
    function cancelPending(bytes32 operationId) external override whenLifeAlive whenControllerCoreUnfrozen {
        MERAWalletTypes.PendingOperation storage operation = _operations[operationId];
        MERAWalletTypes.RelayOperation storage relayOperation = _relayOperations[operationId];
        require(
            operation.status == MERAWalletTypes.OperationStatus.Pending
                || operation.status == MERAWalletTypes.OperationStatus.Vetoed,
            OperationNotPending(operationId)
        );

        require(
            _roleRank(_coreRole(msg.sender)) <= _roleRank(operation.creatorRole), CannotCancelOperation(operationId)
        );

        _refundRelayReward(operation.creator, relayOperation.relayReward);
        relayOperation.relayReward = 0;
        operation.status = MERAWalletTypes.OperationStatus.Cancelled;
        emit PendingTransactionCancelled(operationId, operation.salt, msg.sender);
    }

    function set1271Signer(address signer) external override onlyEmergencyOrSelf whenLifeAlive {
        _set1271Signer(signer);
    }

    function getRequiredBeforeCheckers() external view override returns (address[] memory) {
        return requiredBeforeCheckers;
    }

    function getRequiredAfterCheckers() external view override returns (address[] memory) {
        return requiredAfterCheckers;
    }

    function isLifeController(address controller) external view override returns (bool) {
        return _isLifeController[controller];
    }

    function operations(bytes32 operationId)
        external
        view
        override
        returns (
            address creator,
            MERAWalletTypes.Role creatorRole,
            uint64 createdAt,
            uint64 executeAfter,
            uint256 salt,
            MERAWalletTypes.OperationStatus status,
            MERAWalletTypes.RelayExecutorPolicy relayPolicy,
            uint256 relayReward,
            address designatedExecutor,
            bytes32 executorSetHash,
            uint64 relayExecuteBefore
        )
    {
        MERAWalletTypes.PendingOperation storage operation = _operations[operationId];
        MERAWalletTypes.RelayOperation storage relayOperation = _relayOperations[operationId];
        return (
            operation.creator,
            operation.creatorRole,
            operation.createdAt,
            operation.executeAfter,
            operation.salt,
            operation.status,
            relayOperation.relayPolicy,
            relayOperation.relayReward,
            relayOperation.designatedExecutor,
            relayOperation.executorSetHash,
            relayOperation.relayExecuteBefore
        );
    }

    function getOperationId(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        external
        view
        override
        returns (bytes32)
    {
        _validateCalls(calls);
        return _computeOperationId(calls, salt);
    }

    function getRequiredDelay(MERAWalletTypes.Call[] calldata calls)
        external
        view
        override
        whenControllerCoreUnfrozen
        returns (uint256)
    {
        _validateCalls(calls);
        return _getRequiredDelay(_coreRole(msg.sender), calls);
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

    function _setTargetCallPolicy(address target, MERAWalletTypes.CallPathPolicy calldata policy) internal {
        MERAWalletTypes.CallPathPolicy memory previousPolicy = callPolicyByTarget[target];
        callPolicyByTarget[target] = policy;
        emit TargetCallPolicyUpdated(target, previousPolicy, policy, msg.sender);
    }

    function _setSelectorCallPolicy(bytes4 selector, MERAWalletTypes.CallPathPolicy calldata policy) internal {
        MERAWalletTypes.CallPathPolicy memory previousPolicy = callPolicyBySelector[selector];
        callPolicyBySelector[selector] = policy;
        emit SelectorCallPolicyUpdated(selector, previousPolicy, policy, msg.sender);
    }

    function _setTargetSelectorCallPolicy(
        address target,
        bytes4 selector,
        MERAWalletTypes.CallPathPolicy calldata policy
    ) internal {
        MERAWalletTypes.CallPathPolicy memory previousPolicy = callPolicyByTargetSelector[target][selector];
        // Pair map: `policy.exists == false` clears the slot; `true` stores `policy` as given.
        if (!policy.exists) {
            require(previousPolicy.exists, NoopTargetSelectorCallPolicy());
            delete callPolicyByTargetSelector[target][selector];
            MERAWalletTypes.CallPathPolicy memory cleared;
            emit TargetSelectorCallPolicyUpdated(target, selector, previousPolicy, cleared, false, msg.sender);
            return;
        }

        callPolicyByTargetSelector[target][selector] = policy;
        emit TargetSelectorCallPolicyUpdated(target, selector, previousPolicy, policy, policy.exists, msg.sender);
    }

    function _setRequiredChecker(address checker, bool enabled) internal {
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
        require(enableBefore || enableAfter, NoopCheckerConfig());

        _setRequiredBeforeChecker(checker, enableBefore);
        _setRequiredAfterChecker(checker, enableAfter);

        emit RequiredCheckerUpdated(checker, enableBefore, enableAfter, msg.sender);
    }

    function _setOptionalChecker(address checker, bool allowed, bytes calldata config) internal {
        if (!allowed) {
            delete whitelistOptionalChecker[checker];
            emit OptionalCheckerUpdated(checker, false, false, false, msg.sender);
            return;
        }

        if (checker != address(0) && config.length > 0) {
            IMERAWalletTransactionChecker(checker).applyConfig(config);
        }

        if (checker == address(0)) {
            whitelistOptionalChecker[checker] =
                MERAWalletTypes.OptionalChecker({allowed: true, enableBefore: false, enableAfter: false});
            emit OptionalCheckerUpdated(checker, true, false, false, msg.sender);
            return;
        }

        (bool enableBefore, bool enableAfter) = IMERAWalletTransactionChecker(checker).hookModes();
        require(enableBefore || enableAfter, NoopCheckerConfig());

        whitelistOptionalChecker[checker] =
            MERAWalletTypes.OptionalChecker({allowed: true, enableBefore: enableBefore, enableAfter: enableAfter});
        emit OptionalCheckerUpdated(checker, true, enableBefore, enableAfter, msg.sender);
    }

    /// @notice Enable or disable a veto agent (may call {vetoPending} on any pending op). Only core controllers may configure.
    /// @dev On enable, `roleLevel` is set to `_coreRole(msg.sender)` so only that role or higher may later disable.
    function _setControllerAgent(address agent, bool enabled) internal {
        MERAWalletTypes.Role callerCore = _coreRole(msg.sender);
        require(callerCore != MERAWalletTypes.Role.None, NotCoreController());
        _requireCoreRoleNotFrozen(callerCore);

        MERAWalletTypes.ControllerAgent storage stored = controllerAgents[agent];

        if (!enabled) {
            require(stored.enabled, NoopControllerAgent());
            require(_roleRank(callerCore) >= _roleRank(stored.roleLevel), AgentRemovalNotAuthorized());
            delete controllerAgents[agent];
            emit ControllerAgentUpdated(agent, false, MERAWalletTypes.Role.None, msg.sender);
            return;
        }

        require(agent != address(0), InvalidAddress());

        stored.enabled = true;
        stored.roleLevel = callerCore;

        emit ControllerAgentUpdated(agent, true, stored.roleLevel, msg.sender);
    }

    function _proposeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        internal
        whenControllerCoreUnfrozen
        returns (bytes32 operationId, MERAWalletTypes.Role callerRole, uint256 executeAfter, uint256 requiredDelay)
    {
        callerRole = _coreRole(msg.sender);

        _validateCalls(calls);

        operationId = _computeOperationId(calls, salt);
        requiredDelay = _getRequiredDelay(callerRole, calls);
        require(requiredDelay != 0, ZeroDelayNotProposable());

        MERAWalletTypes.OperationStatus existing = _operations[operationId].status;
        require(existing == MERAWalletTypes.OperationStatus.None, OperationAlreadyUsed(operationId));

        executeAfter = block.timestamp + requiredDelay;
        _operations[operationId] = MERAWalletTypes.PendingOperation({
            creator: msg.sender,
            creatorRole: callerRole,
            createdAt: uint64(block.timestamp),
            executeAfter: uint64(executeAfter),
            salt: salt,
            status: MERAWalletTypes.OperationStatus.Pending
        });

        _beforePropose(calls, operationId);

        emit TransactionProposed(operationId, salt, msg.sender, callerRole, executeAfter, requiredDelay);
    }

    function _saveRelayOperation(
        bytes32 operationId,
        MERAWalletTypes.RelayProposeConfig calldata relayConfig,
        uint256 relayReward
    ) internal {
        _relayOperations[operationId] =
            MERAWalletTypes.RelayOperation({
                relayPolicy: relayConfig.relayPolicy,
                relayReward: relayReward,
                designatedExecutor: relayConfig.designatedExecutor,
                executorSetHash: relayConfig.executorSetHash,
                relayExecuteBefore: relayConfig.relayExecuteBefore
            });
        emit RelayOperationSaved(
            operationId,
            relayConfig.relayPolicy,
            relayReward,
            relayConfig.designatedExecutor,
            relayConfig.executorSetHash,
            relayConfig.relayExecuteBefore
        );
    }

    function _executePending(MERAWalletTypes.Call[] calldata calls, uint256 salt, address[] memory executorWhitelist)
        internal
    {
        _validateCalls(calls);

        bytes32 operationId = _computeOperationId(calls, salt);
        MERAWalletTypes.PendingOperation storage operation = _operations[operationId];
        MERAWalletTypes.RelayOperation storage relayOperation = _relayOperations[operationId];

        require(operation.status == MERAWalletTypes.OperationStatus.Pending, OperationNotPending(operationId));
        require(block.timestamp >= operation.executeAfter, TimelockNotExpired(operation.executeAfter, block.timestamp));
        _requireRelayExecutionNotExpired(relayOperation);

        if (relayOperation.relayPolicy == MERAWalletTypes.RelayExecutorPolicy.CoreExecute) {
            require(executorWhitelist.length == 0, InvalidExecutorWhitelist());
            _requireControllerCoreUnfrozen();
        } else {
            require(!_isCoreController(msg.sender), CoreExecutorNotAllowed(msg.sender));
            _validateRelayExecutor(relayOperation, executorWhitelist);
        }

        operation.status = MERAWalletTypes.OperationStatus.Executed;

        _executeCallsWithHooks(calls, operationId);
        _payoutRelayReward(relayOperation);

        emit PendingTransactionExecuted(operationId, salt, msg.sender);
    }

    /// @dev Runs before/after hooks and the external call for each entry in order so checkers observe post-state incrementally.
    function _executeCallsWithHooks(MERAWalletTypes.Call[] calldata calls, bytes32 operationId) internal {
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength;) {
            MERAWalletTypes.Call calldata callData = calls[i];
            _beforeExecute(callData, operationId, i);
            (bool success, bytes memory result) = callData.target.call{value: callData.value}(callData.data);
            require(success, CallExecutionFailed(i, result));
            _afterExecute(callData, operationId, i);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Same as { _executeCallsWithHooks } for batches built in memory (extensions).
    function _executeCallsWithHooksWithCallsMemory(MERAWalletTypes.Call[] memory calls, bytes32 operationId) internal {
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength;) {
            MERAWalletTypes.Call memory callData = calls[i];
            _beforeExecuteWithCallMemory(callData, operationId, i);
            (bool success, bytes memory result) = callData.target.call{value: callData.value}(callData.data);
            require(success, CallExecutionFailed(i, result));
            _afterExecuteWithCallMemory(callData, operationId, i);
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
            _addChecker(requiredBeforeCheckers, _requiredBeforeIndexPlusOne, checker);
            return;
        }
        _removeChecker(requiredBeforeCheckers, _requiredBeforeIndexPlusOne, checker);
    }

    function _setRequiredAfterChecker(address checker, bool enabled) internal {
        bool current = _requiredAfterIndexPlusOne[checker] != 0;
        if (current == enabled) {
            return;
        }

        if (enabled) {
            _addChecker(requiredAfterCheckers, _requiredAfterIndexPlusOne, checker);
            return;
        }
        _removeChecker(requiredAfterCheckers, _requiredAfterIndexPlusOne, checker);
    }

    function _addChecker(
        address[] storage checkerList,
        mapping(address checker => uint256) storage indexMap,
        address checker
    ) internal {
        require(
            checkerList.length < MERAWalletConstants.MAX_REQUIRED_CHECKERS_PER_LIST,
            TooManyRequiredCheckers(checkerList.length + 1, MERAWalletConstants.MAX_REQUIRED_CHECKERS_PER_LIST)
        );
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

    function _setLifeController(address controller, bool enabled, address caller) internal {
        bool current = _isLifeController[controller];
        if (current == enabled) {
            return;
        }

        if (enabled) {
            _isLifeController[controller] = true;
            emit LifeControllerUpdated(controller, true, caller);
            return;
        }

        _isLifeController[controller] = false;
        emit LifeControllerUpdated(controller, false, caller);
    }

    function _invokeBeforeRequiredCheckers(MERAWalletTypes.Call calldata callData, bytes32 operationId, uint256 callId)
        internal
    {
        uint256 checkersLength = requiredBeforeCheckers.length;
        if (checkersLength == 0) {
            return;
        }
        for (uint256 i = 0; i < checkersLength;) {
            IMERAWalletTransactionChecker(requiredBeforeCheckers[i]).checkBefore(callData, operationId, callId);
            unchecked {
                ++i;
            }
        }
    }

    function _invokeAfterRequiredCheckers(MERAWalletTypes.Call calldata callData, bytes32 operationId, uint256 callId)
        internal
    {
        uint256 checkersLength = requiredAfterCheckers.length;
        if (checkersLength == 0) {
            return;
        }
        for (uint256 i = 0; i < checkersLength;) {
            IMERAWalletTransactionChecker(requiredAfterCheckers[i]).checkAfter(callData, operationId, callId);
            unchecked {
                ++i;
            }
        }
    }

    function _invokeBeforeOptionalChecker(MERAWalletTypes.Call calldata callData, bytes32 operationId, uint256 callId)
        internal
    {
        address checker = callData.checker;
        if (checker == address(0) || !whitelistOptionalChecker[checker].enableBefore) {
            return;
        }
        IMERAWalletTransactionChecker(checker).checkBefore(callData, operationId, callId);
    }

    function _invokeAfterOptionalChecker(MERAWalletTypes.Call calldata callData, bytes32 operationId, uint256 callId)
        internal
    {
        address checker = callData.checker;
        if (checker == address(0) || !whitelistOptionalChecker[checker].enableAfter) {
            return;
        }
        IMERAWalletTransactionChecker(checker).checkAfter(callData, operationId, callId);
    }

    function _invokeBeforeRequiredCheckersWithCallMemory(
        MERAWalletTypes.Call memory callData,
        bytes32 operationId,
        uint256 callId
    ) internal {
        uint256 checkersLength = requiredBeforeCheckers.length;
        if (checkersLength == 0) {
            return;
        }
        for (uint256 i = 0; i < checkersLength;) {
            IMERAWalletTransactionChecker(requiredBeforeCheckers[i]).checkBefore(callData, operationId, callId);
            unchecked {
                ++i;
            }
        }
    }

    function _invokeAfterRequiredCheckersWithCallMemory(
        MERAWalletTypes.Call memory callData,
        bytes32 operationId,
        uint256 callId
    ) internal {
        uint256 checkersLength = requiredAfterCheckers.length;
        if (checkersLength == 0) {
            return;
        }
        for (uint256 i = 0; i < checkersLength;) {
            IMERAWalletTransactionChecker(requiredAfterCheckers[i]).checkAfter(callData, operationId, callId);
            unchecked {
                ++i;
            }
        }
    }

    function _invokeBeforeOptionalCheckerWithCallMemory(
        MERAWalletTypes.Call memory callData,
        bytes32 operationId,
        uint256 callId
    ) internal {
        address checker = callData.checker;
        if (checker == address(0) || !whitelistOptionalChecker[checker].enableBefore) {
            return;
        }
        IMERAWalletTransactionChecker(checker).checkBefore(callData, operationId, callId);
    }

    function _invokeAfterOptionalCheckerWithCallMemory(
        MERAWalletTypes.Call memory callData,
        bytes32 operationId,
        uint256 callId
    ) internal {
        address checker = callData.checker;
        if (checker == address(0) || !whitelistOptionalChecker[checker].enableAfter) {
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

    function _payoutRelayReward(MERAWalletTypes.RelayOperation storage relayOperation) internal {
        uint256 reward = relayOperation.relayReward;
        if (reward == 0) {
            return;
        }

        relayOperation.relayReward = 0;
        _transferReward(payable(msg.sender), reward);
    }

    function _refundRelayReward(address recipient, uint256 reward) internal {
        if (reward == 0) {
            return;
        }
        _transferReward(payable(recipient), reward);
    }

    function _transferReward(address payable recipient, uint256 amount) internal {
        (bool success,) = recipient.call{value: amount}("");
        require(success, RelayRewardTransferFailed(recipient, amount));
    }
    function _beforePropose(MERAWalletTypes.Call[] calldata calls, bytes32 operationId) internal virtual {}

    /// @dev Hook for extension batches built in memory (`MERAWalletMemoryBatches`); default no-op.
    function _beforeProposeWithCallsMemory(MERAWalletTypes.Call[] memory calls, bytes32 operationId) internal virtual {}

    function _beforeExecute(MERAWalletTypes.Call calldata callData, bytes32 operationId, uint256 callId)
        internal
        virtual
    {
        _invokeBeforeRequiredCheckers(callData, operationId, callId);
        _invokeBeforeOptionalChecker(callData, operationId, callId);
    }

    function _beforeExecuteWithCallMemory(MERAWalletTypes.Call memory callData, bytes32 operationId, uint256 callId)
        internal
        virtual
    {
        _invokeBeforeRequiredCheckersWithCallMemory(callData, operationId, callId);
        _invokeBeforeOptionalCheckerWithCallMemory(callData, operationId, callId);
    }

    function _afterExecute(MERAWalletTypes.Call calldata callData, bytes32 operationId, uint256 callId)
        internal
        virtual
    {
        _invokeAfterRequiredCheckers(callData, operationId, callId);
        _invokeAfterOptionalChecker(callData, operationId, callId);
    }

    function _afterExecuteWithCallMemory(MERAWalletTypes.Call memory callData, bytes32 operationId, uint256 callId)
        internal
        virtual
    {
        _invokeAfterRequiredCheckersWithCallMemory(callData, operationId, callId);
        _invokeAfterOptionalCheckerWithCallMemory(callData, operationId, callId);
    }

    function _onlyEmergencyOrSelf() internal view {
        require(msg.sender == address(this) || (GUARDIAN == address(0) && msg.sender == emergency), NotEmergency());
    }

    function _requireControllerCoreUnfrozen() internal view {
        _requireNotSafeMode();
        MERAWalletTypes.Role callerRole = _requireController();
        _requireCoreRoleNotFrozen(callerRole);
    }

    function _requireNotSafeMode() internal view {
        if (safeModeBefore != 0) {
            require(block.timestamp > safeModeBefore, SafeModeActive(safeModeBefore));
        }
    }

    function _validateCalls(MERAWalletTypes.Call[] calldata calls) internal view {
        require(calls.length > 0, EmptyCalls());
        require(
            calls.length <= MERAWalletConstants.MAX_CALLS_PER_BATCH,
            TooManyCalls(calls.length, MERAWalletConstants.MAX_CALLS_PER_BATCH)
        );
        _validateCallWhitelist(calls);
    }

    /// @dev Same bytes as `abi.encode(chainId, wallet, calls, salt)`; `keccak256` runs over the length-prefixed buffer in assembly (matches high-level `keccak256(bytes)` hashing).
    function _computeOperationId(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        internal
        view
        returns (bytes32 id)
    {
        bytes memory preimage = abi.encode(block.chainid, address(this), calls, salt);
        assembly ("memory-safe") {
            id := keccak256(add(preimage, 32), mload(preimage))
        }
    }

    function _getRequiredDelay(MERAWalletTypes.Role callerRole, MERAWalletTypes.Call[] calldata calls)
        internal
        view
        returns (uint256 requiredDelay)
    {
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

    /// @dev Required delay for one call: if a (target, selector) pair policy is configured, use only that slice (zero role delay => 0);
    ///      else if both target and selector policies have `exists == false`, use `globalTimelock`; otherwise max(target, selector) delays.
    ///      Reverts if path forbidden for role.
    /// @dev Emergency uses the **backup** policy slice (no Emergency dimension in `CallPathPolicy`); self-calls that
    ///      only adjust wallet config may be exempt — see `_isEmergencyTimelockExemptSelfCall`.
    function _getCallDelay(MERAWalletTypes.Role callerRole, MERAWalletTypes.Call calldata callData)
        internal
        view
        returns (uint256)
    {
        if (callerRole == MERAWalletTypes.Role.Emergency) {
            if (_isEmergencyTimelockExemptSelfCall(callData)) {
                return 0;
            }
            return _getCallDelayForPolicyRole(MERAWalletTypes.Role.Backup, callData.target, callData.data);
        }
        return _getCallDelayForPolicyRole(callerRole, callData.target, callData.data);
    }

    /// @notice Delay from call policies for Primary or Backup (same slice as used for Emergency when not exempt).
    function _getCallDelayForPolicyRole(MERAWalletTypes.Role policyRole, address target, bytes calldata data)
        internal
        view
        returns (uint256)
    {
        return _getCallDelayForPolicyRoleFromSelector(policyRole, target, _extractSelectorFromCalldataBytes(data));
    }

    function _getCallDelayForPolicyRoleFromSelector(MERAWalletTypes.Role policyRole, address target, bytes4 selector)
        internal
        view
        returns (uint256)
    {
        MERAWalletTypes.CallPathPolicy memory pairPolicy = callPolicyByTargetSelector[target][selector];
        if (pairPolicy.exists) {
            MERAWalletTypes.RoleCallPolicy memory pairRole = _rolePolicySlice(pairPolicy, policyRole);
            require(!pairRole.forbidden, CallPathForbiddenForRole(policyRole));
            return uint256(pairRole.delay);
        }

        MERAWalletTypes.CallPathPolicy memory targetPolicy = callPolicyByTarget[target];
        MERAWalletTypes.CallPathPolicy memory selectorPolicy = callPolicyBySelector[selector];

        if (!targetPolicy.exists && !selectorPolicy.exists) {
            return globalTimelock;
        }

        MERAWalletTypes.RoleCallPolicy memory targetRole = _rolePolicySlice(targetPolicy, policyRole);
        MERAWalletTypes.RoleCallPolicy memory selectorRole = _rolePolicySlice(selectorPolicy, policyRole);

        require(!targetRole.forbidden && !selectorRole.forbidden, CallPathForbiddenForRole(policyRole));

        uint256 a = uint256(targetRole.delay);
        uint256 b = uint256(selectorRole.delay);
        return a > b ? a : b;
    }

    /// @dev Zero extra delay for emergency-driven self-calls that only reconfigure the wallet (role / freeze / policies / life).
    function _isEmergencyTimelockExemptSelfCall(MERAWalletTypes.Call calldata callData) internal view returns (bool) {
        if (callData.target != address(this)) {
            return false;
        }
        return _isEmergencyConfigSelector(_extractSelectorFromCalldataBytes(callData.data));
    }

    function _requireLifeAliveForStateChanges() internal view {
        if (!lifeControlEnabled) {
            return;
        }

        require(
            lastLifeHeartbeatAt != 0 && block.timestamp <= lastLifeHeartbeatAt + lifeHeartbeatTimeout,
            LifeHeartbeatExpired(lastLifeHeartbeatAt, lifeHeartbeatTimeout, block.timestamp)
        );
    }

    function _validateCallWhitelist(MERAWalletTypes.Call[] calldata calls) internal view {
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength;) {
            address checker = calls[i].checker;
            require(whitelistOptionalChecker[checker].allowed, OptionalCheckerNotAllowed(checker, i));
            unchecked {
                ++i;
            }
        }
    }

    function _requireController() internal view returns (MERAWalletTypes.Role role) {
        role = _coreRole(msg.sender);
        require(role != MERAWalletTypes.Role.None, Unauthorized());
    }

    /// @dev Core role must not be frozen for this action; Emergency and None pass without revert.
    function _requireCoreRoleNotFrozen(MERAWalletTypes.Role role) internal view {
        require(role != MERAWalletTypes.Role.Primary || !frozenPrimary, RoleFrozen(MERAWalletTypes.Role.Primary));
        require(role != MERAWalletTypes.Role.Backup || !frozenBackup, RoleFrozen(MERAWalletTypes.Role.Backup));
    }

    /// @dev Current emergency or optional guardian may rotate the emergency address.
    function _canSetEmergency(address caller) internal view returns (bool) {
        if (caller == emergency) {
            return true;
        }
        if (GUARDIAN != address(0) && caller == GUARDIAN) {
            return true;
        }
        return false;
    }

    function _validateRelayExecutor(
        MERAWalletTypes.RelayOperation storage relayOperation,
        address[] memory executorWhitelist
    ) internal view {
        if (relayOperation.relayPolicy == MERAWalletTypes.RelayExecutorPolicy.Anyone) {
            require(executorWhitelist.length == 0, InvalidExecutorWhitelist());
            return;
        }

        if (relayOperation.relayPolicy == MERAWalletTypes.RelayExecutorPolicy.Designated) {
            require(executorWhitelist.length == 0, InvalidExecutorWhitelist());
            require(msg.sender == relayOperation.designatedExecutor, RelayExecutorNotAllowed(msg.sender));
            return;
        }

        if (relayOperation.relayPolicy == MERAWalletTypes.RelayExecutorPolicy.Whitelist) {
            require(
                relayOperation.executorSetHash == keccak256(abi.encode(executorWhitelist)), InvalidExecutorWhitelist()
            );
            uint256 whitelistLength = executorWhitelist.length;
            for (uint256 i = 0; i < whitelistLength;) {
                if (executorWhitelist[i] == msg.sender) {
                    return;
                }
                unchecked {
                    ++i;
                }
            }
            revert RelayExecutorNotAllowed(msg.sender);
        }

        revert InvalidRelayConfig();
    }

    function _isCoreController(address account) internal view returns (bool) {
        return _coreRole(account) != MERAWalletTypes.Role.None;
    }

    /// @dev Role from the wallet's fixed controller addresses only (ignores controller agent mapping).
    /// Checks are ordered Emergency → Backup → Primary (same precedence as {_roleRank}).
    function _coreRole(address account) internal view returns (MERAWalletTypes.Role) {
        if (account == emergency) {
            return MERAWalletTypes.Role.Emergency;
        }
        if (account == backup) {
            return MERAWalletTypes.Role.Backup;
        }
        if (account == primary) {
            return MERAWalletTypes.Role.Primary;
        }
        return MERAWalletTypes.Role.None;
    }

    function _isEmergencyConfigSelector(bytes4 selector) internal pure returns (bool) {
        // Compare against IBaseMERAWallet so selectors stay aligned with the external API.
        return selector == IBaseMERAWallet.setPrimary.selector || selector == IBaseMERAWallet.setBackup.selector
            || selector == IBaseMERAWallet.setEmergency.selector
            || selector == IBaseMERAWallet.setGlobalTimelock.selector
            || selector == IBaseMERAWallet.setLifeControl.selector
            || selector == IBaseMERAWallet.setLifeControllers.selector
            || selector == IBaseMERAWallet.setTargetCallPolicies.selector
            || selector == IBaseMERAWallet.setSelectorCallPolicies.selector
            || selector == IBaseMERAWallet.setTargetSelectorCallPolicies.selector
            || selector == IBaseMERAWallet.setRequiredCheckers.selector
            || selector == IBaseMERAWallet.setOptionalCheckers.selector
            || selector == IBaseMERAWallet.setControllerAgents.selector
            || selector == IBaseMERAWallet.setFrozenPrimary.selector
            || selector == IBaseMERAWallet.setFrozenBackup.selector
            || selector == IBaseMERAWallet.set1271Signer.selector;
    }

    function _rolePolicySlice(MERAWalletTypes.CallPathPolicy memory policy, MERAWalletTypes.Role callerRole)
        internal
        pure
        returns (MERAWalletTypes.RoleCallPolicy memory)
    {
        require(callerRole == MERAWalletTypes.Role.Primary || callerRole == MERAWalletTypes.Role.Backup, InvalidRole());
        if (callerRole == MERAWalletTypes.Role.Primary) {
            return policy.primary;
        }
        return policy.backup;
    }

    // Consider refactoring low-level helpers (bytes selector reads, ECDSA, etc.) to Solady where it fits.
    function _extractSelectorFromCalldataBytes(bytes calldata data) internal pure returns (bytes4 selector) {
        if (data.length < MERAWalletConstants.FUNCTION_SELECTOR_LENGTH) {
            return bytes4(0);
        }
        return bytes4(data[0:4]);
    }

    /// @dev OpenZeppelin ECDSA on calldata; zero address on invalid signature (no revert, for EIP-1271).
    function _recoverSigner(bytes32 hash, bytes calldata signature) internal pure returns (address) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecoverCalldata(hash, signature);
        if (err != ECDSA.RecoverError.NoError) {
            return address(0);
        }
        return recovered;
    }

    /// @dev When `relayExecuteBefore` is non-zero, pending execution must happen on or before that timestamp (after timelock).
    function _requireRelayExecutionNotExpired(MERAWalletTypes.RelayOperation storage relayOperation) internal view {
        uint64 before = relayOperation.relayExecuteBefore;
        if (before != 0) {
            require(block.timestamp <= before, RelayExecutionExpired(before, uint256(block.timestamp)));
        }
    }

    function _validateRelayConfig(MERAWalletTypes.RelayProposeConfig calldata relayConfig, uint256 relayReward)
        internal
        pure
    {
        require(relayConfig.relayExecuteBefore != 0, RelayDeadlineRequired());

        if (relayConfig.relayPolicy == MERAWalletTypes.RelayExecutorPolicy.CoreExecute) {
            require(relayReward == 0, RelayRewardNotAllowed());
            require(
                relayConfig.designatedExecutor == address(0) && relayConfig.executorSetHash == bytes32(0),
                InvalidRelayConfig()
            );
            return;
        }

        require(relayReward != 0, RelayRewardRequired());

        if (relayConfig.relayPolicy == MERAWalletTypes.RelayExecutorPolicy.Anyone) {
            require(
                relayConfig.designatedExecutor == address(0) && relayConfig.executorSetHash == bytes32(0),
                InvalidRelayConfig()
            );
            return;
        }
        if (relayConfig.relayPolicy == MERAWalletTypes.RelayExecutorPolicy.Designated) {
            require(
                relayConfig.designatedExecutor != address(0) && relayConfig.executorSetHash == bytes32(0),
                InvalidRelayConfig()
            );
            return;
        }
        if (relayConfig.relayPolicy == MERAWalletTypes.RelayExecutorPolicy.Whitelist) {
            require(
                relayConfig.designatedExecutor == address(0) && relayConfig.executorSetHash != bytes32(0),
                InvalidRelayConfig()
            );
            return;
        }

        revert InvalidRelayConfig();
    }

    /// @dev Numeric rank: Primary < Backup < Emergency (see {MERAWalletConstants}). Used for agent caps and for {cancelPending}/{clearVeto} (lower number = stronger wallet authority).
    function _roleRank(MERAWalletTypes.Role role) internal pure returns (uint256) {
        if (role == MERAWalletTypes.Role.Emergency) {
            return MERAWalletConstants.ROLE_RANK_EMERGENCY;
        }
        if (role == MERAWalletTypes.Role.Backup) {
            return MERAWalletConstants.ROLE_RANK_BACKUP;
        }
        if (role == MERAWalletTypes.Role.Primary) {
            return MERAWalletConstants.ROLE_RANK_PRIMARY;
        }
        return MERAWalletConstants.ROLE_RANK_NONE;
    }
}
