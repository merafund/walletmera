// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IBaseMERAWallet} from "../interfaces/IBaseMERAWallet.sol";

/// @notice Threshold guardian for emergency recovery: N-of-M members approve, then execute separately before deadline.
contract MERAWalletThresholdGuardian {
    uint64 public constant MAX_DEADLINE_FROM_NOW = 30 days;

    struct Proposal {
        address newEmergency;
        address proposer;
        uint64 createdAt;
        uint64 deadline;
        uint16 approvals;
        bool executed;
        bool cancelled;
    }

    error InvalidWallet();
    error WalletAlreadySet(address wallet);
    error InvalidThreshold();
    error InvalidMember();
    error DuplicateMember(address member);
    error NotMember();
    error InvalidEmergency();
    error InvalidDeadline();
    error ProposalNotFound(bytes32 proposalId);
    error ProposalExpired(bytes32 proposalId, uint256 deadline, uint256 currentTime);
    error ProposalAlreadyExecuted(bytes32 proposalId);
    error ProposalIsCancelled(bytes32 proposalId);
    error AlreadyApproved(bytes32 proposalId, address member);
    error NotApproved(bytes32 proposalId, address member);
    error ThresholdNotReached(bytes32 proposalId, uint256 approvals, uint256 threshold);

    event WalletSet(address indexed wallet, address indexed caller);
    event EmergencyChangeProposed(
        bytes32 indexed proposalId, address indexed proposer, address indexed newEmergency, uint256 deadline
    );
    event ProposalApproved(bytes32 indexed proposalId, address indexed member, uint256 approvals);
    event ProposalApprovalRevoked(bytes32 indexed proposalId, address indexed member, uint256 approvals);
    event ProposalCancelled(bytes32 indexed proposalId, address indexed by);
    event ProposalExecuted(bytes32 indexed proposalId, address indexed by, address indexed newEmergency);

    address public wallet;
    uint256 public immutable threshold;
    address[] internal _members;

    uint256 public proposalNonce;

    mapping(address member => bool isMember) public isMember;
    mapping(bytes32 proposalId => Proposal proposal) public proposals;
    mapping(bytes32 proposalId => mapping(address member => bool approved)) public hasApproved;

    constructor(address wallet_, uint256 threshold_, address[] memory members_) {
        if (threshold_ == 0 || threshold_ > members_.length) {
            revert InvalidThreshold();
        }

        uint256 membersLength = members_.length;
        for (uint256 i = 0; i < membersLength;) {
            address member = members_[i];
            if (member == address(0)) {
                revert InvalidMember();
            }
            if (isMember[member]) {
                revert DuplicateMember(member);
            }
            isMember[member] = true;
            _members.push(member);
            unchecked {
                ++i;
            }
        }

        if (wallet_ != address(0)) {
            wallet = wallet_;
            emit WalletSet(wallet_, msg.sender);
        }
        threshold = threshold_;
    }

    function getMembers() external view returns (address[] memory) {
        return _members;
    }

    function setWallet(address wallet_) external {
        _requireMember();
        if (wallet_ == address(0)) {
            revert InvalidWallet();
        }
        if (wallet != address(0)) {
            revert WalletAlreadySet(wallet);
        }
        wallet = wallet_;
        emit WalletSet(wallet_, msg.sender);
    }

    function proposeEmergencyChange(address newEmergency, uint64 deadline) external returns (bytes32 proposalId) {
        _requireMember();
        if (wallet == address(0)) {
            revert InvalidWallet();
        }
        if (newEmergency == address(0)) {
            revert InvalidEmergency();
        }
        if (deadline <= block.timestamp) {
            revert InvalidDeadline();
        }
        if (deadline > block.timestamp + MAX_DEADLINE_FROM_NOW) {
            revert InvalidDeadline();
        }

        uint256 nonce = proposalNonce;
        proposalId = keccak256(abi.encode(wallet, newEmergency, nonce));
        proposalNonce = nonce + 1;

        Proposal storage proposal = proposals[proposalId];
        proposal.newEmergency = newEmergency;
        proposal.proposer = msg.sender;
        proposal.createdAt = uint64(block.timestamp);
        proposal.deadline = deadline;

        emit EmergencyChangeProposed(proposalId, msg.sender, newEmergency, deadline);
    }

    function approveProposal(bytes32 proposalId) external {
        _requireMember();
        Proposal storage proposal = _activeProposal(proposalId);

        if (hasApproved[proposalId][msg.sender]) {
            revert AlreadyApproved(proposalId, msg.sender);
        }

        hasApproved[proposalId][msg.sender] = true;
        proposal.approvals += 1;
        emit ProposalApproved(proposalId, msg.sender, proposal.approvals);
    }

    function revokeApproval(bytes32 proposalId) external {
        _requireMember();
        Proposal storage proposal = _activeProposal(proposalId);

        if (!hasApproved[proposalId][msg.sender]) {
            revert NotApproved(proposalId, msg.sender);
        }

        hasApproved[proposalId][msg.sender] = false;
        proposal.approvals -= 1;
        emit ProposalApprovalRevoked(proposalId, msg.sender, proposal.approvals);
    }

    function cancelProposal(bytes32 proposalId) external {
        _requireMember();
        Proposal storage proposal = _activeProposal(proposalId);

        // Any member can cancel stale or compromised proposal before execution.
        proposal.cancelled = true;
        emit ProposalCancelled(proposalId, msg.sender);
    }

    function executeProposal(bytes32 proposalId) external {
        Proposal storage proposal = _activeProposal(proposalId);
        if (proposal.approvals < threshold) {
            revert ThresholdNotReached(proposalId, proposal.approvals, threshold);
        }

        proposal.executed = true;
        IBaseMERAWallet(payable(wallet)).setEmergency(proposal.newEmergency);
        emit ProposalExecuted(proposalId, msg.sender, proposal.newEmergency);
    }

    function _requireMember() internal view {
        if (!isMember[msg.sender]) {
            revert NotMember();
        }
    }

    function _activeProposal(bytes32 proposalId) internal view returns (Proposal storage proposal) {
        proposal = proposals[proposalId];
        if (proposal.createdAt == 0) {
            revert ProposalNotFound(proposalId);
        }
        if (proposal.executed) {
            revert ProposalAlreadyExecuted(proposalId);
        }
        if (proposal.cancelled) {
            revert ProposalIsCancelled(proposalId);
        }
        if (block.timestamp > proposal.deadline) {
            revert ProposalExpired(proposalId, proposal.deadline, block.timestamp);
        }
    }
}
