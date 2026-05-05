// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {MERAWalletThresholdGuardian} from "../src/guardian/MERAWalletThresholdGuardian.sol";
import {IBaseMERAWalletErrors} from "../src/interfaces/IBaseMERAWalletErrors.sol";

contract MERAWalletThresholdGuardianTest is Test {
    address internal primary = vm.addr(0xA11CE);
    address internal backup = vm.addr(0xB0B);
    address internal emergency = vm.addr(0xE911);

    address internal member1 = vm.addr(0x1111);
    address internal member2 = vm.addr(0x2222);
    address internal member3 = vm.addr(0x3333);
    address internal outsider = vm.addr(0x4444);

    BaseMERAWallet internal wallet;
    MERAWalletThresholdGuardian internal guardian;

    function setUp() public {
        address[] memory members = new address[](3);
        members[0] = member1;
        members[1] = member2;
        members[2] = member3;

        guardian = new MERAWalletThresholdGuardian(address(0), 2, members);
        wallet = new BaseMERAWallet(primary, backup, emergency, address(0), address(guardian));

        vm.prank(member1);
        guardian.setWallet(address(wallet));
    }

    function test_ExecuteProposal_ChangesEmergencyWhenNReached() public {
        address newEmergency = address(0xE0001);
        bytes32 proposalId = _propose(newEmergency, 1 days, member1);

        vm.prank(member1);
        guardian.approveProposal(proposalId);
        vm.prank(member2);
        guardian.approveProposal(proposalId);

        vm.prank(outsider);
        guardian.executeProposal(proposalId);

        assertEq(wallet.emergency(), newEmergency);
    }

    function test_NonMember_CannotProposeOrApprove() public {
        vm.prank(outsider);
        vm.expectRevert(MERAWalletThresholdGuardian.NotMember.selector);
        guardian.proposeEmergencyChange(address(0xE1001), uint64(block.timestamp + 1 days));

        bytes32 proposalId = _propose(address(0xE1002), 1 days, member1);
        vm.prank(outsider);
        vm.expectRevert(MERAWalletThresholdGuardian.NotMember.selector);
        guardian.approveProposal(proposalId);
    }

    function test_Approve_DuplicateReverts() public {
        bytes32 proposalId = _propose(address(0xE2001), 1 days, member1);

        vm.prank(member1);
        guardian.approveProposal(proposalId);
        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(MERAWalletThresholdGuardian.AlreadyApproved.selector, proposalId, member1)
        );
        guardian.approveProposal(proposalId);
    }

    function test_Execute_BeforeThresholdReverts() public {
        bytes32 proposalId = _propose(address(0xE3001), 1 days, member1);

        vm.prank(member1);
        guardian.approveProposal(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(MERAWalletThresholdGuardian.ThresholdNotReached.selector, proposalId, 1, 2)
        );
        guardian.executeProposal(proposalId);
    }

    function test_Execute_AfterDeadlineReverts() public {
        bytes32 proposalId = _propose(address(0xE4001), 1 hours, member1);

        vm.prank(member1);
        guardian.approveProposal(proposalId);
        vm.prank(member2);
        guardian.approveProposal(proposalId);

        (,,, uint64 deadline,,,) = guardian.proposals(proposalId);
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert(
            abi.encodeWithSelector(
                MERAWalletThresholdGuardian.ProposalExpired.selector, proposalId, deadline, block.timestamp
            )
        );
        guardian.executeProposal(proposalId);
    }

    function test_Execute_SecondTimeReverts() public {
        bytes32 proposalId = _propose(address(0xE5001), 1 days, member1);

        vm.prank(member1);
        guardian.approveProposal(proposalId);
        vm.prank(member2);
        guardian.approveProposal(proposalId);
        guardian.executeProposal(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(MERAWalletThresholdGuardian.ProposalAlreadyExecuted.selector, proposalId)
        );
        guardian.executeProposal(proposalId);
    }

    function test_Propose_DeadlineTooFarReverts() public {
        uint64 tooFar = uint64(block.timestamp + guardian.MAX_DEADLINE_FROM_NOW() + 1);
        vm.prank(member1);
        vm.expectRevert(MERAWalletThresholdGuardian.InvalidDeadline.selector);
        guardian.proposeEmergencyChange(address(0xE5010), tooFar);
    }

    function test_Regression_OutsiderCannotSetEmergencyDirectly() public {
        vm.prank(outsider);
        vm.expectRevert(IBaseMERAWalletErrors.NotSelf.selector);
        wallet.setEmergency(address(0xE6001));
    }

    function test_SetWallet_CannotBeCalledTwice() public {
        vm.prank(member2);
        vm.expectRevert(abi.encodeWithSelector(MERAWalletThresholdGuardian.WalletAlreadySet.selector, address(wallet)));
        guardian.setWallet(address(0x1234));
    }

    function _propose(address newEmergency, uint64 delta, address proposer) internal returns (bytes32 proposalId) {
        vm.prank(proposer);
        proposalId = guardian.proposeEmergencyChange(newEmergency, uint64(block.timestamp + delta));
    }
}
