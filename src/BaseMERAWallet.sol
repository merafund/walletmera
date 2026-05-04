// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletConstants} from "./constants/MERAWalletConstants.sol";
import {MERAWalletTypes} from "./types/MERAWalletTypes.sol";
import {IBaseMERAWallet} from "./interfaces/IBaseMERAWallet.sol";
import {IBaseMERAWalletErrors} from "./interfaces/IBaseMERAWalletErrors.sol";
import {IBaseMERAWalletEvents} from "./interfaces/IBaseMERAWalletEvents.sol";
import {IMERAWalletLoginRegistryMigration} from "./interfaces/IMERAWalletLoginRegistryMigration.sol";
import {IMERAWalletTransactionChecker} from "./interfaces/checkers/IMERAWalletTransactionChecker.sol";
import {IMigrationCalls} from "./interfaces/external/IMigrationCalls.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract BaseMERAWallet is IBaseMERAWallet, IBaseMERAWalletEvents, IBaseMERAWalletErrors, ReentrancyGuard {
    address public primary;
    address public backup;
    address public emergency;
    address public guardian;
    address public eip1271Signer;

    mapping(MERAWalletTypes.Role role => uint256 delay) public roleTimelock;
    uint256 public emergencyAgentLifetime;
    uint256 public lifeHeartbeatTimeout;
    uint256 public lastLifeHeartbeatAt;
    bool public lifeControlEnabled;
    uint256 public pendingTransactionsCount;
    uint256 public pendingTransactionsInvalidBefore;
    bool public frozenPrimary;
    bool public frozenBackup;
    uint256 public safeModeBefore;
    bool public safeModeUsed;
    address public migrationTarget;
    mapping(address target => MERAWalletTypes.CallPathPolicy policy) public callPolicyByTarget;
    mapping(bytes4 selector => MERAWalletTypes.CallPathPolicy policy) public callPolicyBySelector;
    mapping(address target => mapping(bytes4 selector => MERAWalletTypes.CallPathPolicy policy)) public
        callPolicyByTargetSelector;
    mapping(bytes32 operationId => MERAWalletTypes.PendingOperation operation) internal _operations;
    mapping(bytes32 operationId => MERAWalletTypes.RelayOperation relayOperation) internal _relayOperations;
    mapping(address checker => MERAWalletTypes.OptionalChecker) public whitelistOptionalChecker;
    mapping(address agent => MERAWalletTypes.Agent) public agents;

    address[] internal requiredBeforeCheckers;
    address[] internal requiredAfterCheckers;

    mapping(address checker => uint256 indexPlusOne) internal _requiredBeforeIndexPlusOne;
    mapping(address checker => uint256 indexPlusOne) internal _requiredAfterIndexPlusOne;
    mapping(address controller => bool) internal _isLifeController;

    /// @dev Only self-calls (e.g. batched execute) may reach gated config.
    modifier onlySelf() {
        _onlySelf();
        _;
    }

    /// @dev Self-call where the effective caller must hold core `Emergency` (same transient context as {setEmergency}).
    modifier onlySelfAsEmergency() {
        _onlySelfAsEmergency();
        _;
    }

    modifier whenLifeAlive() {
        _requireLifeAliveForStateChanges();
        _;
    }

    /// @dev Caller must be a core controller and not blocked for their role.
    modifier whenControllerCoreAvailable() {
        _requireControllerCoreAvailable();
        _;
    }

    constructor(
        address initialPrimary,
        address initialBackup,
        address initialEmergency,
        address initialSigner,
        address initialGuardian
    ) {
        _initialize(initialPrimary, initialBackup, initialEmergency, initialSigner, initialGuardian);
    }

    receive() external payable override {}

    function initializeFromImmutableArgs() external override {
        require(primary == address(0), AlreadyInitialized());
        MERAWalletTypes.WalletInitParams memory params =
            abi.decode(Clones.fetchCloneArgs(address(this)), (MERAWalletTypes.WalletInitParams));
        _initialize(
            params.initialPrimary,
            params.initialBackup,
            params.initialEmergency,
            params.initialSigner,
            params.initialGuardian
        );
    }

    function setPrimary(address newPrimary) external override onlySelf whenLifeAlive {
        require(newPrimary != address(0), InvalidAddress());

        _requireControllerCoreAvailable();

        address previousPrimary = primary;
        primary = newPrimary;
        if (eip1271Signer == previousPrimary) {
            _set1271Signer(newPrimary);
        }
        emit PrimaryUpdated(previousPrimary, newPrimary, _effectiveCaller());
    }

    function setBackup(address newBackup) external override onlySelf whenLifeAlive {
        require(newBackup != address(0), InvalidAddress());

        MERAWalletTypes.Role callerRole = _requireControllerCoreAvailable();

        require(
            callerRole == MERAWalletTypes.Role.Backup || callerRole == MERAWalletTypes.Role.Emergency,
            NotAllowedRoleChange()
        );

        address previousBackup = backup;
        backup = newBackup;
        if (eip1271Signer == previousBackup) {
            _set1271Signer(newBackup);
        }
        emit BackupUpdated(previousBackup, newBackup, _effectiveCaller());
    }

    function setEmergency(address newEmergency) external override {
        address caller;
        bool calledByGuardian = guardian != address(0) && msg.sender == guardian;
        if (calledByGuardian) {
            caller = msg.sender;
        } else {
            _onlySelfAsEmergency();
            caller = _effectiveCaller();
        }
        require(newEmergency != address(0), InvalidAddress());

        address previousEmergency = emergency;
        emergency = newEmergency;
        bool emergencyChanged = previousEmergency != newEmergency;
        if (emergencyChanged) {
            _setLifeController(previousEmergency, false, caller);
            _setLifeController(newEmergency, true, caller);
            _invalidatePendingTransactions(caller);
        }
        if (eip1271Signer == previousEmergency) {
            _set1271Signer(newEmergency);
        }
        if (calledByGuardian && emergencyChanged) {
            _clearSafeMode(msg.sender);
        }
        emit EmergencyUpdated(previousEmergency, newEmergency, caller);
    }

    /// @notice Rotates the optional guardian address; address(0) disables guardian-only paths.
    /// @dev Only the Emergency core role may rotate guardian; self-calls set the role in transient storage.
    function setGuardian(address newGuardian) external override onlySelfAsEmergency whenLifeAlive {
        address previousGuardian = guardian;
        guardian = newGuardian;
        emit GuardianUpdated(previousGuardian, newGuardian, msg.sender);
    }

    function setRoleTimelock(MERAWalletTypes.Role role, uint256 delay) external override onlySelf whenLifeAlive {
        require(role != MERAWalletTypes.Role.None, InvalidRole());
        require(
            delay <= MERAWalletConstants.MAX_TIMELOCK_DELAY,
            TimelockDelayTooLarge(delay, MERAWalletConstants.MAX_TIMELOCK_DELAY)
        );
        MERAWalletTypes.Role callerRole = _requireControllerCoreAvailable();
        // `{_roleRank}` increases Primary→Emergency; caller rank must be >= the slot role (Emergency may update any slot).
        require(_roleRank(callerRole) >= _roleRank(role), RoleTimelockChangeNotAuthorized(callerRole, role));
        uint256 previousDelay = roleTimelock[role];
        roleTimelock[role] = delay;
        emit RoleTimelockUpdated(role, previousDelay, delay, _effectiveCaller());
    }

    function setEmergencyAgentLifetime(uint256 lifetime) external override onlySelf whenLifeAlive {
        require(
            lifetime <= MERAWalletConstants.MAX_EMERGENCY_AGENT_LIFETIME,
            EmergencyAgentLifetimeTooLarge(lifetime, MERAWalletConstants.MAX_EMERGENCY_AGENT_LIFETIME)
        );
        _onlySelfAsEmergency();
        uint256 previousLifetime = emergencyAgentLifetime;
        emergencyAgentLifetime = lifetime;
        emit EmergencyAgentLifetimeUpdated(previousLifetime, lifetime, _effectiveCaller());
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
        onlySelfAsEmergency
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
        onlySelfAsEmergency
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
    ) external override onlySelfAsEmergency whenLifeAlive {
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

    function setRequiredCheckers(MERAWalletTypes.RequiredCheckerUpdate[] calldata updates)
        external
        override
        onlySelfAsEmergency
        whenLifeAlive
    {
        uint256 n = updates.length;
        for (uint256 i = 0; i < n;) {
            MERAWalletTypes.RequiredCheckerUpdate calldata u = updates[i];
            _setRequiredChecker(u.checker, u.enabled, u.config);
            unchecked {
                ++i;
            }
        }
    }

    function setOptionalCheckers(MERAWalletTypes.OptionalCheckerUpdate[] calldata updates)
        external
        override
        onlySelfAsEmergency
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

    function setAgents(address[] calldata agentAddresses, MERAWalletTypes.Role[] calldata roleLevels)
        external
        override
        onlySelf
        whenLifeAlive
    {
        uint256 n = agentAddresses.length;
        require(n == roleLevels.length, ArrayLengthMismatch(n, roleLevels.length));
        for (uint256 i = 0; i < n;) {
            _setAgent(agentAddresses[i], roleLevels[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Same-or-higher agents/core controllers may freeze. Only strictly higher core controllers may unfreeze. Guardian may freeze only.
    function setFrozenPrimary(bool frozen) external override {
        _setFrozenRole(MERAWalletTypes.Role.Primary, frozen);
    }

    /// @dev Same-or-higher agents/core controllers may freeze. Only strictly higher core controllers may unfreeze. Guardian may freeze only.
    function setFrozenBackup(bool frozen) external override {
        _setFrozenRole(MERAWalletTypes.Role.Backup, frozen);
    }

    function enterSafeMode(uint256 duration) external override {
        require(
            msg.sender == emergency || (guardian != address(0) && msg.sender == guardian)
                || _agentRole(msg.sender) == MERAWalletTypes.Role.Emergency,
            SafeModeNotAuthorized()
        );
        // Re-entry is allowed once the active window is cleared (deadline zeroed), even if {safeModeUsed} stays true until {resetSafeMode}.
        require(!(safeModeUsed && safeModeBefore != 0), SafeModeAlreadyUsed());
        require(
            duration >= MERAWalletConstants.SAFE_MODE_MIN_DURATION
                && duration <= MERAWalletConstants.SAFE_MODE_MAX_DURATION,
            SafeModeDurationOutOfRange(duration)
        );

        // Common emergency-agent window is extended for all agents (expiry = activeFrom + this value).
        emergencyAgentLifetime += duration;

        _startEmergencyAgentLifetimeIfNeeded(msg.sender);

        safeModeUsed = true;
        safeModeBefore = block.timestamp + duration;
        emit SafeModeEntered(safeModeBefore, msg.sender);
    }

    function resetSafeMode() external override onlySelfAsEmergency {
        require(safeModeUsed, SafeModeNotUsed());
        require(block.timestamp > safeModeBefore, SafeModeStillActive(safeModeBefore));

        safeModeUsed = false;
        safeModeBefore = 0;
        emit SafeModeReset(_effectiveCaller());
    }

    function setMigrationTarget(address target) external override onlySelfAsEmergency {
        address previous = migrationTarget;
        migrationTarget = target;
        emit MigrationTargetUpdated(previous, target, _effectiveCaller());
    }

    /// @notice Invalidates pending transactions created before the current timestamp and resets the pending counter.
    function invalidatePendingTransactionsBeforeCurrentTimestamp() external override onlySelf whenLifeAlive {
        _invalidatePendingTransactions(_effectiveCaller());
    }

    function executeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        external
        payable
        override
        whenLifeAlive
        nonReentrant
    {
        MERAWalletTypes.Role callerRole = _requireControllerCoreAvailable();
        _validateCalls(calls);

        bytes32 operationId = _computeOperationId(calls, salt);
        uint256 requiredDelay = _getRequiredDelay(callerRole, calls);

        require(requiredDelay == 0, TimelockRequired(requiredDelay));

        _executeCallsWithHooks(calls, operationId, _effectiveCaller(), callerRole);

        emit ImmediateTransactionExecuted(operationId, salt, msg.sender);
    }

    function executeMigrationTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        external
        payable
        override
        whenLifeAlive
        whenControllerCoreAvailable
        nonReentrant
    {
        require(_coreRole(msg.sender) != MERAWalletTypes.Role.None, Unauthorized());
        require(migrationTarget != address(0), MigrationModeNotActive());
        _validateMigrationCalls(calls);

        bytes32 operationId = _computeOperationId(calls, salt);
        uint256 n = calls.length;
        for (uint256 i = 0; i < n;) {
            MERAWalletTypes.Call calldata c = calls[i];
            (bool success, bytes memory result) = c.target.call{value: c.value}(c.data);
            require(success, CallExecutionFailed(i, result));
            unchecked {
                ++i;
            }
        }
        emit MigrationTransactionExecuted(operationId, salt, msg.sender);
    }

    function proposeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        external
        override
        whenLifeAlive
        nonReentrant
        returns (bytes32 operationId)
    {
        MERAWalletTypes.Role callerRole = _requireControllerCoreAvailable();
        (operationId,) = _proposeTransaction(calls, salt, callerRole);
    }

    function proposeTransactionWithRelay(
        MERAWalletTypes.Call[] calldata calls,
        uint256 salt,
        MERAWalletTypes.RelayProposeConfig calldata relayConfig
    ) external payable override whenLifeAlive nonReentrant returns (bytes32 operationId) {
        MERAWalletTypes.Role callerRole = _requireControllerCoreAvailable();
        _validateRelayConfig(relayConfig, msg.value);

        uint256 executeAfter;
        (operationId, executeAfter) = _proposeTransaction(calls, salt, callerRole);
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
        whenControllerCoreAvailable
        nonReentrant
    {
        _executePending(calls, salt, new address[](0));
    }

    function executePending(MERAWalletTypes.Call[] calldata calls, uint256 salt, address[] calldata executorWhitelist)
        external
        payable
        override
        whenLifeAlive
        whenControllerCoreAvailable
        nonReentrant
    {
        _executePending(calls, salt, executorWhitelist);
    }

    /// @notice Veto pending ops: same-or-higher agents/core controllers may veto.
    function vetoPending(bytes32 operationId) external override {
        MERAWalletTypes.PendingOperation storage operation = _operations[operationId];
        require(operation.status == MERAWalletTypes.OperationStatus.Pending, OperationNotPending(operationId));

        require(_isRankedRoleActionAllowed(operation.creatorRole, true), CannotVetoOperation(operationId));

        _startEmergencyAgentLifetimeIfNeeded(msg.sender);

        operation.status = MERAWalletTypes.OperationStatus.Vetoed;
        emit PendingTransactionVetoed(operationId, operation.salt, msg.sender);
    }

    /// @notice Resume a vetoed timelock op: unfrozen core controller strictly above the creator role.
    function clearVeto(bytes32 operationId) external override whenLifeAlive {
        MERAWalletTypes.Role callerRole = _requireControllerCoreAvailable();
        MERAWalletTypes.PendingOperation storage operation = _operations[operationId];
        require(operation.status == MERAWalletTypes.OperationStatus.Vetoed, OperationNotVetoed(operationId));

        require(_roleRank(callerRole) > _roleRank(operation.creatorRole), CannotClearVeto(operationId));

        operation.status = MERAWalletTypes.OperationStatus.Pending;
        emit PendingTransactionVetoCleared(operationId, operation.salt, msg.sender);
    }

    /// @notice Irreversible cancel: any core controller (allowed even when the caller's role is frozen or under SafeMode); uses {_roleRank} (Primary=1 .. Emergency=3). Cancel if caller rank is at most creator rank (stronger or same tier). Refund still goes to the proposer. Agents cannot call.
    function cancelPending(bytes32 operationId) external override whenLifeAlive {
        // Allow cancellation under freezes/timelocks/SafeMode: only require a core role (not None).
        MERAWalletTypes.Role callerRole = _requireController();
        MERAWalletTypes.PendingOperation storage operation = _operations[operationId];
        MERAWalletTypes.RelayOperation storage relayOperation = _relayOperations[operationId];
        require(
            operation.status == MERAWalletTypes.OperationStatus.Pending
                || operation.status == MERAWalletTypes.OperationStatus.Vetoed,
            OperationNotPending(operationId)
        );

        require(
            callerRole != MERAWalletTypes.Role.Emergency || operation.creatorRole != MERAWalletTypes.Role.Emergency,
            CannotCancelOperation(operationId)
        );
        require(_roleRank(callerRole) <= _roleRank(operation.creatorRole), CannotCancelOperation(operationId));

        _refundRelayReward(operation.creator, relayOperation.relayReward);
        relayOperation.relayReward = 0;
        operation.status = MERAWalletTypes.OperationStatus.Cancelled;
        _decrementPendingTransactionsCount(operation);
        emit PendingTransactionCancelled(operationId, operation.salt, msg.sender);
    }

    function set1271Signer(address signer) external override onlySelf whenLifeAlive {
        _set1271Signer(signer);
    }

    function getRequiredCheckers()
        external
        view
        override
        returns (address[] memory beforeCheckers, address[] memory afterCheckers)
    {
        return (requiredBeforeCheckers, requiredAfterCheckers);
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

    function getRequiredDelay(MERAWalletTypes.Call[] calldata calls) external view override returns (uint256) {
        MERAWalletTypes.Role callerRole = _requireControllerCoreAvailable();
        _validateCalls(calls);
        return _getRequiredDelay(callerRole, calls);
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

    function _setSelectorCallPolicy(bytes4 selector, MERAWalletTypes.CallPathPolicy memory policy) internal {
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

    function _setRequiredChecker(address checker, bool enabled, bytes calldata config) internal {
        require(checker != address(0), InvalidCheckerAddress());

        bool wasConfigured = _requiredBeforeIndexPlusOne[checker] != 0 || _requiredAfterIndexPlusOne[checker] != 0;

        if (!enabled) {
            require(wasConfigured, NoopCheckerConfig());
            _setRequiredBeforeChecker(checker, false);
            _setRequiredAfterChecker(checker, false);
            emit RequiredCheckerUpdated(checker, false, false, msg.sender);
            return;
        }

        if (config.length > 0) {
            IMERAWalletTransactionChecker(checker).applyConfig(config);
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

    /// @notice Configure an agent. `Role.None` disables it.
    function _setAgent(address agent, MERAWalletTypes.Role roleLevel) internal {
        address caller = _effectiveCaller();
        MERAWalletTypes.Role callerCore = _effectiveCoreRole();
        require(callerCore != MERAWalletTypes.Role.None, NotCoreController());
        _requireCoreRoleAvailable(callerCore);

        MERAWalletTypes.Agent storage stored = agents[agent];

        if (roleLevel == MERAWalletTypes.Role.None) {
            require(stored.roleLevel != MERAWalletTypes.Role.None, NoopAgent());
            require(_roleRank(callerCore) >= _roleRank(stored.roleLevel), AgentRemovalNotAuthorized());
            delete agents[agent];
            emit AgentUpdated(agent, MERAWalletTypes.Role.None, 0, caller);
            return;
        }

        require(agent != address(0), InvalidAddress());
        // Core wallet controllers cannot be delegated agents (avoids dual-path authority for the same address).
        require(agent != primary && agent != backup && agent != emergency, CoreControllerCannotBeAgent(agent));
        require(_roleRank(roleLevel) <= _roleRank(callerCore), AgentRemovalNotAuthorized());

        // Emergency agent: `activeFrom` stays 0 until first veto, freeze, or safe mode (see _startEmergencyAgentLifetimeIfNeeded).
        stored.roleLevel = roleLevel;
        stored.activeFrom = 0;

        emit AgentUpdated(agent, stored.roleLevel, uint64(0), caller);
    }

    function _proposeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt, MERAWalletTypes.Role callerRole)
        internal
        returns (bytes32 operationId, uint256 executeAfter)
    {
        _validateCalls(calls);

        operationId = _computeOperationId(calls, salt);
        uint256 requiredDelay = _getRequiredDelay(callerRole, calls);
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
        ++pendingTransactionsCount;

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
        // The cutoff invalidates transactions created before this timestamp.
        // Transactions created in the same block remain valid; intra-block order is intentionally ignored.
        require(
            uint256(operation.createdAt) >= pendingTransactionsInvalidBefore, PendingTransactionInvalidated(operationId)
        );
        _requireRelayExecutionNotExpired(relayOperation);

        if (relayOperation.relayPolicy == MERAWalletTypes.RelayExecutorPolicy.CoreExecute) {
            require(executorWhitelist.length == 0, InvalidExecutorWhitelist());
            _requireControllerCoreAvailable();
        } else {
            require(!_isCoreController(msg.sender), CoreExecutorNotAllowed(msg.sender));
            _validateRelayExecutor(relayOperation, executorWhitelist);
        }

        operation.status = MERAWalletTypes.OperationStatus.Executed;
        _decrementPendingTransactionsCount(operation);

        _executeCallsWithHooks(calls, operationId, operation.creator, operation.creatorRole);
        _payoutRelayReward(relayOperation);

        emit PendingTransactionExecuted(operationId, salt, msg.sender);
    }

    /// @dev Runs before/after hooks and the external call for each entry in order so checkers observe post-state incrementally.
    function _executeCallsWithHooks(
        MERAWalletTypes.Call[] calldata calls,
        bytes32 operationId,
        address contextCaller,
        MERAWalletTypes.Role contextRole
    ) internal {
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength;) {
            MERAWalletTypes.Call calldata callData = calls[i];
            _beforeExecute(callData, operationId, i);
            (bool success, bytes memory result) = _callWithExecutionContext(callData, contextCaller, contextRole);
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

        _isLifeController[controller] = enabled;
        emit LifeControllerUpdated(controller, enabled, caller);
    }

    function _initialize(
        address initialPrimary,
        address initialBackup,
        address initialEmergency,
        address initialSigner,
        address initialGuardian
    ) internal {
        require(
            initialPrimary != address(0) && initialBackup != address(0) && initialEmergency != address(0),
            InvalidAddress()
        );

        guardian = initialGuardian;

        primary = initialPrimary;
        backup = initialBackup;
        emergency = initialEmergency;
        roleTimelock[MERAWalletTypes.Role.Primary] = MERAWalletConstants.DEFAULT_PRIMARY_TIMELOCK;
        roleTimelock[MERAWalletTypes.Role.Backup] = MERAWalletConstants.DEFAULT_BACKUP_TIMELOCK;
        roleTimelock[MERAWalletTypes.Role.Emergency] = MERAWalletConstants.DEFAULT_EMERGENCY_TIMELOCK;
        emergencyAgentLifetime = MERAWalletConstants.DEFAULT_EMERGENCY_AGENT_LIFETIME;
        _setLifeController(initialEmergency, true, msg.sender);
        lastLifeHeartbeatAt = block.timestamp;

        _set1271Signer(initialSigner);

        MERAWalletTypes.CallPathPolicy memory ownershipAndGrantRolePolicy = MERAWalletTypes.CallPathPolicy({
            primary: MERAWalletTypes.RoleCallPolicy({delay: 0, forbidden: true}),
            backup: MERAWalletTypes.RoleCallPolicy({delay: 0, forbidden: true}),
            emergencyDelay: uint56(MERAWalletConstants.OWNERSHIP_AND_ROLE_GRANT_SELECTOR_EMERGENCY_DELAY),
            exists: true
        });
        _setSelectorCallPolicy(IMigrationCalls.transferOwnership.selector, ownershipAndGrantRolePolicy);
        _setSelectorCallPolicy(IMigrationCalls.grantRole.selector, ownershipAndGrantRolePolicy);
        _setSelectorCallPolicy(
            IMERAWalletLoginRegistryMigration.requestLoginMigration.selector, ownershipAndGrantRolePolicy
        );
        _setSelectorCallPolicy(
            IMERAWalletLoginRegistryMigration.confirmLoginMigration.selector, ownershipAndGrantRolePolicy
        );
        _setSelectorCallPolicy(IBaseMERAWallet.setTargetCallPolicies.selector, ownershipAndGrantRolePolicy);
        _setSelectorCallPolicy(IBaseMERAWallet.setSelectorCallPolicies.selector, ownershipAndGrantRolePolicy);
        _setSelectorCallPolicy(IBaseMERAWallet.setTargetSelectorCallPolicies.selector, ownershipAndGrantRolePolicy);
        _setSelectorCallPolicy(IBaseMERAWallet.setRequiredCheckers.selector, ownershipAndGrantRolePolicy);
        _setSelectorCallPolicy(IBaseMERAWallet.setOptionalCheckers.selector, ownershipAndGrantRolePolicy);
    }

    function _invokeBeforeRequiredCheckers(MERAWalletTypes.Call calldata callData, bytes32 operationId, uint256 callId)
        internal
    {
        if (callData.target == address(this)) {
            return;
        }
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
        if (callData.target == address(this)) {
            return;
        }
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
        if (callData.target == address(this)) {
            return;
        }
        address checker = callData.checker;
        if (checker == address(0) || !whitelistOptionalChecker[checker].enableBefore) {
            return;
        }
        IMERAWalletTransactionChecker(checker).checkBefore(callData, operationId, callId);
    }

    function _invokeAfterOptionalChecker(MERAWalletTypes.Call calldata callData, bytes32 operationId, uint256 callId)
        internal
    {
        if (callData.target == address(this)) {
            return;
        }
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
        if (callData.target == address(this)) {
            return;
        }
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
        if (callData.target == address(this)) {
            return;
        }
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
        if (callData.target == address(this)) {
            return;
        }
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
        if (callData.target == address(this)) {
            return;
        }
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

    function _invalidatePendingTransactions(address caller) internal {
        uint256 previousInvalidBefore = pendingTransactionsInvalidBefore;
        uint256 previousPendingTransactionsCount = pendingTransactionsCount;
        uint256 newInvalidBefore = block.timestamp;

        // Only transactions created before this timestamp are cut off.
        // Same-block transactions stay valid because block.timestamp cannot express intra-block order.
        pendingTransactionsInvalidBefore = newInvalidBefore;
        pendingTransactionsCount = 0;

        emit PendingTransactionsInvalidated(
            previousInvalidBefore, newInvalidBefore, previousPendingTransactionsCount, caller
        );
    }

    function _decrementPendingTransactionsCount(MERAWalletTypes.PendingOperation storage operation) internal {
        if (uint256(operation.createdAt) < pendingTransactionsInvalidBefore || pendingTransactionsCount == 0) {
            return;
        }

        --pendingTransactionsCount;
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

    function _callWithExecutionContext(
        MERAWalletTypes.Call calldata callData,
        address contextCaller,
        MERAWalletTypes.Role contextRole
    ) internal returns (bool success, bytes memory result) {
        if (callData.target != address(this)) {
            return callData.target.call{value: callData.value}(callData.data);
        }

        _storeExecutionContext(contextCaller, contextRole);
        (success, result) = callData.target.call{value: callData.value}(callData.data);
        _clearExecutionContext();
    }

    function _storeExecutionContext(address contextCaller, MERAWalletTypes.Role contextRole) internal {
        bytes32 callerSlot = MERAWalletConstants.EXECUTION_CONTEXT_CALLER_SLOT;
        bytes32 roleSlot = MERAWalletConstants.EXECUTION_CONTEXT_ROLE_SLOT;
        assembly ("memory-safe") {
            tstore(callerSlot, contextCaller)
            tstore(roleSlot, contextRole)
        }
    }

    function _clearExecutionContext() internal {
        bytes32 callerSlot = MERAWalletConstants.EXECUTION_CONTEXT_CALLER_SLOT;
        bytes32 roleSlot = MERAWalletConstants.EXECUTION_CONTEXT_ROLE_SLOT;
        assembly ("memory-safe") {
            tstore(callerSlot, 0)
            tstore(roleSlot, 0)
        }
    }

    function _effectiveCaller() internal view returns (address contextCaller) {
        bytes32 callerSlot = MERAWalletConstants.EXECUTION_CONTEXT_CALLER_SLOT;
        assembly ("memory-safe") {
            contextCaller := tload(callerSlot)
        }
        if (contextCaller == address(0)) {
            return msg.sender;
        }
    }

    function _effectiveCoreRole() internal view returns (MERAWalletTypes.Role role) {
        bytes32 roleSlot = MERAWalletConstants.EXECUTION_CONTEXT_ROLE_SLOT;
        uint256 rawRole;
        assembly ("memory-safe") {
            rawRole := tload(roleSlot)
        }
        if (rawRole != 0) {
            return MERAWalletTypes.Role(rawRole);
        }
        return _coreRole(msg.sender);
    }

    function _beforePropose(MERAWalletTypes.Call[] calldata calls, bytes32 operationId) internal virtual {}

    function _beforeExecute(MERAWalletTypes.Call calldata callData, bytes32 operationId, uint256 callId)
        internal
        virtual
    {
        _invokeBeforeRequiredCheckers(callData, operationId, callId);
        _invokeBeforeOptionalChecker(callData, operationId, callId);
    }

    function _afterExecute(MERAWalletTypes.Call calldata callData, bytes32 operationId, uint256 callId)
        internal
        virtual
    {
        _invokeAfterRequiredCheckers(callData, operationId, callId);
        _invokeAfterOptionalChecker(callData, operationId, callId);
    }

    function _validateMigrationCalls(MERAWalletTypes.Call[] calldata calls) internal view {
        require(calls.length > 0, EmptyCalls());
        uint256 n = calls.length;
        for (uint256 i = 0; i < n;) {
            if (!_isMigrationCall(calls[i])) revert MigrationCallNotAllowed(i);
            unchecked {
                ++i;
            }
        }
    }

    function _isMigrationCall(MERAWalletTypes.Call calldata call) internal view returns (bool) {
        bytes4 sel = _extractSelectorFromCalldataBytes(call.data);

        // transferOwnership(address) — address is first arg at data[4:36]
        if (sel == IMigrationCalls.transferOwnership.selector) {
            return call.data.length >= 36 && address(uint160(uint256(bytes32(call.data[4:36])))) == migrationTarget;
        }
        // grantRole(bytes32,address) — address is second arg at data[36:68]
        if (sel == IMigrationCalls.grantRole.selector) {
            return call.data.length >= 68 && address(uint160(uint256(bytes32(call.data[36:68])))) == migrationTarget;
        }
        return false;
    }

    function _onlySelf() internal view {
        require(msg.sender == address(this), NotSelf());
    }

    function _onlySelfAsEmergency() internal view {
        _onlySelf();
        _requireNotSafeMode();
        require(_effectiveCoreRole() == MERAWalletTypes.Role.Emergency, NotEmergency());
    }

    function _requireControllerCoreAvailable() internal view returns (MERAWalletTypes.Role callerRole) {
        _requireNotSafeMode();
        callerRole = _requireController();
        _requireCoreRoleNotFrozen(callerRole);
    }

    function _requireCoreRoleAvailable(MERAWalletTypes.Role role) internal view {
        _requireNotSafeMode();
        _requireCoreRoleNotFrozen(role);
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
        _validateCheckerWhitelist(calls);
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

    /// @dev Pair policies override target/selector policies. Role timelock is the fallback when no call-path policy exists.
    function _getCallDelay(MERAWalletTypes.Role callerRole, MERAWalletTypes.Call calldata callData)
        internal
        view
        returns (uint256)
    {
        return _getCallDelayForPolicyRole(callerRole, callData.target, callData.data);
    }

    /// @notice Delay from role-level and call-path policies.
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
            return roleTimelock[policyRole];
        }

        MERAWalletTypes.RoleCallPolicy memory targetRole = _rolePolicySlice(targetPolicy, policyRole);
        MERAWalletTypes.RoleCallPolicy memory selectorRole = _rolePolicySlice(selectorPolicy, policyRole);

        require(!targetRole.forbidden && !selectorRole.forbidden, CallPathForbiddenForRole(policyRole));

        uint256 a = uint256(targetRole.delay);
        uint256 b = uint256(selectorRole.delay);
        return a > b ? a : b;
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

    function _validateCheckerWhitelist(MERAWalletTypes.Call[] calldata calls) internal view {
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength;) {
            if (calls[i].target != address(this)) {
                address checker = calls[i].checker;
                require(whitelistOptionalChecker[checker].allowed, OptionalCheckerNotAllowed(checker, i));
            }
            unchecked {
                ++i;
            }
        }
    }

    function _requireController() internal view returns (MERAWalletTypes.Role role) {
        role = _effectiveCoreRole();
        require(role != MERAWalletTypes.Role.None, Unauthorized());
    }

    /// @dev Core role must not be frozen for this action; Emergency and None pass without revert.
    function _requireCoreRoleNotFrozen(MERAWalletTypes.Role role) internal view {
        require(role != MERAWalletTypes.Role.Primary || !frozenPrimary, RoleFrozen(MERAWalletTypes.Role.Primary));
        require(role != MERAWalletTypes.Role.Backup || !frozenBackup, RoleFrozen(MERAWalletTypes.Role.Backup));
    }

    function _setFrozenRole(MERAWalletTypes.Role targetRole, bool frozen) internal {
        require(targetRole == MERAWalletTypes.Role.Primary || targetRole == MERAWalletTypes.Role.Backup, InvalidRole());

        bool allowed = guardian != address(0) && msg.sender == guardian && frozen;
        if (!allowed) {
            allowed = _isRankedRoleActionAllowed(targetRole, frozen);
        }
        require(allowed, FreezeActionNotAuthorized());

        _startEmergencyAgentLifetimeIfNeeded(msg.sender);

        if (targetRole == MERAWalletTypes.Role.Primary) {
            frozenPrimary = frozen;
            emit PrimaryFreezeUpdated(frozen, msg.sender);
            return;
        }
        if (frozenBackup == frozen) {
            return;
        }
        frozenBackup = frozen;
        emit BackupFreezeUpdated(frozen, msg.sender);
    }

    function _isRankedRoleActionAllowed(MERAWalletTypes.Role targetRole, bool isBlockingAction)
        internal
        view
        returns (bool)
    {
        MERAWalletTypes.Role callerCore = _effectiveCoreRole();
        if (callerCore != MERAWalletTypes.Role.None) {
            _requireCoreRoleAvailable(callerCore);
            if (isBlockingAction) {
                return _roleRank(callerCore) >= _roleRank(targetRole);
            }
            return _roleRank(callerCore) > _roleRank(targetRole);
        }

        MERAWalletTypes.Role agentRole = _agentRole(_effectiveCaller());
        if (agentRole != MERAWalletTypes.Role.None) {
            _requireNotSafeMode();
            return isBlockingAction && _roleRank(agentRole) >= _roleRank(targetRole);
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

    function _rolePolicySlice(MERAWalletTypes.CallPathPolicy memory policy, MERAWalletTypes.Role callerRole)
        internal
        pure
        returns (MERAWalletTypes.RoleCallPolicy memory)
    {
        if (callerRole == MERAWalletTypes.Role.Emergency) {
            return MERAWalletTypes.RoleCallPolicy({delay: policy.emergencyDelay, forbidden: false});
        }
        if (callerRole == MERAWalletTypes.Role.Backup) {
            return policy.backup;
        }
        if (callerRole == MERAWalletTypes.Role.Primary) {
            return policy.primary;
        }
        revert InvalidRole();
    }

    function _agentRole(address account) internal view returns (MERAWalletTypes.Role role) {
        MERAWalletTypes.Agent storage agent = agents[account];
        role = agent.roleLevel;
        // `activeFrom == 0`: Emergency agent assigned but activity not started yet.
        if (role == MERAWalletTypes.Role.Emergency && agent.activeFrom != 0) {
            uint256 expiresAt = uint256(agent.activeFrom) + emergencyAgentLifetime;
            if (block.timestamp > expiresAt) {
                revert AgentExpired(account, expiresAt);
            }
        }
    }

    /// @dev Sets `activeFrom` on first blocking action; no-op if not an Emergency agent or start already recorded.
    function _startEmergencyAgentLifetimeIfNeeded(address account) internal {
        MERAWalletTypes.Agent storage agent = agents[account];
        if (agent.roleLevel != MERAWalletTypes.Role.Emergency || agent.activeFrom != 0) {
            return;
        }
        uint64 startedAt = uint64(block.timestamp);
        agent.activeFrom = startedAt;
        emit AgentUpdated(account, MERAWalletTypes.Role.Emergency, startedAt, _effectiveCaller());
    }

    function _clearSafeMode(address caller) internal {
        if (!safeModeUsed && safeModeBefore == 0) {
            return;
        }
        safeModeBefore = 0;
        emit SafeModeReset(caller);
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

        if (relayConfig.relayPolicy == MERAWalletTypes.RelayExecutorPolicy.CoreExecute) {
            require(relayReward == 0, RelayRewardNotAllowed());
            require(
                relayConfig.designatedExecutor == address(0) && relayConfig.executorSetHash == bytes32(0),
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
