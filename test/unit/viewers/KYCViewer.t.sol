// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/wallet/KintoWalletFactory.sol";
import "@kinto-core/KintoID.sol";
import "@kinto-core/viewers/KYCViewer.sol";

import "@kinto-core-test/SharedSetup.t.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";

contract KYCViewerUpgraded is KYCViewer {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address _kintoWalletFactory, address _faucet, address _engenCredits)
        KYCViewer(_kintoWalletFactory, _faucet, _engenCredits)
    {}
}

contract KYCViewerTest is SharedSetup {
    function testUp() public override {
        super.testUp();
        assertEq(_kycViewer.owner(), _owner);
        assertEq(address(_entryPoint.walletFactory()), address(_kycViewer.walletFactory()));
        assertEq(address(_walletFactory.kintoID()), address(_kycViewer.kintoID()));
        assertEq(address(_engenCredits), address(_kycViewer.engenCredits()));
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        KYCViewerUpgraded _implementationV2 =
            new KYCViewerUpgraded(address(_walletFactory), address(_faucet), address(_engenCredits));
        vm.prank(_owner);
        _kycViewer.upgradeTo(address(_implementationV2));
        assertEq(KYCViewerUpgraded(address(_kycViewer)).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner(address someone) public {
        vm.assume(someone != _owner);
        KYCViewerUpgraded _implementationV2 =
            new KYCViewerUpgraded(address(_walletFactory), address(_faucet), address(_engenCredits));
        vm.expectRevert(IKYCViewer.OnlyOwner.selector);
        vm.prank(someone);
        _kycViewer.upgradeTo(address(_implementationV2));
    }

    /* ============ Viewer tests ============ */

    function testIsKYC_WhenBothOwnerAndWallet() public view {
        assertEq(_kycViewer.isKYC(address(_kintoWallet)), _kycViewer.isKYC(_owner));
        assertEq(_kycViewer.isIndividual(address(_kintoWallet)), _kycViewer.isIndividual(_owner));
        assertEq(_kycViewer.isCompany(address(_kintoWallet)), false);
        assertEq(_kycViewer.hasTrait(address(_kintoWallet), 6), false);
        assertEq(_kycViewer.isSanctionsSafe(address(_kintoWallet)), true);
        assertEq(_kycViewer.isSanctionsSafeIn(address(_kintoWallet), 1), true);
    }

    function testGetUserInfoWithCredits() public {
        address[] memory _wallets = new address[](1);
        uint256[] memory _points = new uint256[](1);
        _wallets[0] = address(_kintoWallet);
        _points[0] = 5e18;
        vm.prank(_owner);
        _engenCredits.setCredits(_wallets, _points);

        IKYCViewer.UserInfo memory userInfo = _kycViewer.getUserInfo(_owner, payable(address(_kintoWallet)));
        // verify properties
        assertEq(userInfo.ownerBalance, _owner.balance);
        assertEq(userInfo.walletBalance, address(_kintoWallet).balance);
        assertEq(userInfo.walletPolicy, _kintoWallet.signerPolicy());
        assertEq(userInfo.walletOwners.length, 1);
        assertEq(userInfo.claimedFaucet, false);
        assertEq(userInfo.engenCreditsEarned, 5e18);
        assertEq(userInfo.engenCreditsClaimed, 0);
        assertEq(userInfo.hasNFT, true);
        assertEq(userInfo.isKYC, _kycViewer.isKYC(_owner));

        vm.prank(address(_kintoWallet));
        _engenCredits.mintCredits();
        userInfo = _kycViewer.getUserInfo(_owner, payable(address(_kintoWallet)));
        assertEq(userInfo.engenCreditsClaimed, 5e18);
    }

    function testGetUserInfo_WhenWalletDoesNotExist() public view {
        IKYCViewer.UserInfo memory userInfo = _kycViewer.getUserInfo(_owner, payable(address(123)));

        // verify properties
        assertEq(userInfo.ownerBalance, _owner.balance);
        assertEq(userInfo.walletBalance, 0);
        assertEq(userInfo.walletPolicy, 0);
        assertEq(userInfo.recoveryTs, 0);
        assertEq(userInfo.walletOwners.length, 0);
        assertEq(userInfo.engenCreditsEarned, 0);
        assertEq(userInfo.engenCreditsClaimed, 0);
        assertEq(userInfo.claimedFaucet, false);
        assertEq(userInfo.hasNFT, true);
        assertEq(userInfo.isKYC, _kycViewer.isKYC(_owner));
    }

    function testGetUserInfo_WhenAccountDoesNotExist() public view {
        IKYCViewer.UserInfo memory userInfo = _kycViewer.getUserInfo(address(111), payable(address(123)));

        // verify properties
        assertEq(userInfo.ownerBalance, 0);
        assertEq(userInfo.walletBalance, 0);
        assertEq(userInfo.walletPolicy, 0);
        assertEq(userInfo.recoveryTs, 0);
        assertEq(userInfo.walletOwners.length, 0);
        assertEq(userInfo.claimedFaucet, false);
        assertEq(userInfo.engenCreditsEarned, 0);
        assertEq(userInfo.engenCreditsClaimed, 0);
        assertEq(userInfo.hasNFT, false);
        assertEq(userInfo.isKYC, _kycViewer.isKYC(address(111)));
    }
}
