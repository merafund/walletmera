// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IBaseMERAWallet} from "../interfaces/IBaseMERAWallet.sol";
import {MERAWalletLoginRegistry} from "../MERAWalletLoginRegistry.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @notice Login-based threshold guardian backed by incrementally revealed Merkle login proofs.
contract MERAWalletLoginMerkleGuardian {
    /// @notice Emergency-change proposal approved by eligible login owners.
    struct Proposal {
        /// @notice Wallet whose emergency controller will change.
        address targetWallet;
        /// @notice Proposed emergency controller.
        address newEmergency;
        /// @notice Address that created the proposal.
        address proposer;
        /// @notice Timestamp when the proposal was created.
        uint64 createdAt;
        /// @notice Number of current approvals.
        uint16 approvals;
        /// @notice Whether the proposal has been executed.
        bool executed;
    }

    /// @notice Login registry used to map wallets to login hashes.
    MERAWalletLoginRegistry public immutable LOGIN_REGISTRY;
    /// @notice Merkle root of eligible login hashes.
    bytes32 public immutable LOGIN_ROOT;
    /// @notice Number of login-owner approvals required for execution.
    uint256 public immutable THRESHOLD;
    /// @notice Lifetime of an emergency-change proposal.
    uint64 public immutable PROPOSAL_LIFETIME;
    /// @notice Lower bound enforced in the constructor for `proposalLifetime_` (72 hours).
    uint64 public constant MIN_PROPOSAL_LIFETIME = 72 hours;

    /// @notice Whether at least one login hash batch has been published.
    bool public loginListPublished;
    /// @notice Total number of published login hashes.
    uint256 public publishedLoginCount;
    /// @notice Monotonic nonce used when deriving proposal ids.
    uint256 public proposalNonce;

    /// @notice Whether a login hash has been published with a valid Merkle proof.
    mapping(bytes32 loginHash => bool published) public publishedLoginHash;
    /// @notice Stored proposals by proposal id.
    mapping(bytes32 proposalId => Proposal proposal) public proposals;
    /// @notice Whether a login hash has approved a proposal.
    mapping(bytes32 proposalId => mapping(bytes32 loginHash => bool approved)) public hasApproved;

    /// @notice Emitted after a login hash is published.
    event LoginHashPublished(bytes32 indexed loginHash);
    /// @notice Emitted after a batch of login hashes is published.
    event LoginListPublished(uint256 loginCount);
    /// @notice Emitted when an eligible login owner proposes an emergency change.
    event EmergencyChangeProposed(
        bytes32 indexed proposalId, address indexed proposer, bytes32 indexed proposerLoginHash, address newEmergency
    );
    /// @notice Emitted when an eligible login hash approves a proposal.
    event ProposalApproved(
        bytes32 indexed proposalId, bytes32 indexed loginHash, address indexed owner, uint256 approvals
    );
    /// @notice Emitted when an eligible login hash revokes approval.
    event ProposalApprovalRevoked(
        bytes32 indexed proposalId, bytes32 indexed loginHash, address indexed owner, uint256 approvals
    );
    /// @notice Emitted when a proposal changes a wallet emergency controller.
    event ProposalExecuted(bytes32 indexed proposalId, address indexed by, address indexed newEmergency);

    error InvalidWallet();
    /// @dev Reverts when `wallet_` does not list this contract as its guardian on IBaseMERAWallet.
    error TargetWalletGuardianMismatch();
    error InvalidLoginRegistry();
    error InvalidLoginRoot();
    error InvalidThreshold();
    /// @dev `proposalLifetime_` must be at least `MIN_PROPOSAL_LIFETIME`.
    error InvalidProposalLifetime();
    error EmptyLoginList();
    error DuplicateLoginHash(bytes32 loginHash);
    error LoginProofCountMismatch(uint256 loginCount, uint256 proofCount);
    error InvalidLoginProof(bytes32 loginHash);
    /// @dev `publishLoginList` caller must be a wallet registered in `LOGIN_REGISTRY`.
    error PublisherNotRegistered(address publisher);
    /// @dev Caller must have already published their login hash or include it in `loginHashes`.
    error PublisherNotInLoginList(address publisher, bytes32 loginHash);
    error LoginListNotPublished();
    error InvalidEmergency();
    error LoginNotEligible(address owner, bytes32 loginHash);
    error ProposalNotFound(bytes32 proposalId);
    error ProposalExpired(bytes32 proposalId, uint256 deadline, uint256 currentTime);
    error ProposalAlreadyExecuted(bytes32 proposalId);
    error AlreadyApproved(bytes32 proposalId, bytes32 loginHash);
    error NotApproved(bytes32 proposalId, bytes32 loginHash);
    error ThresholdNotReached(bytes32 proposalId, uint256 approvals, uint256 threshold);

    /// @notice Creates a login Merkle guardian.
    /// @param loginRegistry_ Login registry used to resolve wallet ownership.
    /// @param loginRoot_ Merkle root of eligible login hashes.
    /// @param threshold_ Number of approvals required for execution.
    /// @param proposalLifetime_ Proposal lifetime in seconds.
    constructor(address loginRegistry_, bytes32 loginRoot_, uint256 threshold_, uint64 proposalLifetime_) {
        require(loginRegistry_ != address(0) && loginRegistry_.code.length != 0, InvalidLoginRegistry());
        require(loginRoot_ != bytes32(0), InvalidLoginRoot());
        require(threshold_ != 0 && threshold_ <= type(uint16).max, InvalidThreshold());
        require(proposalLifetime_ >= MIN_PROPOSAL_LIFETIME, InvalidProposalLifetime());

        LOGIN_REGISTRY = MERAWalletLoginRegistry(loginRegistry_);
        LOGIN_ROOT = loginRoot_;
        THRESHOLD = threshold_;
        PROPOSAL_LIFETIME = proposalLifetime_;
    }

    /// @notice Publishes eligible login hashes with Merkle proofs.
    function publishLoginList(bytes32[] calldata loginHashes, bytes32[][] calldata proofs) external {
        uint256 loginCount = loginHashes.length;
        require(loginCount != 0, EmptyLoginList());
        require(loginCount == proofs.length, LoginProofCountMismatch(loginCount, proofs.length));

        bytes32 senderLoginHash = LOGIN_REGISTRY.loginHashByWallet(msg.sender);
        require(senderLoginHash != bytes32(0), PublisherNotRegistered(msg.sender));

        bool senderCanPublish = publishedLoginHash[senderLoginHash];
        for (uint256 i = 0; i < loginCount;) {
            bytes32 loginHash = loginHashes[i];
            require(!publishedLoginHash[loginHash], DuplicateLoginHash(loginHash));
            require(MerkleProof.verifyCalldata(proofs[i], LOGIN_ROOT, loginHash), InvalidLoginProof(loginHash));
            if (loginHash == senderLoginHash) {
                senderCanPublish = true;
            }
            publishedLoginHash[loginHash] = true;
            emit LoginHashPublished(loginHash);
            unchecked {
                ++i;
            }
        }
        require(senderCanPublish, PublisherNotInLoginList(msg.sender, senderLoginHash));

        loginListPublished = true;
        publishedLoginCount += loginCount;
        emit LoginListPublished(loginCount);
    }

    /// @notice Proposes an emergency controller change for `wallet_`.
    function proposeEmergencyChange(address wallet_, address newEmergency) external returns (bytes32 proposalId) {
        require(wallet_ != address(0), InvalidWallet());
        require(newEmergency != address(0), InvalidEmergency());

        bytes32 loginHash = _requireEligibleLoginOwner(msg.sender);
        require(IBaseMERAWallet(payable(wallet_)).guardian() == address(this), TargetWalletGuardianMismatch());

        uint256 nonce = proposalNonce;
        proposalId = keccak256(abi.encode(wallet_, newEmergency, nonce));
        proposalNonce = nonce + 1;

        Proposal storage proposal = proposals[proposalId];
        proposal.targetWallet = wallet_;
        proposal.newEmergency = newEmergency;
        proposal.proposer = msg.sender;
        proposal.createdAt = uint64(block.timestamp);
        proposal.approvals = 1;

        hasApproved[proposalId][loginHash] = true;

        emit EmergencyChangeProposed(proposalId, msg.sender, loginHash, newEmergency);
        emit ProposalApproved(proposalId, loginHash, msg.sender, 1);
    }

    /// @notice Approves an active proposal with the caller's registered login.
    function approveProposal(bytes32 proposalId) external {
        bytes32 loginHash = _requireEligibleLoginOwner(msg.sender);
        Proposal storage proposal = _activeProposal(proposalId);
        require(!hasApproved[proposalId][loginHash], AlreadyApproved(proposalId, loginHash));

        hasApproved[proposalId][loginHash] = true;
        proposal.approvals += 1;
        emit ProposalApproved(proposalId, loginHash, msg.sender, proposal.approvals);
    }

    /// @notice Revokes the caller's registered-login approval for an active proposal.
    function revokeApproval(bytes32 proposalId) external {
        bytes32 loginHash = _requireEligibleLoginOwner(msg.sender);
        Proposal storage proposal = _activeProposal(proposalId);
        require(hasApproved[proposalId][loginHash], NotApproved(proposalId, loginHash));

        hasApproved[proposalId][loginHash] = false;
        proposal.approvals -= 1;
        emit ProposalApprovalRevoked(proposalId, loginHash, msg.sender, proposal.approvals);
    }

    /// @notice Executes an approved proposal.
    function executeProposal(bytes32 proposalId) external {
        Proposal storage proposal = _activeProposal(proposalId);
        require(proposal.approvals >= THRESHOLD, ThresholdNotReached(proposalId, proposal.approvals, THRESHOLD));

        proposal.executed = true;
        IBaseMERAWallet(payable(proposal.targetWallet)).setEmergency(proposal.newEmergency);
        emit ProposalExecuted(proposalId, msg.sender, proposal.newEmergency);
    }

    /// @notice Freezes the primary role on a target wallet protected by this guardian.
    function freezePrimary(address wallet_) external {
        _requireEligibleLoginOwner(msg.sender);
        _requireTargetWallet(wallet_);
        IBaseMERAWallet(payable(wallet_)).setFrozenPrimary(true);
    }

    /// @notice Freezes the backup role on a target wallet protected by this guardian.
    function freezeBackup(address wallet_) external {
        _requireEligibleLoginOwner(msg.sender);
        _requireTargetWallet(wallet_);
        IBaseMERAWallet(payable(wallet_)).setFrozenBackup(true);
    }

    /// @notice Enters safe mode on a target wallet protected by this guardian.
    function enterSafeMode(address wallet_, uint256 duration) external {
        _requireEligibleLoginOwner(msg.sender);
        _requireTargetWallet(wallet_);
        IBaseMERAWallet(payable(wallet_)).enterSafeMode(duration);
    }

    function _requireEligibleLoginOwner(address owner) internal view returns (bytes32 loginHash) {
        require(loginListPublished, LoginListNotPublished());

        loginHash = LOGIN_REGISTRY.loginHashByWallet(owner);
        require(loginHash != bytes32(0) && publishedLoginHash[loginHash], LoginNotEligible(owner, loginHash));
    }

    function _requireTargetWallet(address wallet_) internal view {
        require(wallet_ != address(0), InvalidWallet());
        require(IBaseMERAWallet(payable(wallet_)).guardian() == address(this), TargetWalletGuardianMismatch());
    }

    function _activeProposal(bytes32 proposalId) internal view returns (Proposal storage proposal) {
        proposal = proposals[proposalId];
        require(proposal.createdAt != 0, ProposalNotFound(proposalId));
        require(!proposal.executed, ProposalAlreadyExecuted(proposalId));
        uint256 expiresAt = uint256(proposal.createdAt) + PROPOSAL_LIFETIME;
        require(block.timestamp <= expiresAt, ProposalExpired(proposalId, expiresAt, block.timestamp));
    }
}
