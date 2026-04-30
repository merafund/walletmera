// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IBaseMERAWallet} from "../interfaces/IBaseMERAWallet.sol";
import {MERAWalletLoginRegistry} from "../MERAWalletLoginRegistry.sol";
import {Hashes} from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

/// @notice Login-based threshold guardian backed by a one-time published Merkle login set.
contract MERAWalletLoginMerkleGuardian {
    struct Proposal {
        address targetWallet;
        address newEmergency;
        address proposer;
        uint64 createdAt;
        uint64 deadline;
        uint16 approvals;
        bool executed;
        bool cancelled;
    }

    MERAWalletLoginRegistry public immutable LOGIN_REGISTRY;
    bytes32 public immutable LOGIN_ROOT;
    uint256 public immutable THRESHOLD;
    uint64 public immutable PROPOSAL_LIFETIME;
    /// @notice Lower bound enforced in the constructor for `proposalLifetime_` (72 hours).
    uint64 public constant MIN_PROPOSAL_LIFETIME = 72 hours;

    bool public loginListPublished;
    uint256 public proposalNonce;

    mapping(bytes32 loginHash => bool published) public publishedLoginHash;
    mapping(bytes32 proposalId => Proposal proposal) public proposals;
    mapping(bytes32 proposalId => mapping(bytes32 loginHash => bool approved)) public hasApproved;

    event LoginListPublished(bytes32 indexed loginRoot, uint256 loginCount);
    event EmergencyChangeProposed(
        bytes32 indexed proposalId, address indexed proposer, bytes32 indexed proposerLoginHash, address newEmergency
    );
    event ProposalApproved(
        bytes32 indexed proposalId, bytes32 indexed loginHash, address indexed owner, uint256 approvals
    );
    event ProposalApprovalRevoked(
        bytes32 indexed proposalId, bytes32 indexed loginHash, address indexed owner, uint256 approvals
    );
    event ProposalCancelled(bytes32 indexed proposalId, address indexed by, bytes32 indexed loginHash);
    event ProposalExecuted(bytes32 indexed proposalId, address indexed by, address indexed newEmergency);

    error InvalidWallet();
    /// @dev Reverts when `wallet_` does not list this contract as its GUARDIAN on IBaseMERAWallet.
    error TargetWalletGuardianMismatch();
    error InvalidLoginRegistry();
    error InvalidLoginRoot();
    error InvalidThreshold();
    /// @dev `proposalLifetime_` must be at least `MIN_PROPOSAL_LIFETIME`.
    error InvalidProposalLifetime();
    error EmptyLoginList();
    error LoginListAlreadyPublished();
    error DuplicateLoginHash(bytes32 loginHash);
    error LoginRootMismatch(bytes32 expected, bytes32 actual);
    error LoginListTooSmall(uint256 loginCount, uint256 threshold);
    error LoginListNotPublished();
    error InvalidEmergency();
    error LoginNotEligible(address owner, bytes32 loginHash);
    error ProposalNotFound(bytes32 proposalId);
    error ProposalExpired(bytes32 proposalId, uint256 deadline, uint256 currentTime);
    error ProposalAlreadyExecuted(bytes32 proposalId);
    error ProposalIsCancelled(bytes32 proposalId);
    error AlreadyApproved(bytes32 proposalId, bytes32 loginHash);
    error NotApproved(bytes32 proposalId, bytes32 loginHash);
    error ThresholdNotReached(bytes32 proposalId, uint256 approvals, uint256 threshold);

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

    function publishLoginList(bytes32[] calldata loginHashes) external {
        require(!loginListPublished, LoginListAlreadyPublished());

        uint256 loginCount = loginHashes.length;
        require(loginCount != 0, EmptyLoginList());
        require(loginCount >= THRESHOLD, LoginListTooSmall(loginCount, THRESHOLD));

        bytes32 root = _computeRoot(loginHashes);
        require(root == LOGIN_ROOT, LoginRootMismatch(LOGIN_ROOT, root));

        for (uint256 i = 0; i < loginCount;) {
            bytes32 loginHash = loginHashes[i];
            require(!publishedLoginHash[loginHash], DuplicateLoginHash(loginHash));
            publishedLoginHash[loginHash] = true;
            unchecked {
                ++i;
            }
        }

        loginListPublished = true;
        emit LoginListPublished(LOGIN_ROOT, loginCount);
    }

    function proposeEmergencyChange(address wallet_, address newEmergency) external returns (bytes32 proposalId) {
        require(wallet_ != address(0), InvalidWallet());
        require(newEmergency != address(0), InvalidEmergency());

        bytes32 loginHash = _requireEligibleLoginOwner(msg.sender);
        require(IBaseMERAWallet(payable(wallet_)).GUARDIAN() == address(this), TargetWalletGuardianMismatch());

        uint256 nonce = proposalNonce;
        proposalId = keccak256(abi.encode(wallet_, newEmergency, nonce));
        proposalNonce = nonce + 1;

        Proposal storage proposal = proposals[proposalId];
        proposal.targetWallet = wallet_;
        proposal.newEmergency = newEmergency;
        proposal.proposer = msg.sender;
        proposal.createdAt = uint64(block.timestamp);
        proposal.deadline = uint64(block.timestamp) + PROPOSAL_LIFETIME;
        proposal.approvals = 1;

        hasApproved[proposalId][loginHash] = true;

        emit EmergencyChangeProposed(proposalId, msg.sender, loginHash, newEmergency);
        emit ProposalApproved(proposalId, loginHash, msg.sender, 1);
    }

    function approveProposal(bytes32 proposalId) external {
        bytes32 loginHash = _requireEligibleLoginOwner(msg.sender);
        Proposal storage proposal = _activeProposal(proposalId);
        require(!hasApproved[proposalId][loginHash], AlreadyApproved(proposalId, loginHash));

        hasApproved[proposalId][loginHash] = true;
        proposal.approvals += 1;
        emit ProposalApproved(proposalId, loginHash, msg.sender, proposal.approvals);
    }

    function revokeApproval(bytes32 proposalId) external {
        bytes32 loginHash = _requireEligibleLoginOwner(msg.sender);
        Proposal storage proposal = _activeProposal(proposalId);
        require(hasApproved[proposalId][loginHash], NotApproved(proposalId, loginHash));

        hasApproved[proposalId][loginHash] = false;
        proposal.approvals -= 1;
        emit ProposalApprovalRevoked(proposalId, loginHash, msg.sender, proposal.approvals);
    }

    function cancelProposal(bytes32 proposalId) external {
        bytes32 loginHash = _requireEligibleLoginOwner(msg.sender);
        Proposal storage proposal = _activeProposal(proposalId);

        proposal.cancelled = true;
        emit ProposalCancelled(proposalId, msg.sender, loginHash);
    }

    function executeProposal(bytes32 proposalId) external {
        Proposal storage proposal = _activeProposal(proposalId);
        require(proposal.approvals >= THRESHOLD, ThresholdNotReached(proposalId, proposal.approvals, THRESHOLD));

        proposal.executed = true;
        IBaseMERAWallet(payable(proposal.targetWallet)).setEmergency(proposal.newEmergency);
        emit ProposalExecuted(proposalId, msg.sender, proposal.newEmergency);
    }

    function _requireEligibleLoginOwner(address owner) internal view returns (bytes32 loginHash) {
        require(loginListPublished, LoginListNotPublished());

        loginHash = LOGIN_REGISTRY.loginHashByWallet(owner);
        require(
            loginHash != bytes32(0) && publishedLoginHash[loginHash]
                && LOGIN_REGISTRY.walletByLoginHash(loginHash) == owner,
            LoginNotEligible(owner, loginHash)
        );
    }

    function _activeProposal(bytes32 proposalId) internal view returns (Proposal storage proposal) {
        proposal = proposals[proposalId];
        require(proposal.createdAt != 0, ProposalNotFound(proposalId));
        require(!proposal.executed, ProposalAlreadyExecuted(proposalId));
        require(!proposal.cancelled, ProposalIsCancelled(proposalId));
        require(block.timestamp <= proposal.deadline, ProposalExpired(proposalId, proposal.deadline, block.timestamp));
    }

    function _computeRoot(bytes32[] calldata loginHashes) internal pure returns (bytes32 root) {
        uint256 levelLength = loginHashes.length;
        bytes32[] memory level = new bytes32[](levelLength);
        for (uint256 i = 0; i < levelLength;) {
            level[i] = loginHashes[i];
            unchecked {
                ++i;
            }
        }

        while (levelLength > 1) {
            uint256 nextLength = (levelLength + 1) >> 1;
            for (uint256 i = 0; i < nextLength;) {
                uint256 pairIndex = i << 1;
                if (pairIndex + 1 < levelLength) {
                    level[i] = Hashes.commutativeKeccak256(level[pairIndex], level[pairIndex + 1]);
                } else {
                    level[i] = level[pairIndex];
                }
                unchecked {
                    ++i;
                }
            }
            levelLength = nextLength;
        }

        return level[0];
    }
}
