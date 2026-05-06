// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {MERAWalletLoginRegistry} from "../src/MERAWalletLoginRegistry.sol";
import {MERAWalletLoginMerkleGuardian} from "../src/guardian/MERAWalletLoginMerkleGuardian.sol";
import {Hashes} from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

contract MERAWalletLoginMerkleGuardianTest is Test {
    address internal owner = address(0xAD111);
    address internal primary = vm.addr(0xA11CE);
    address internal backup = vm.addr(0xB0B);
    address internal emergency = vm.addr(0xE911);

    BaseMERAWallet internal aliceWallet;
    BaseMERAWallet internal bobWallet;
    BaseMERAWallet internal carolWallet;
    BaseMERAWallet internal daveWallet;
    BaseMERAWallet internal erinWallet;
    address internal outsider = vm.addr(0x4444);
    address internal guardianAddress = address(0xA11CEB0BCAFE);

    uint64 internal constant PROPOSAL_LIFETIME = 3 days;

    BaseMERAWallet internal wallet;
    MERAWalletLoginRegistry internal registry;
    MERAWalletLoginMerkleGuardian internal guardian;
    bytes32[] internal loginHashes;
    bytes32 internal loginRoot;

    function setUp() public {
        registry = new MERAWalletLoginRegistry(owner);
        vm.prank(owner);
        registry.addFactory(address(this));

        aliceWallet = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddress);
        bobWallet = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddress);
        carolWallet = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddress);
        daveWallet = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddress);
        erinWallet = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddress);

        _registerDefaultLogins();
        loginRoot = _computeRoot(loginHashes);

        wallet = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddress);
        MERAWalletLoginMerkleGuardian guardianImpl =
            new MERAWalletLoginMerkleGuardian(address(registry), loginRoot, 2, PROPOSAL_LIFETIME);
        vm.etch(guardianAddress, address(guardianImpl).code);
        guardian = MERAWalletLoginMerkleGuardian(guardianAddress);
    }

    function test_PublishLoginList_Succeeds() public {
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(loginHashes, _proofs(loginHashes));

        assertTrue(guardian.loginListPublished());
        assertEq(guardian.publishedLoginCount(), 3);
        assertTrue(guardian.publishedLoginHash(_loginHash("alice")));
        assertTrue(guardian.publishedLoginHash(_loginHash("bob")));
        assertTrue(guardian.publishedLoginHash(_loginHash("carol")));
    }

    function test_PublishLoginList_SupportsOneByOneTopUp() public {
        bytes32[] memory aliceOnly = _singleHash(_loginHash("alice"));
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(aliceOnly, _proofs(aliceOnly));

        assertTrue(guardian.loginListPublished());
        assertEq(guardian.publishedLoginCount(), 1);
        assertTrue(guardian.publishedLoginHash(_loginHash("alice")));
        assertFalse(guardian.publishedLoginHash(_loginHash("bob")));

        bytes32[] memory bobOnly = _singleHash(_loginHash("bob"));
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(bobOnly, _proofs(bobOnly));

        assertEq(guardian.publishedLoginCount(), 2);
        assertTrue(guardian.publishedLoginHash(_loginHash("bob")));
    }

    function test_PublishLoginList_RejectsEmptyList() public {
        bytes32[] memory empty = new bytes32[](0);
        bytes32[][] memory emptyProofs = new bytes32[][](0);

        vm.expectRevert(MERAWalletLoginMerkleGuardian.EmptyLoginList.selector);
        guardian.publishLoginList(empty, emptyProofs);
    }

    function test_PublishLoginList_RejectsProofCountMismatch() public {
        bytes32[] memory oneLogin = _singleHash(_loginHash("alice"));
        bytes32[][] memory emptyProofs = new bytes32[][](0);

        vm.expectRevert(abi.encodeWithSelector(MERAWalletLoginMerkleGuardian.LoginProofCountMismatch.selector, 1, 0));
        guardian.publishLoginList(oneLogin, emptyProofs);
    }

    function test_PublishLoginList_RejectsInvalidProof() public {
        bytes32[] memory carolOnly = _singleHash(_loginHash("carol"));
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = _proofs(_singleHash(_loginHash("alice")))[0];

        vm.prank(address(carolWallet));
        vm.expectRevert(
            abi.encodeWithSelector(MERAWalletLoginMerkleGuardian.InvalidLoginProof.selector, _loginHash("carol"))
        );
        guardian.publishLoginList(carolOnly, proofs);
    }

    function test_PublishLoginList_RejectsDuplicates() public {
        bytes32[] memory duplicates = new bytes32[](2);
        duplicates[0] = _loginHash("alice");
        duplicates[1] = _loginHash("alice");
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = _proofs(_singleHash(_loginHash("alice")))[0];
        proofs[1] = proofs[0];

        vm.expectRevert(
            abi.encodeWithSelector(MERAWalletLoginMerkleGuardian.DuplicateLoginHash.selector, _loginHash("alice"))
        );
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(duplicates, proofs);
    }

    function test_PublishLoginList_RejectsAlreadyPublishedLogin() public {
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(_singleHash(_loginHash("alice")), _proofs(_singleHash(_loginHash("alice"))));

        vm.expectRevert(
            abi.encodeWithSelector(MERAWalletLoginMerkleGuardian.DuplicateLoginHash.selector, _loginHash("alice"))
        );
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(_singleHash(_loginHash("alice")), _proofs(_singleHash(_loginHash("alice"))));
    }

    function test_PublishLoginList_RejectsUnregisteredPublisher() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(MERAWalletLoginMerkleGuardian.PublisherNotRegistered.selector, outsider));
        guardian.publishLoginList(loginHashes, _proofs(loginHashes));
    }

    function test_PublishLoginList_RejectsPublisherNotInList() public {
        bytes32[] memory aliceCarol = new bytes32[](2);
        aliceCarol[0] = _loginHash("alice");
        aliceCarol[1] = _loginHash("carol");

        vm.prank(address(bobWallet));
        vm.expectRevert(
            abi.encodeWithSelector(
                MERAWalletLoginMerkleGuardian.PublisherNotInLoginList.selector, address(bobWallet), _loginHash("bob")
            )
        );
        guardian.publishLoginList(aliceCarol, _proofs(aliceCarol));
    }

    function test_PublishLoginList_SupportsOZCompatibleOddLengthTree() public {
        bytes32[] memory fiveLogins = new bytes32[](5);
        fiveLogins[0] = _loginHash("alice");
        fiveLogins[1] = _loginHash("bob");
        fiveLogins[2] = _loginHash("carol");
        fiveLogins[3] = _loginHash("dave");
        fiveLogins[4] = _loginHash("erin");

        _registerLogin("dave", address(daveWallet));
        _registerLogin("erin", address(erinWallet));

        bytes32 expectedRoot = Hashes.commutativeKeccak256(
            Hashes.commutativeKeccak256(Hashes.commutativeKeccak256(fiveLogins[0], fiveLogins[1]), fiveLogins[4]),
            Hashes.commutativeKeccak256(fiveLogins[2], fiveLogins[3])
        );
        bytes32 ozCompatibleRoot = _computeRoot(fiveLogins);
        MERAWalletLoginMerkleGuardian fiveLoginGuardian =
            new MERAWalletLoginMerkleGuardian(address(registry), ozCompatibleRoot, 2, PROPOSAL_LIFETIME);

        assertEq(ozCompatibleRoot, expectedRoot);

        vm.prank(address(aliceWallet));
        fiveLoginGuardian.publishLoginList(fiveLogins, _proofsForTree(fiveLogins, fiveLogins));

        assertTrue(fiveLoginGuardian.loginListPublished());
        assertEq(fiveLoginGuardian.publishedLoginCount(), 5);
        assertTrue(fiveLoginGuardian.publishedLoginHash(_loginHash("erin")));
    }

    function test_Propose_AutoApprovesCurrentLoginOwner() public {
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(loginHashes, _proofs(loginHashes));
        address newEmergency = address(0xE0001);

        vm.prank(address(aliceWallet));
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), newEmergency);

        (address target, address storedEmergency, address proposer,, uint16 approvals,) = guardian.proposals(proposalId);
        assertEq(target, address(wallet));
        assertEq(storedEmergency, newEmergency);
        assertEq(proposer, address(aliceWallet));
        assertEq(approvals, 1);
        assertTrue(guardian.hasApproved(proposalId, _loginHash("alice")));
    }

    function test_Approve_ExecuteChangesEmergencyWhenThresholdReached() public {
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(loginHashes, _proofs(loginHashes));
        address newEmergency = address(0xE0002);

        vm.prank(address(aliceWallet));
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), newEmergency);
        vm.prank(address(bobWallet));
        guardian.approveProposal(proposalId);

        vm.prank(outsider);
        guardian.executeProposal(proposalId);

        assertEq(wallet.emergency(), newEmergency);
    }

    function test_Propose_RevertsBeforeLoginListPublished() public {
        vm.prank(address(aliceWallet));
        vm.expectRevert(MERAWalletLoginMerkleGuardian.LoginListNotPublished.selector);
        guardian.proposeEmergencyChange(address(wallet), address(0xE0003));
    }

    function test_Approve_RequiresCurrentRegisteredOwner() public {
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(loginHashes, _proofs(loginHashes));

        vm.prank(address(aliceWallet));
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), address(0xE0004));

        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(MERAWalletLoginMerkleGuardian.LoginNotEligible.selector, outsider, bytes32(0))
        );
        guardian.approveProposal(proposalId);
    }

    function test_Approve_SameLoginCannotApproveTwiceAfterTransfer() public {
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(loginHashes, _proofs(loginHashes));
        BaseMERAWallet newAliceWallet = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddress);

        vm.prank(address(aliceWallet));
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), address(0xE0005));
        _migrateLogin("alice", address(aliceWallet), "alice-new", address(newAliceWallet));

        vm.prank(address(newAliceWallet));
        vm.expectRevert(
            abi.encodeWithSelector(
                MERAWalletLoginMerkleGuardian.AlreadyApproved.selector, proposalId, _loginHash("alice")
            )
        );
        guardian.approveProposal(proposalId);
    }

    function test_TransferLogin_NewOwnerCanApproveAndRevoke() public {
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(loginHashes, _proofs(loginHashes));
        BaseMERAWallet newBobWallet = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddress);

        vm.prank(address(aliceWallet));
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), address(0xE0006));
        _migrateLogin("bob", address(bobWallet), "bob-new", address(newBobWallet));

        vm.prank(address(newBobWallet));
        guardian.approveProposal(proposalId);
        assertTrue(guardian.hasApproved(proposalId, _loginHash("bob")));

        vm.prank(address(newBobWallet));
        guardian.revokeApproval(proposalId);
        assertFalse(guardian.hasApproved(proposalId, _loginHash("bob")));

        (,,,, uint16 approvals,) = guardian.proposals(proposalId);
        assertEq(approvals, 1);
    }

    function test_Execute_BeforeThresholdReverts() public {
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(loginHashes, _proofs(loginHashes));

        vm.prank(address(aliceWallet));
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), address(0xE0007));

        vm.expectRevert(
            abi.encodeWithSelector(MERAWalletLoginMerkleGuardian.ThresholdNotReached.selector, proposalId, 1, 2)
        );
        guardian.executeProposal(proposalId);
    }

    function test_Execute_AfterLifetimeReverts() public {
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(loginHashes, _proofs(loginHashes));

        vm.prank(address(aliceWallet));
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), address(0xE0008));
        vm.prank(address(bobWallet));
        guardian.approveProposal(proposalId);

        (,,, uint64 createdAt,,) = guardian.proposals(proposalId);
        uint256 expiresAt = uint256(createdAt) + PROPOSAL_LIFETIME;
        vm.warp(block.timestamp + PROPOSAL_LIFETIME + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                MERAWalletLoginMerkleGuardian.ProposalExpired.selector, proposalId, expiresAt, block.timestamp
            )
        );
        guardian.executeProposal(proposalId);
    }

    function test_Execute_SecondTimeReverts() public {
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(loginHashes, _proofs(loginHashes));

        vm.prank(address(aliceWallet));
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), address(0xE0010));
        vm.prank(address(bobWallet));
        guardian.approveProposal(proposalId);
        guardian.executeProposal(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(MERAWalletLoginMerkleGuardian.ProposalAlreadyExecuted.selector, proposalId)
        );
        guardian.executeProposal(proposalId);
    }

    function test_ConstructorValidation() public {
        vm.expectRevert(MERAWalletLoginMerkleGuardian.InvalidLoginRegistry.selector);
        new MERAWalletLoginMerkleGuardian(address(0x1234), loginRoot, 1, PROPOSAL_LIFETIME);

        vm.expectRevert(MERAWalletLoginMerkleGuardian.InvalidLoginRoot.selector);
        new MERAWalletLoginMerkleGuardian(address(registry), bytes32(0), 1, PROPOSAL_LIFETIME);

        vm.expectRevert(MERAWalletLoginMerkleGuardian.InvalidThreshold.selector);
        new MERAWalletLoginMerkleGuardian(address(registry), loginRoot, 0, PROPOSAL_LIFETIME);

        vm.expectRevert(MERAWalletLoginMerkleGuardian.InvalidProposalLifetime.selector);
        new MERAWalletLoginMerkleGuardian(address(registry), loginRoot, 1, 0);

        vm.expectRevert(MERAWalletLoginMerkleGuardian.InvalidProposalLifetime.selector);
        new MERAWalletLoginMerkleGuardian(address(registry), loginRoot, 1, uint64(71 hours));
    }

    function test_Propose_RevertsWhenTargetWalletIsZero() public {
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(loginHashes, _proofs(loginHashes));

        vm.prank(address(aliceWallet));
        vm.expectRevert(MERAWalletLoginMerkleGuardian.InvalidWallet.selector);
        guardian.proposeEmergencyChange(address(0), address(0xE0011));
    }

    function test_Propose_RevertsWhenTargetWalletGuardianMismatch() public {
        vm.prank(address(aliceWallet));
        guardian.publishLoginList(loginHashes, _proofs(loginHashes));
        BaseMERAWallet otherWallet = new BaseMERAWallet(primary, backup, emergency, address(0), address(0xBEEF));

        vm.prank(address(aliceWallet));
        vm.expectRevert(MERAWalletLoginMerkleGuardian.TargetWalletGuardianMismatch.selector);
        guardian.proposeEmergencyChange(address(otherWallet), address(0xE0012));
    }

    function _registerDefaultLogins() internal {
        loginHashes.push(_loginHash("alice"));
        loginHashes.push(_loginHash("bob"));
        loginHashes.push(_loginHash("carol"));

        _registerLogin("alice", address(aliceWallet));
        _registerLogin("bob", address(bobWallet));
        _registerLogin("carol", address(carolWallet));
    }

    function _migrateLogin(string memory oldLogin, address oldWallet, string memory newLogin, address newWallet)
        internal
    {
        _registerLogin(newLogin, newWallet);
        vm.prank(oldWallet);
        registry.requestLoginMigration(oldLogin, newLogin, newWallet);
        vm.prank(newWallet);
        registry.confirmLoginMigration(oldLogin);
    }

    function _registerLogin(string memory login, address wallet_) internal {
        bytes32 secret = keccak256(abi.encode(login, wallet_));
        registry.commit(registry.makeCommitment(login, wallet_, address(this), secret, 0, keccak256("")));
        vm.warp(block.timestamp + registry.MIN_COMMITMENT_AGE());
        registry.registerLogin{value: registry.priceOf(login)}(login, wallet_, secret, 0, "");
    }

    function _loginHash(string memory login) internal pure returns (bytes32) {
        return keccak256(bytes(login));
    }

    function _singleHash(bytes32 loginHash) internal pure returns (bytes32[] memory hashes) {
        hashes = new bytes32[](1);
        hashes[0] = loginHash;
    }

    function _proofs(bytes32[] memory hashes) internal view returns (bytes32[][] memory proofs) {
        bytes32[] memory allHashes = new bytes32[](loginHashes.length);
        for (uint256 i = 0; i < loginHashes.length; ++i) {
            allHashes[i] = loginHashes[i];
        }
        proofs = _proofsForTree(allHashes, hashes);
    }

    function _proofsForTree(bytes32[] memory allHashes, bytes32[] memory hashes)
        internal
        pure
        returns (bytes32[][] memory proofs)
    {
        bytes32[] memory heap = _buildHeap(allHashes);
        proofs = new bytes32[][](hashes.length);
        for (uint256 i = 0; i < hashes.length; ++i) {
            proofs[i] = _proofForHash(allHashes, heap, hashes[i]);
        }
    }

    function _buildHeap(bytes32[] memory hashes) internal pure returns (bytes32[] memory heap) {
        uint256 leafCount = hashes.length;
        uint256 treeLength = (leafCount << 1) - 1;
        uint256 internalCount = leafCount - 1;
        heap = new bytes32[](treeLength);

        for (uint256 i = internalCount; i < treeLength; ++i) {
            heap[i] = hashes[treeLength - 1 - i];
        }
        for (uint256 i = internalCount; i > 0;) {
            unchecked {
                --i;
            }
            heap[i] = Hashes.commutativeKeccak256(heap[(i << 1) + 1], heap[(i << 1) + 2]);
        }
    }

    function _proofForHash(bytes32[] memory hashes, bytes32[] memory heap, bytes32 loginHash)
        internal
        pure
        returns (bytes32[] memory proof)
    {
        uint256 leafIndex = type(uint256).max;
        for (uint256 i = 0; i < hashes.length; ++i) {
            if (hashes[i] == loginHash) {
                leafIndex = i;
                break;
            }
        }
        require(leafIndex != type(uint256).max, "missing hash");

        uint256 nodeIndex = heap.length - 1 - leafIndex;
        uint256 proofLength;
        for (uint256 cursor = nodeIndex; cursor != 0; cursor = (cursor - 1) >> 1) {
            ++proofLength;
        }

        proof = new bytes32[](proofLength);
        for (uint256 cursor = nodeIndex; cursor != 0; cursor = (cursor - 1) >> 1) {
            uint256 parent = (cursor - 1) >> 1;
            uint256 left = (parent << 1) + 1;
            uint256 sibling = cursor == left ? left + 1 : left;
            proof[proofLength - _remainingDepth(cursor)] = heap[sibling];
        }
    }

    function _remainingDepth(uint256 nodeIndex) internal pure returns (uint256 depth) {
        for (uint256 cursor = nodeIndex; cursor != 0; cursor = (cursor - 1) >> 1) {
            ++depth;
        }
    }

    function _computeRoot(bytes32[] memory hashes) internal pure returns (bytes32 root) {
        uint256 leafCount = hashes.length;
        uint256 internalCount = leafCount - 1;
        if (internalCount == 0) {
            return hashes[0];
        }

        bytes32[] memory nodes = new bytes32[](internalCount);
        uint256 treeLength = (leafCount << 1) - 1;

        for (uint256 i = internalCount; i > 0;) {
            unchecked {
                --i;
            }
            uint256 leftIndex = (i << 1) + 1;
            uint256 rightIndex = leftIndex + 1;
            bytes32 left = leftIndex < internalCount ? nodes[leftIndex] : hashes[treeLength - 1 - leftIndex];
            bytes32 right = rightIndex < internalCount ? nodes[rightIndex] : hashes[treeLength - 1 - rightIndex];
            nodes[i] = Hashes.commutativeKeccak256(left, right);
        }

        return nodes[0];
    }
}
