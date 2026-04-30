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

    address internal aliceWallet = vm.addr(0xA11);
    address internal bobWallet = vm.addr(0xB0B1);
    address internal carolWallet = vm.addr(0xCA);
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

        _registerDefaultLogins();
        loginRoot = _computeRoot(loginHashes);

        wallet = new BaseMERAWallet(primary, backup, emergency, address(0), guardianAddress);
        MERAWalletLoginMerkleGuardian guardianImpl =
            new MERAWalletLoginMerkleGuardian(address(registry), loginRoot, 2, PROPOSAL_LIFETIME);
        vm.etch(guardianAddress, address(guardianImpl).code);
        guardian = MERAWalletLoginMerkleGuardian(guardianAddress);
    }

    function test_PublishLoginList_Succeeds() public {
        guardian.publishLoginList(loginHashes);

        assertTrue(guardian.loginListPublished());
        assertTrue(guardian.publishedLoginHash(_loginHash("alice")));
        assertTrue(guardian.publishedLoginHash(_loginHash("bob")));
        assertTrue(guardian.publishedLoginHash(_loginHash("carol")));
    }

    function test_PublishLoginList_RejectsEmptyList() public {
        bytes32[] memory empty = new bytes32[](0);

        vm.expectRevert(MERAWalletLoginMerkleGuardian.EmptyLoginList.selector);
        guardian.publishLoginList(empty);
    }

    function test_PublishLoginList_RejectsWrongTreeOrder() public {
        bytes32[] memory wrongOrder = new bytes32[](3);
        wrongOrder[0] = _loginHash("alice");
        wrongOrder[1] = _loginHash("carol");
        wrongOrder[2] = _loginHash("bob");

        vm.expectRevert(
            abi.encodeWithSelector(
                MERAWalletLoginMerkleGuardian.LoginRootMismatch.selector, loginRoot, _computeRoot(wrongOrder)
            )
        );
        guardian.publishLoginList(wrongOrder);
    }

    function test_PublishLoginList_RejectsDuplicates() public {
        bytes32[] memory duplicates = new bytes32[](2);
        duplicates[0] = _loginHash("alice");
        duplicates[1] = _loginHash("alice");
        bytes32 duplicateRoot = _computeRoot(duplicates);

        MERAWalletLoginMerkleGuardian duplicateGuardian =
            new MERAWalletLoginMerkleGuardian(address(registry), duplicateRoot, 1, PROPOSAL_LIFETIME);

        vm.expectRevert(
            abi.encodeWithSelector(MERAWalletLoginMerkleGuardian.DuplicateLoginHash.selector, _loginHash("alice"))
        );
        duplicateGuardian.publishLoginList(duplicates);
    }

    function test_PublishLoginList_RejectsSecondPublish() public {
        guardian.publishLoginList(loginHashes);

        vm.expectRevert(MERAWalletLoginMerkleGuardian.LoginListAlreadyPublished.selector);
        guardian.publishLoginList(loginHashes);
    }

    function test_PublishLoginList_RejectsListBelowThreshold() public {
        bytes32[] memory oneLogin = new bytes32[](1);
        oneLogin[0] = _loginHash("alice");
        MERAWalletLoginMerkleGuardian smallGuardian =
            new MERAWalletLoginMerkleGuardian(address(registry), oneLogin[0], 2, PROPOSAL_LIFETIME);

        vm.expectRevert(abi.encodeWithSelector(MERAWalletLoginMerkleGuardian.LoginListTooSmall.selector, 1, 2));
        smallGuardian.publishLoginList(oneLogin);
    }

    function test_Propose_AutoApprovesCurrentLoginOwner() public {
        guardian.publishLoginList(loginHashes);
        address newEmergency = address(0xE0001);

        vm.prank(aliceWallet);
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), newEmergency);

        (address target, address storedEmergency, address proposer,,, uint16 approvals,,) =
            guardian.proposals(proposalId);
        assertEq(target, address(wallet));
        assertEq(storedEmergency, newEmergency);
        assertEq(proposer, aliceWallet);
        assertEq(approvals, 1);
        assertTrue(guardian.hasApproved(proposalId, _loginHash("alice")));
    }

    function test_Approve_ExecuteChangesEmergencyWhenThresholdReached() public {
        guardian.publishLoginList(loginHashes);
        address newEmergency = address(0xE0002);

        vm.prank(aliceWallet);
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), newEmergency);
        vm.prank(bobWallet);
        guardian.approveProposal(proposalId);

        vm.prank(outsider);
        guardian.executeProposal(proposalId);

        assertEq(wallet.emergency(), newEmergency);
    }

    function test_Propose_RevertsBeforeLoginListPublished() public {
        vm.prank(aliceWallet);
        vm.expectRevert(MERAWalletLoginMerkleGuardian.LoginListNotPublished.selector);
        guardian.proposeEmergencyChange(address(wallet), address(0xE0003));
    }

    function test_Approve_RequiresCurrentRegisteredOwner() public {
        guardian.publishLoginList(loginHashes);

        vm.prank(aliceWallet);
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), address(0xE0004));

        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(MERAWalletLoginMerkleGuardian.LoginNotEligible.selector, outsider, bytes32(0))
        );
        guardian.approveProposal(proposalId);
    }

    function test_Approve_SameLoginCannotApproveTwiceAfterTransfer() public {
        guardian.publishLoginList(loginHashes);
        address newAliceWallet = vm.addr(0xA12);

        vm.prank(aliceWallet);
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), address(0xE0005));
        vm.prank(aliceWallet);
        registry.transferLogin("alice", newAliceWallet);

        vm.prank(newAliceWallet);
        vm.expectRevert(
            abi.encodeWithSelector(
                MERAWalletLoginMerkleGuardian.AlreadyApproved.selector, proposalId, _loginHash("alice")
            )
        );
        guardian.approveProposal(proposalId);
    }

    function test_TransferLogin_NewOwnerCanApproveAndRevoke() public {
        guardian.publishLoginList(loginHashes);
        address newBobWallet = vm.addr(0xB0B2);

        vm.prank(aliceWallet);
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), address(0xE0006));
        vm.prank(bobWallet);
        registry.transferLogin("bob", newBobWallet);

        vm.prank(newBobWallet);
        guardian.approveProposal(proposalId);
        assertTrue(guardian.hasApproved(proposalId, _loginHash("bob")));

        vm.prank(newBobWallet);
        guardian.revokeApproval(proposalId);
        assertFalse(guardian.hasApproved(proposalId, _loginHash("bob")));

        (,,,,, uint16 approvals,,) = guardian.proposals(proposalId);
        assertEq(approvals, 1);
    }

    function test_Execute_BeforeThresholdReverts() public {
        guardian.publishLoginList(loginHashes);

        vm.prank(aliceWallet);
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), address(0xE0007));

        vm.expectRevert(
            abi.encodeWithSelector(MERAWalletLoginMerkleGuardian.ThresholdNotReached.selector, proposalId, 1, 2)
        );
        guardian.executeProposal(proposalId);
    }

    function test_Execute_AfterLifetimeReverts() public {
        guardian.publishLoginList(loginHashes);

        vm.prank(aliceWallet);
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), address(0xE0008));
        vm.prank(bobWallet);
        guardian.approveProposal(proposalId);

        (,,,, uint64 deadline,,,) = guardian.proposals(proposalId);
        vm.warp(block.timestamp + PROPOSAL_LIFETIME + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                MERAWalletLoginMerkleGuardian.ProposalExpired.selector, proposalId, deadline, block.timestamp
            )
        );
        guardian.executeProposal(proposalId);
    }

    function test_Execute_AfterCancelReverts() public {
        guardian.publishLoginList(loginHashes);

        vm.prank(aliceWallet);
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), address(0xE0009));
        vm.prank(bobWallet);
        guardian.cancelProposal(proposalId);

        vm.expectRevert(abi.encodeWithSelector(MERAWalletLoginMerkleGuardian.ProposalIsCancelled.selector, proposalId));
        guardian.executeProposal(proposalId);
    }

    function test_Execute_SecondTimeReverts() public {
        guardian.publishLoginList(loginHashes);

        vm.prank(aliceWallet);
        bytes32 proposalId = guardian.proposeEmergencyChange(address(wallet), address(0xE0010));
        vm.prank(bobWallet);
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
        guardian.publishLoginList(loginHashes);

        vm.prank(aliceWallet);
        vm.expectRevert(MERAWalletLoginMerkleGuardian.InvalidWallet.selector);
        guardian.proposeEmergencyChange(address(0), address(0xE0011));
    }

    function test_Propose_RevertsWhenTargetWalletGuardianMismatch() public {
        guardian.publishLoginList(loginHashes);
        BaseMERAWallet otherWallet = new BaseMERAWallet(primary, backup, emergency, address(0), address(0xBEEF));

        vm.prank(aliceWallet);
        vm.expectRevert(MERAWalletLoginMerkleGuardian.TargetWalletGuardianMismatch.selector);
        guardian.proposeEmergencyChange(address(otherWallet), address(0xE0012));
    }

    function _registerDefaultLogins() internal {
        loginHashes.push(_loginHash("alice"));
        loginHashes.push(_loginHash("bob"));
        loginHashes.push(_loginHash("carol"));

        registry.registerLogin("alice", aliceWallet);
        registry.registerLogin("bob", bobWallet);
        registry.registerLogin("carol", carolWallet);
    }

    function _loginHash(string memory login) internal pure returns (bytes32) {
        return keccak256(bytes(login));
    }

    function _computeRoot(bytes32[] memory hashes) internal pure returns (bytes32 root) {
        uint256 levelLength = hashes.length;
        bytes32[] memory level = new bytes32[](levelLength);
        for (uint256 i = 0; i < levelLength;) {
            level[i] = hashes[i];
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
