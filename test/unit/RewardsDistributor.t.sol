// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";

import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";

import {RewardsDistributor} from "@kinto-core/RewardsDistributor.sol";

contract RewardsDistributorTest is ForkTest {
    RewardsDistributor internal distributor;
    ERC20Mock internal kinto;
    bytes32 internal root = 0x4f75b6d95fab3aedde221f8f5020583b4752cbf6a155ab4e5405fe92881f80e6;
    bytes32 internal leaf;
    uint256 internal baseAmount = 600_000e18;
    uint256 internal maxRatePerSecond = 1e16;
    uint256 internal startTime = START_TIMESTAMP;

    function setUp() public override {
        super.setUp();

        kinto = new ERC20Mock("Kinto Token", "KINTO", 18);

        vm.prank(_owner);
        distributor = new RewardsDistributor(kinto, root, baseAmount, maxRatePerSecond, startTime);
    }

    function testUp() public override {
        distributor = new RewardsDistributor(kinto, root, baseAmount, maxRatePerSecond, startTime);

        assertEq(distributor.startTime(), START_TIMESTAMP);
        assertEq(address(distributor.KINTO()), address(kinto));
        assertEq(distributor.root(), root);
        assertEq(distributor.totalClaimed(), 0);
        assertEq(distributor.baseAmount(), baseAmount);
        assertEq(distributor.maxRatePerSecond(), maxRatePerSecond);
        assertEq(distributor.getTotalLimit(), baseAmount);
        assertEq(distributor.getUnclaimedLimit(), baseAmount);
    }

    function testClaim() public {
        uint256 amount = 1e18;

        kinto.mint(address(distributor), amount);

        assertEq(kinto.balanceOf(address(distributor)), amount);
        assertEq(kinto.balanceOf(_user), 0);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        vm.expectEmit(true, true, true, true);
        emit RewardsDistributor.UserClaimed(_user, amount);
        distributor.claim(proof, _user, amount);

        assertEq(kinto.balanceOf(address(distributor)), 0);
        assertEq(kinto.balanceOf(_user), amount);
        assertEq(distributor.totalClaimed(), amount);
        assertEq(distributor.claimedByUser(_user), amount);
        assertEq(distributor.getTotalLimit(), baseAmount);
        assertEq(distributor.getUnclaimedLimit(), baseAmount - amount);
    }

    function testClaim_WhenTimePass() public {
        uint256 amount = 1e18;

        vm.prank(_owner);
        distributor.updateBaseAmount(0);

        kinto.mint(address(distributor), amount);

        assertEq(kinto.balanceOf(address(distributor)), amount);
        assertEq(kinto.balanceOf(_user), 0);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        vm.warp(START_TIMESTAMP + amount / maxRatePerSecond);

        distributor.claim(proof, _user, amount);

        assertEq(kinto.balanceOf(address(distributor)), 0);
        assertEq(kinto.balanceOf(_user), amount);
        assertEq(distributor.totalClaimed(), amount);
        assertEq(distributor.claimedByUser(_user), amount);
        assertEq(distributor.getTotalLimit(), amount);
        assertEq(distributor.getUnclaimedLimit(), 0);
    }

    function testClaimMultiple() public {
        uint256 amount = 1e18;

        kinto.mint(address(distributor), amount);

        assertEq(kinto.balanceOf(address(distributor)), amount);
        assertEq(kinto.balanceOf(_user), 0);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        distributor.claim(proof, _user, amount);

        assertEq(kinto.balanceOf(address(distributor)), 0);
        assertEq(kinto.balanceOf(_user), amount);
        assertEq(distributor.totalClaimed(), amount);
        assertEq(distributor.claimedByUser(_user), amount);
        assertEq(distributor.getTotalLimit(), baseAmount);
        assertEq(distributor.getUnclaimedLimit(), baseAmount - amount);

        kinto.mint(address(distributor), amount);

        proof[0] = 0xf99b282683659c94d424bb86cf2a97562a08a76b5aee76ae401a001c75ca8f02;
        proof[1] = 0xf5d3a04b6083ba8077d903785b3001db5b9077f1a3af3e06d27a8a9fa3567546;

        distributor.claim(proof, _user, amount);

        assertEq(kinto.balanceOf(address(distributor)), 0);
        assertEq(kinto.balanceOf(_user), 2 * amount);
        assertEq(distributor.totalClaimed(), 2 * amount);
        assertEq(distributor.claimedByUser(_user), 2 * amount);
        assertEq(distributor.getTotalLimit(), baseAmount);
        assertEq(distributor.getUnclaimedLimit(), baseAmount - 2 * amount);
    }

    function testClaim_RevertWhen_InvalidProof() public {
        uint256 amount = 1e18;

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        leaf = keccak256(bytes.concat(keccak256(abi.encode(_user, amount))));
        vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.InvalidProof.selector, proof, leaf));

        distributor.claim(proof, _user, amount);
    }

    function testClaim_RevertWhen_MaxLimitExceeded() public {
        distributor = new RewardsDistributor(kinto, root, 0, maxRatePerSecond, startTime);
        uint256 amount = 1e18;

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.MaxLimitReached.selector, amount, 0));
        distributor.claim(proof, _user, amount);
    }

    function testUpdateRoot() public {
        bytes32 newRoot = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

        vm.expectEmit(true, true, true, true);
        emit RewardsDistributor.RootUpdated(newRoot, root);
        vm.prank(_owner);
        distributor.updateRoot(newRoot);

        assertEq(distributor.root(), newRoot);
    }

    function testUpdateRoot_RevertWhen_NotOwner() public {
        bytes32 newRoot = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        distributor.updateRoot(newRoot);
    }

    function testUpdateBaseAmount() public {
        uint256 newBaseAmount = 1_000_000e18;

        vm.expectEmit(true, true, true, true);
        emit RewardsDistributor.BaseAmountUpdated(newBaseAmount, baseAmount);
        vm.prank(_owner);
        distributor.updateBaseAmount(newBaseAmount);

        assertEq(distributor.baseAmount(), newBaseAmount);
    }

    function testUpdateBaseAmount_RevertWhen_NotOwner() public {
        uint256 newBaseAmount = 1_000_000e18;

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        distributor.updateBaseAmount(newBaseAmount);
    }

    function testUpdateMaxRatePerSecond() public {
        uint256 newMaxRatePerSecond = 5e16; // 0.05 tokens per second

        vm.expectEmit(true, true, true, true);
        emit RewardsDistributor.MaxRatePerSecondUpdated(newMaxRatePerSecond, maxRatePerSecond);
        vm.prank(_owner);
        distributor.updateMaxRatePerSecond(newMaxRatePerSecond);

        assertEq(distributor.maxRatePerSecond(), newMaxRatePerSecond);
    }

    function testUpdateMaxRatePerSecond_RevertWhen_NotOwner() public {
        uint256 newMaxRatePerSecond = 5e16; // 0.05 tokens per second

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        distributor.updateMaxRatePerSecond(newMaxRatePerSecond);
    }
}