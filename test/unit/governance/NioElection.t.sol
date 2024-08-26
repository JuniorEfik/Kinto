// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC721} from "@openzeppelin-5.0.1/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";

import {NioElection} from "@kinto-core/governance/NioElection.sol";
import {NioGuardians} from "@kinto-core/tokens/NioGuardians.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";

import "forge-std/console2.sol";

contract NioElectionTest is SharedSetup {
    NioElection internal election;
    BridgedKinto internal kToken;
    NioGuardians internal nioNFT;

    uint256 public constant CANDIDATE_SUBMISSION_DURATION = 5 days;
    uint256 public constant CANDIDATE_VOTING_DURATION = 5 days;
    uint256 public constant COMPLIANCE_PROCESS_DURATION = 5 days;
    uint256 public constant NOMINEE_VOTING_DURATION = 15 days;
    uint256 public constant ELECTION_DURATION = 30 days;
    uint256 public constant MIN_VOTE_PERCENTAGE = 5e15; // 0.5% in wei
    uint256 public constant ELECTION_INTERVAL = 180 days; // 6 months

    uint256 internal kAmount = 100e18;
    uint256 internal fullVoteAmount = 100e18;
    uint256 internal halfVoteAmount = 50e18;

    function setUp() public override {
        super.setUp();

        kToken = BridgedKinto(payable(address(new UUPSProxy(address(new BridgedKinto()), ""))));
        kToken.initialize("KINTO TOKEN", "KINTO", admin, admin, admin);

        nioNFT = new NioGuardians(address(admin));
        election = new NioElection(kToken, nioNFT, _kintoID);
        vm.prank(admin);
        nioNFT.transferOwnership(address(election));

        // Distribute tokens and set up KYC
        for (uint256 i = 1; i < wallets.length; i++) {
            vm.prank(admin);
            kToken.mint(wallets[i], kAmount);
            vm.prank(wallets[i]);
            kToken.delegate(wallets[i]);
        }
    }

    /* ============ startElection ============ */

    function testStartElection() public {
        election.startElection();
        assertEq(uint256(election.getCurrentPhase()), uint256(NioElection.ElectionPhase.CandidateSubmission));
        (
            uint256 startTime,
            uint256 candidateSubmissionEndTime,
            uint256 candidateVotingEndTime,
            uint256 complianceProcessEndTime,
            uint256 nomineeVotingEndTime,
            uint256 electionEndTime,
            uint256 niosToElect
        ) = election.getElectionDetails();

        assertEq(startTime, block.timestamp);
        assertEq(candidateSubmissionEndTime, startTime + CANDIDATE_SUBMISSION_DURATION);
        assertEq(candidateVotingEndTime, candidateSubmissionEndTime + CANDIDATE_VOTING_DURATION);
        assertEq(complianceProcessEndTime, candidateVotingEndTime + COMPLIANCE_PROCESS_DURATION);
        assertEq(nomineeVotingEndTime, startTime + ELECTION_DURATION);
        assertEq(electionEndTime, 0); // Should be 0 before election is completed
        assertEq(niosToElect, 4); // First election should elect 4 Nios
    }

    function testStartElection_RevertWhenActiveElection() public {
        election.startElection();
        vm.expectRevert(abi.encodeWithSelector(NioElection.ElectionAlreadyActive.selector, 0, block.timestamp));
        election.startElection();
    }

    function testStartElection_RevertWhenElectionTooEarly() public {
        runElection();

        vm.warp(block.timestamp + 179 days); // Just before the ELECTION_INTERVAL
        uint256 nextElectionTime = election.getNextElectionTime();
        vm.expectRevert(
            abi.encodeWithSelector(NioElection.TooEarlyForNewElection.selector, block.timestamp, nextElectionTime)
        );
        election.startElection();
    }

    /* ============ submitCandidate ============ */

    function testSubmitCandidate() public {
        election.startElection();

        vm.prank(alice);
        election.submitCandidate();

        address[] memory candidates = election.getCandidates(0);

        assertEq(candidates.length, 1);
        assertEq(candidates[0], alice);
    }

    function testSubmitCandidate_RevertWhenAfterDeadline() public {
        election.startElection();
        vm.warp(block.timestamp + 6 days);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                0,
                NioElection.ElectionPhase.CandidateVoting,
                NioElection.ElectionPhase.CandidateSubmission
            )
        );
        election.submitCandidate();
    }

    /* ============ voteForCandidate ============ */

    function testVoteForCandidate() public {
        election.startElection();
        vm.prank(alice);
        election.submitCandidate();
        vm.warp(block.timestamp + 6 days);

        vm.prank(bob);
        election.voteForCandidate(alice, 50e18);

        assertEq(election.getCandidateVotes(alice), 50e18);
    }

    function testVoteForCandidate_RevertWhenBeforeCandidateVoting() public {
        election.startElection();

        vm.prank(alice);
        election.submitCandidate();

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                0,
                NioElection.ElectionPhase.CandidateSubmission,
                NioElection.ElectionPhase.CandidateVoting
            )
        );
        election.voteForCandidate(alice, 50e18);
    }

    /* ============ voteForNominee ============ */

    function testVoteForNominee() public {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);
        voteForCandidates();
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        vm.prank(bob);
        election.voteForNominee(alice, fullVoteAmount);

        assertEq(election.getNomineeVotes(alice), fullVoteAmount);
    }

    function testVoteForNominee_RevertWhenBeforeNomineeVoting() public {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);
        voteForCandidates();
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                0,
                NioElection.ElectionPhase.ComplianceProcess,
                NioElection.ElectionPhase.NomineeVoting
            )
        );
        election.voteForNominee(alice, 50e18);
    }

    function testVoteForNominee_RevertWhenVoteTwice() public {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);
        voteForCandidates();
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        vm.prank(bob);
        election.voteForNominee(alice, fullVoteAmount);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NioElection.NoVotingPower.selector, bob));
        election.voteForNominee(alice, fullVoteAmount);
    }

    function testVoteForNomineeVoteWeighting() public {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);
        voteForCandidates();
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        // 50% voting power
        vm.warp(block.timestamp + 11 days);
        vm.prank(bob);
        election.voteForNominee(alice, fullVoteAmount);

        assertEq(election.getNomineeVotes(alice), fullVoteAmount / 2);

        // ~0% voting power
        vm.warp(block.timestamp + 4 days - 1);
        vm.prank(eve);
        election.voteForNominee(alice, fullVoteAmount);

        uint256 weight = uint256(1e18) / 8 days;
        assertEq(election.getNomineeVotes(alice), fullVoteAmount / 2 + fullVoteAmount * weight / 1e18);
    }

    /* ============ electNios ============ */

    function testElectNios() public {
        runElection();

        (,,,,, uint256 electionEndTime,) = election.getElectionDetails();

        address[] memory electedNios = election.getElectedNios();
        assertEq(electedNios.length, 4);

        for (uint256 index = 0; index < electedNios.length; index++) {
            assertTrue(nioNFT.balanceOf(electedNios[index]) > 0);
        }
        for (uint256 index = 5; index < wallets.length; index++) {
            assertTrue(nioNFT.balanceOf(wallets[index]) == 0);
        }

        assertEq(electionEndTime, block.timestamp);
    }

    function testElectNiosSorting() public {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);

        // Vote for candidates with different amounts
        vm.prank(alice);
        election.voteForCandidate(bob, 80e18);
        vm.prank(bob);
        election.voteForCandidate(charlie, 90e18);
        vm.prank(charlie);
        election.voteForCandidate(ian, 70e18);
        vm.prank(ian);
        election.voteForCandidate(eve, 60e18);
        vm.prank(eve);
        election.voteForCandidate(frank, 50e18);

        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        // Vote for nominees with different amounts
        vm.prank(alice);
        election.voteForNominee(bob, 80e18);
        vm.prank(bob);
        election.voteForNominee(charlie, 90e18);
        vm.prank(charlie);
        election.voteForNominee(ian, 10e18);
        vm.prank(ian);
        election.voteForNominee(eve, 60e18);
        vm.prank(eve);
        election.voteForNominee(frank, 70e18);

        vm.warp(block.timestamp + NOMINEE_VOTING_DURATION);

        election.electNios();

        address[] memory electedNios = election.getElectedNios();

        // Check that we have the correct number of elected Nios
        assertEq(electedNios.length, 4);

        // Check that the elected Nios are in the correct order (highest votes to lowest)
        assertEq(electedNios[0], charlie);
        assertEq(electedNios[1], bob);
        assertEq(electedNios[2], frank);
        assertEq(electedNios[3], eve);

        // Verify vote counts
        assertEq(election.getNomineeVotes(charlie), 90e18);
        assertEq(election.getNomineeVotes(bob), 80e18);
        assertEq(election.getNomineeVotes(frank), 70e18);
        assertEq(election.getNomineeVotes(eve), 60e18);

        // Verify that frank (lowest votes) was not elected
        assertEq(election.getNomineeVotes(ian), 10e18);
    }

    function testElectNios_RevertWhenBeforeEnd() public {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);
        voteForCandidates();
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        vm.prank(bob);
        election.voteForNominee(alice, fullVoteAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                0,
                NioElection.ElectionPhase.NomineeVoting,
                NioElection.ElectionPhase.AwaitingElection
            )
        );
        election.electNios();
    }

    function testAlternatingNiosToElect() public {
        // First election
        runElection();
        (,,,,, uint256 electionEndTime, uint256 niosToElect) = election.getElectionDetails();
        assertEq(niosToElect, 4);

        // Second election
        vm.warp(electionEndTime + ELECTION_INTERVAL);
        runElection();
        (,,,,, electionEndTime, niosToElect) = election.getElectionDetails(1);
        assertEq(niosToElect, 5);

        // Third election
        vm.warp(electionEndTime + ELECTION_INTERVAL);
        runElection();
        (,,,,, electionEndTime, niosToElect) = election.getElectionDetails(2);
        assertEq(niosToElect, 4);
    }

    /* ============ Helper functions ============ */

    function submitCandidates() internal {
        for (uint256 i = 1; i < wallets.length; i++) {
            vm.prank(wallets[i]);
            election.submitCandidate();
        }
    }

    function voteForCandidates() internal {
        for (uint256 i = 1; i < wallets.length; i++) {
            vm.prank(wallets[i]);
            election.voteForCandidate(wallets[i], halfVoteAmount);
        }
    }

    function voteForNominees() internal {
        for (uint256 i = 1; i < wallets.length; i++) {
            vm.prank(wallets[i]);
            election.voteForNominee(wallets[i], halfVoteAmount);
        }
    }

    function runElection() internal {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);

        voteForCandidates();
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        voteForNominees();
        vm.warp(block.timestamp + NOMINEE_VOTING_DURATION);

        election.electNios();
    }
}
