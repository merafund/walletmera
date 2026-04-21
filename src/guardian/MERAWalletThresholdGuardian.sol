// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IBaseMERAWallet} from "../interfaces/IBaseMERAWallet.sol";

/// @notice Threshold guardian for emergency recovery: N-of-M members approve, then execute separately before deadline.
contract MERAWalletThresholdGuardian {
    struct Proposal {
        address newEmergency;
        address proposer;
        uint64 createdAt;
        uint64 deadline;
        uint16 approvals;
        bool executed;
        bool cancelled;
    }

    uint64 public constant MAX_DEADLINE_FROM_NOW = 30 days;

    address public wallet;
    uint256 public immutable THRESHOLD;
    address[] internal _members;

    uint256 public proposalNonce;

    mapping(address member => bool isMember) public isMember;
    mapping(bytes32 proposalId => Proposal proposal) public proposals;
    mapping(bytes32 proposalId => mapping(address member => bool approved)) public hasApproved;

    event WalletSet(address indexed wallet, address indexed caller);
    event EmergencyChangeProposed(
        bytes32 indexed proposalId, address indexed proposer, address indexed newEmergency, uint256 deadline
    );
    event ProposalApproved(bytes32 indexed proposalId, address indexed member, uint256 approvals);
    event ProposalApprovalRevoked(bytes32 indexed proposalId, address indexed member, uint256 approvals);
    event ProposalCancelled(bytes32 indexed proposalId, address indexed by);
    event ProposalExecuted(bytes32 indexed proposalId, address indexed by, address indexed newEmergency);

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

    constructor(address wallet_, uint256 threshold_, address[] memory members_) {
        require(threshold_ != 0 && threshold_ <= members_.length, InvalidThreshold());

        uint256 membersLength = members_.length;
        for (uint256 i = 0; i < membersLength;) {
            address member = members_[i];
            require(member != address(0), InvalidMember());
            require(!isMember[member], DuplicateMember(member));
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
        THRESHOLD = threshold_;
    }

    function setWallet(address wallet_) external {
        _requireMember();
        require(wallet_ != address(0), InvalidWallet());
        require(wallet == address(0), WalletAlreadySet(wallet));
        wallet = wallet_;
        emit WalletSet(wallet_, msg.sender);
    }

    function proposeEmergencyChange(address newEmergency, uint64 deadline) external returns (bytes32 proposalId) {
        _requireMember();
        require(wallet != address(0), InvalidWallet());
        require(newEmergency != address(0), InvalidEmergency());
        require(deadline > block.timestamp, InvalidDeadline());
        require(deadline <= block.timestamp + MAX_DEADLINE_FROM_NOW, InvalidDeadline());

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

        require(!hasApproved[proposalId][msg.sender], AlreadyApproved(proposalId, msg.sender));

        hasApproved[proposalId][msg.sender] = true;
        proposal.approvals += 1;
        emit ProposalApproved(proposalId, msg.sender, proposal.approvals);
    }

    function revokeApproval(bytes32 proposalId) external {
        _requireMember();
        Proposal storage proposal = _activeProposal(proposalId);

        require(hasApproved[proposalId][msg.sender], NotApproved(proposalId, msg.sender));

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
        require(proposal.approvals >= THRESHOLD, ThresholdNotReached(proposalId, proposal.approvals, THRESHOLD));

        proposal.executed = true;
        IBaseMERAWallet(payable(wallet)).setEmergency(proposal.newEmergency);
        emit ProposalExecuted(proposalId, msg.sender, proposal.newEmergency);
    }

    function getMembers() external view returns (address[] memory) {
        return _members;
    }

    function _requireMember() internal view {
        require(isMember[msg.sender], NotMember());
    }

    function _activeProposal(bytes32 proposalId) internal view returns (Proposal storage proposal) {
        proposal = proposals[proposalId];
        require(proposal.createdAt != 0, ProposalNotFound(proposalId));
        require(!proposal.executed, ProposalAlreadyExecuted(proposalId));
        require(!proposal.cancelled, ProposalIsCancelled(proposalId));
        require(block.timestamp <= proposal.deadline, ProposalExpired(proposalId, proposal.deadline, block.timestamp));
    }
}
