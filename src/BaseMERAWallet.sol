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
    mapping(address target => MERAWalletTypes.CallPathPolicy policy) public callPolicyByTarget;
    mapping(bytes4 selector => MERAWalletTypes.CallPathPolicy policy) public callPolicyBySelector;
    mapping(bytes32 operationId => MERAWalletTypes.PendingOperation operation) internal _operations;
    mapping(bytes32 operationId => MERAWalletTypes.RelayOperation relayOperation) internal _relayOperations;
    mapping(address checker => MERAWalletTypes.WhitelistChecker) public whitelistedChecker;
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

    function _onlyEmergencyOrSelf() internal view {
        require(msg.sender == address(this) || (GUARDIAN == address(0) && msg.sender == emergency), NotEmergency());
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

    function _requireControllerCoreUnfrozen() internal view {
        MERAWalletTypes.Role callerRole = _requireController();
        _requireCoreRoleNotFrozen(callerRole);
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
                if (controller == emergency) {
                    revert EmergencyMustStayLifeController();
                }
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

    function setTargetCallPolicy(address target, MERAWalletTypes.CallPathPolicy calldata policy)
        external
        override
        onlyEmergencyOrSelf
        whenLifeAlive
    {
        MERAWalletTypes.CallPathPolicy memory previousPolicy = callPolicyByTarget[target];
        callPolicyByTarget[target] = policy;
        emit TargetCallPolicyUpdated(target, previousPolicy, policy, msg.sender);
    }

    function setSelectorCallPolicy(bytes4 selector, MERAWalletTypes.CallPathPolicy calldata policy)
        external
        override
        onlyEmergencyOrSelf
        whenLifeAlive
    {
        MERAWalletTypes.CallPathPolicy memory previousPolicy = callPolicyBySelector[selector];
        callPolicyBySelector[selector] = policy;
        emit SelectorCallPolicyUpdated(selector, previousPolicy, policy, msg.sender);
    }

    function setRequiredChecker(address checker, bool enabled) external override onlyEmergencyOrSelf whenLifeAlive {
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

    function setWhitelistedChecker(address checker, bool allowed) external override onlyEmergencyOrSelf whenLifeAlive {
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

    /// @notice Enable or disable a veto agent (may call {vetoPending} on any pending op). Only core controllers may configure.
    /// @dev On enable, `removalMinRole` is set to `_coreRole(msg.sender)` so only that role or higher may later disable.
    function setControllerAgent(address agent, bool enabled) external override whenLifeAlive {
        MERAWalletTypes.Role callerCore = _coreRole(msg.sender);
        require(callerCore != MERAWalletTypes.Role.None, NotCoreController());
        _requireCoreRoleNotFrozen(callerCore);

        MERAWalletTypes.ControllerAgent storage stored = controllerAgents[agent];

        if (!enabled) {
            require(stored.enabled, NoopControllerAgent());
            require(_roleRank(callerCore) >= _roleRank(stored.removalMinRole), AgentRemovalNotAuthorized());
            delete controllerAgents[agent];
            emit ControllerAgentUpdated(agent, false, MERAWalletTypes.Role.None, msg.sender);
            return;
        }

        require(agent != address(0), InvalidAddress());

        stored.enabled = true;
        stored.removalMinRole = callerCore;

        emit ControllerAgentUpdated(agent, true, stored.removalMinRole, msg.sender);
    }

    /// @dev Only Backup or Emergency may change primary-level freeze; Primary cannot.
    function setFrozenPrimary(bool frozen) external override whenLifeAlive {
        MERAWalletTypes.Role callerCore = _coreRole(msg.sender);
        require(
            callerCore == MERAWalletTypes.Role.Backup || callerCore == MERAWalletTypes.Role.Emergency,
            FreezeActionNotAuthorized()
        );
        if (frozenPrimary == frozen) {
            return;
        }
        frozenPrimary = frozen;
        emit PrimaryFreezeUpdated(frozen, msg.sender);
    }

    /// @dev Only Emergency may change backup-level freeze.
    function setFrozenBackup(bool frozen) external override whenLifeAlive {
        require(_coreRole(msg.sender) == MERAWalletTypes.Role.Emergency, FreezeActionNotAuthorized());
        if (frozenBackup == frozen) {
            return;
        }
        frozenBackup = frozen;
        emit BackupFreezeUpdated(frozen, msg.sender);
    }

    /// @notice Sets `frozenPrimary` to true; only enabled controller agents; cannot unfreeze.
    function freezePrimaryByAgent() external override whenLifeAlive {
        require(controllerAgents[msg.sender].enabled, Unauthorized());
        if (frozenPrimary) {
            return;
        }
        frozenPrimary = true;
        emit PrimaryFreezeUpdated(true, msg.sender);
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
            bytes32 executorSetHash
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
            relayOperation.executorSetHash
        );
    }

    function executeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        external
        payable
        override
        whenLifeAlive
        whenControllerCoreUnfrozen
    {
        MERAWalletTypes.Call[] memory memoryCalls = calls;

        _validateCalls(memoryCalls);

        bytes32 operationId = _computeOperationId(memoryCalls, salt);
        uint256 requiredDelay = _getRequiredDelay(_coreRole(msg.sender), memoryCalls);

        require(requiredDelay == 0, TimelockRequired(requiredDelay));

        _executeCallsWithHooks(memoryCalls, operationId);

        emit ImmediateTransactionExecuted(operationId, salt, msg.sender);
    }

    function proposeTransaction(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        external
        override
        whenLifeAlive
        returns (bytes32 operationId)
    {
        MERAWalletTypes.Call[] memory memoryCalls = new MERAWalletTypes.Call[](calls.length);
        uint256 len = calls.length;
        for (uint256 i = 0; i < len;) {
            memoryCalls[i] = calls[i];
            unchecked {
                ++i;
            }
        }
        (operationId,,,) = _proposeTransactionFromMemory(memoryCalls, salt);
    }

    function proposeTransactionWithRelay(
        MERAWalletTypes.Call[] calldata calls,
        uint256 salt,
        MERAWalletTypes.RelayProposeConfig calldata relayConfig
    ) external payable override whenLifeAlive returns (bytes32 operationId) {
        MERAWalletTypes.RelayProposeConfig memory relayConfigMem = relayConfig;
        _validateRelayConfig(relayConfigMem, msg.value);

        MERAWalletTypes.Call[] memory memoryCalls = new MERAWalletTypes.Call[](calls.length);
        uint256 clen = calls.length;
        for (uint256 i = 0; i < clen;) {
            memoryCalls[i] = calls[i];
            unchecked {
                ++i;
            }
        }
        (operationId,,,) = _proposeTransactionFromMemory(memoryCalls, salt);
        _saveRelayOperation(operationId, relayConfigMem, msg.value);
    }

    function executePending(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        external
        payable
        override
        whenLifeAlive
    {
        address[] memory emptyWhitelist = new address[](0);
        _executePendingCalldata(calls, salt, emptyWhitelist);
    }

    function executePending(MERAWalletTypes.Call[] calldata calls, uint256 salt, address[] calldata executorWhitelist)
        external
        payable
        override
        whenLifeAlive
    {
        address[] memory whitelist = executorWhitelist;
        _executePendingCalldata(calls, salt, whitelist);
    }

    function _executePendingCalldata(
        MERAWalletTypes.Call[] calldata calls,
        uint256 salt,
        address[] memory executorWhitelist
    ) internal {
        MERAWalletTypes.Call[] memory memoryCalls = new MERAWalletTypes.Call[](calls.length);
        uint256 clen = calls.length;
        for (uint256 i = 0; i < clen;) {
            memoryCalls[i] = calls[i];
            unchecked {
                ++i;
            }
        }
        _executePendingFromMemory(memoryCalls, salt, executorWhitelist);
    }

    /// @dev Used by extensions that build `Call[]` in memory (e.g. ERC20 timelock helpers).
    function _proposeTransactionFromMemory(MERAWalletTypes.Call[] memory memoryCalls, uint256 salt)
        internal
        whenControllerCoreUnfrozen
        returns (bytes32 operationId, MERAWalletTypes.Role callerRole, uint256 executeAfter, uint256 requiredDelay)
    {
        callerRole = _coreRole(msg.sender);

        _validateCalls(memoryCalls);

        operationId = _computeOperationId(memoryCalls, salt);
        requiredDelay = _getRequiredDelay(callerRole, memoryCalls);
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

        _beforePropose(memoryCalls, operationId);

        emit TransactionProposed(operationId, salt, msg.sender, callerRole, executeAfter, requiredDelay);
    }

    function _saveRelayOperation(
        bytes32 operationId,
        MERAWalletTypes.RelayProposeConfig memory relayConfig,
        uint256 relayReward
    ) internal {
        _relayOperations[operationId] =
            MERAWalletTypes.RelayOperation({
                relayPolicy: relayConfig.relayPolicy,
                relayReward: relayReward,
                designatedExecutor: relayConfig.designatedExecutor,
                executorSetHash: relayConfig.executorSetHash
            });
        emit RelayOperationSaved(
            operationId,
            relayConfig.relayPolicy,
            relayReward,
            relayConfig.designatedExecutor,
            relayConfig.executorSetHash
        );
    }

    function _executePendingFromMemory(
        MERAWalletTypes.Call[] memory memoryCalls,
        uint256 salt,
        address[] memory executorWhitelist
    ) internal {
        _validateCalls(memoryCalls);

        bytes32 operationId = _computeOperationId(memoryCalls, salt);
        MERAWalletTypes.PendingOperation storage operation = _operations[operationId];
        MERAWalletTypes.RelayOperation storage relayOperation = _relayOperations[operationId];

        if (operation.status == MERAWalletTypes.OperationStatus.Vetoed) {
            revert OperationVetoed(operationId);
        }
        require(operation.status == MERAWalletTypes.OperationStatus.Pending, OperationNotPending(operationId));
        require(block.timestamp >= operation.executeAfter, TimelockNotExpired(operation.executeAfter, block.timestamp));

        if (relayOperation.relayPolicy == MERAWalletTypes.RelayExecutorPolicy.CoreExecute) {
            require(executorWhitelist.length == 0, InvalidExecutorWhitelist());
            _requireControllerCoreUnfrozen();
        } else {
            require(!_isCoreController(msg.sender), CoreExecutorNotAllowed(msg.sender));
            _validateRelayExecutor(relayOperation, executorWhitelist);
        }

        operation.status = MERAWalletTypes.OperationStatus.Executed;

        _executeCallsWithHooks(memoryCalls, operationId);
        _payoutRelayReward(relayOperation);

        emit PendingTransactionExecuted(operationId, salt, msg.sender);
    }

    function vetoPending(bytes32 operationId) external override whenLifeAlive {
        require(controllerAgents[msg.sender].enabled, Unauthorized());
        require(_coreRole(msg.sender) == MERAWalletTypes.Role.None, Unauthorized());

        MERAWalletTypes.PendingOperation storage operation = _operations[operationId];
        require(operation.status != MERAWalletTypes.OperationStatus.Vetoed, OperationAlreadyVetoed(operationId));
        require(operation.status == MERAWalletTypes.OperationStatus.Pending, OperationNotPending(operationId));

        require(operation.creatorRole != MERAWalletTypes.Role.Emergency, AgentCannotVetoEmergencyOperation());

        operation.status = MERAWalletTypes.OperationStatus.Vetoed;
        emit PendingTransactionVetoed(operationId, operation.salt, msg.sender);
    }

    function clearVeto(bytes32 operationId) external override whenLifeAlive whenControllerCoreUnfrozen {
        MERAWalletTypes.PendingOperation storage operation = _operations[operationId];
        require(operation.status == MERAWalletTypes.OperationStatus.Vetoed, OperationNotVetoed(operationId));

        operation.status = MERAWalletTypes.OperationStatus.Pending;
        emit PendingTransactionVetoCleared(operationId, operation.salt, msg.sender);
    }

    /// @notice Irreversible cancel: only unfrozen Primary; must be the operation creator (proposer). Backup/Emergency/agents cannot call.
    function cancelPending(bytes32 operationId) external override whenLifeAlive whenControllerCoreUnfrozen {
        MERAWalletTypes.PendingOperation storage operation = _operations[operationId];
        MERAWalletTypes.RelayOperation storage relayOperation = _relayOperations[operationId];
        require(
            operation.status == MERAWalletTypes.OperationStatus.Pending
                || operation.status == MERAWalletTypes.OperationStatus.Vetoed,
            OperationNotPending(operationId)
        );

        require(_coreRole(msg.sender) == MERAWalletTypes.Role.Primary, CancelPendingPrimaryOnly());
        // Primary-only caller: only the proposer may cancel (override is for Backup/Emergency, not used here).
        require(operation.creator == msg.sender, CannotCancelOperation(operationId));

        _refundRelayReward(operation.creator, relayOperation.relayReward);
        relayOperation.relayReward = 0;
        operation.status = MERAWalletTypes.OperationStatus.Cancelled;
        emit PendingTransactionCancelled(operationId, operation.salt, msg.sender);
    }

    function getOperationId(MERAWalletTypes.Call[] calldata calls, uint256 salt)
        external
        view
        override
        returns (bytes32)
    {
        MERAWalletTypes.Call[] memory memoryCalls = calls;
        _validateCalls(memoryCalls);
        return _computeOperationId(memoryCalls, salt);
    }

    function getRequiredDelay(MERAWalletTypes.Call[] calldata calls)
        external
        view
        override
        whenControllerCoreUnfrozen
        returns (uint256)
    {
        MERAWalletTypes.Call[] memory memoryCalls = calls;
        _validateCalls(memoryCalls);
        return _getRequiredDelay(_coreRole(msg.sender), memoryCalls);
    }

    function set1271Signer(address signer) external override onlyEmergencyOrSelf whenLifeAlive {
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
        uint256 salt
    ) internal {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: target, value: value, data: data, checker: checker, checkerData: checkerData
        });
        _executeImmediateFromCalls(calls, salt);
    }

    function _executeImmediateFromCalls(MERAWalletTypes.Call[] memory calls, uint256 salt)
        internal
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

    function _validateCalls(MERAWalletTypes.Call[] memory calls) internal view {
        require(calls.length > 0, EmptyCalls());
        require(
            calls.length <= MERAWalletConstants.MAX_CALLS_PER_BATCH,
            TooManyCalls(calls.length, MERAWalletConstants.MAX_CALLS_PER_BATCH)
        );
        _validateCallWhitelist(calls);
    }

    /// @dev Same bytes as `abi.encode(chainId, wallet, calls, salt)`; `keccak256` runs over the length-prefixed buffer in assembly (matches high-level `keccak256(bytes)` hashing).
    function _computeOperationId(MERAWalletTypes.Call[] memory calls, uint256 salt) internal view returns (bytes32 id) {
        bytes memory preimage = abi.encode(block.chainid, address(this), calls, salt);
        assembly ("memory-safe") {
            id := keccak256(add(preimage, 32), mload(preimage))
        }
    }

    function _getRequiredDelay(MERAWalletTypes.Role callerRole, MERAWalletTypes.Call[] memory calls)
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

    /// @dev Required delay for one call: if neither target nor selector sets a role delay, use `globalTimelock`;
    ///      otherwise use max(target role delay, selector role delay). Reverts if path forbidden for role.
    /// @dev Emergency uses the **backup** policy slice (no Emergency dimension in `CallPathPolicy`); self-calls that
    ///      only adjust wallet config may be exempt — see `_isEmergencyTimelockExemptSelfCall`.
    function _getCallDelay(MERAWalletTypes.Role callerRole, MERAWalletTypes.Call memory callData)
        internal
        view
        returns (uint256)
    {
        if (callerRole == MERAWalletTypes.Role.Emergency) {
            if (_isEmergencyTimelockExemptSelfCall(callData)) {
                return 0;
            }
            return _getCallDelayForPolicyRole(MERAWalletTypes.Role.Backup, callData);
        }
        return _getCallDelayForPolicyRole(callerRole, callData);
    }

    /// @notice Delay from call policies for Primary or Backup (same slice as used for Emergency when not exempt).
    function _getCallDelayForPolicyRole(MERAWalletTypes.Role policyRole, MERAWalletTypes.Call memory callData)
        internal
        view
        returns (uint256)
    {
        MERAWalletTypes.CallPathPolicy memory targetPolicy = callPolicyByTarget[callData.target];
        bytes4 selector = _extractSelector(callData.data);
        MERAWalletTypes.CallPathPolicy memory selectorPolicy = callPolicyBySelector[selector];

        MERAWalletTypes.RoleCallPolicy memory targetRole = _rolePolicySlice(targetPolicy, policyRole);
        MERAWalletTypes.RoleCallPolicy memory selectorRole = _rolePolicySlice(selectorPolicy, policyRole);

        require(!targetRole.forbidden && !selectorRole.forbidden, CallPathForbiddenForRole(policyRole));

        uint256 a = uint256(targetRole.delay);
        uint256 b = uint256(selectorRole.delay);
        if (a == 0 && b == 0) {
            return globalTimelock;
        }
        return a > b ? a : b;
    }

    /// @dev Zero extra delay for emergency-driven self-calls that only reconfigure the wallet (role / freeze / policies / life).
    function _isEmergencyTimelockExemptSelfCall(MERAWalletTypes.Call memory callData) internal view returns (bool) {
        if (callData.target != address(this)) {
            return false;
        }
        return _isEmergencyConfigSelector(_extractSelector(callData.data));
    }

    function _isEmergencyConfigSelector(bytes4 selector) internal pure returns (bool) {
        return selector == MERAWalletConstants.SEL_SET_PRIMARY || selector == MERAWalletConstants.SEL_SET_BACKUP
            || selector == MERAWalletConstants.SEL_SET_EMERGENCY
            || selector == MERAWalletConstants.SEL_SET_GLOBAL_TIMELOCK
            || selector == MERAWalletConstants.SEL_SET_LIFE_CONTROL
            || selector == MERAWalletConstants.SEL_SET_LIFE_CONTROLLERS
            || selector == MERAWalletConstants.SEL_SET_TARGET_CALL_POLICY
            || selector == MERAWalletConstants.SEL_SET_SELECTOR_CALL_POLICY
            || selector == MERAWalletConstants.SEL_SET_REQUIRED_CHECKER
            || selector == MERAWalletConstants.SEL_SET_WHITELISTED_CHECKER
            || selector == MERAWalletConstants.SEL_SET_CONTROLLER_AGENT
            || selector == MERAWalletConstants.SEL_SET_FROZEN_PRIMARY
            || selector == MERAWalletConstants.SEL_SET_FROZEN_BACKUP
            || selector == MERAWalletConstants.SEL_SET1271_SIGNER
            || selector == MERAWalletConstants.SEL_FREEZE_PRIMARY_BY_AGENT;
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

    function _requireLifeAliveForStateChanges() internal view {
        if (!lifeControlEnabled) {
            return;
        }

        require(
            lastLifeHeartbeatAt != 0 && block.timestamp <= lastLifeHeartbeatAt + lifeHeartbeatTimeout,
            LifeHeartbeatExpired(lastLifeHeartbeatAt, lifeHeartbeatTimeout, block.timestamp)
        );
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

    function _invokeAfterRequiredCheckers(MERAWalletTypes.Call memory callData, bytes32 operationId, uint256 callId)
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

    function _invokeBeforeWhitelistedChecker(MERAWalletTypes.Call memory callData, bytes32 operationId, uint256 callId)
        internal
    {
        address checker = callData.checker;
        if (checker == address(0) || !whitelistedChecker[checker].enableBefore) {
            return;
        }
        IMERAWalletTransactionChecker(checker).checkBefore(callData, operationId, callId);
    }

    function _invokeAfterWhitelistedChecker(MERAWalletTypes.Call memory callData, bytes32 operationId, uint256 callId)
        internal
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
        if (data.length < MERAWalletConstants.FUNCTION_SELECTOR_LENGTH) {
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

    function _validateRelayConfig(MERAWalletTypes.RelayProposeConfig memory relayConfig, uint256 relayReward)
        internal
        pure
    {
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

    function _isCoreController(address account) internal view returns (bool) {
        return _coreRole(account) != MERAWalletTypes.Role.None;
    }

    /// @dev Role from the wallet's fixed controller addresses only (ignores controller agent mapping).
    function _coreRole(address account) internal view returns (MERAWalletTypes.Role) {
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

    /// @dev Primary < Backup < Emergency for removal / assignment caps.
    function _roleRank(MERAWalletTypes.Role role) internal pure returns (uint256) {
        if (role == MERAWalletTypes.Role.Primary) {
            return MERAWalletConstants.ROLE_RANK_PRIMARY;
        }
        if (role == MERAWalletTypes.Role.Backup) {
            return MERAWalletConstants.ROLE_RANK_BACKUP;
        }
        if (role == MERAWalletTypes.Role.Emergency) {
            return MERAWalletConstants.ROLE_RANK_EMERGENCY;
        }
        return MERAWalletConstants.ROLE_RANK_NONE;
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
