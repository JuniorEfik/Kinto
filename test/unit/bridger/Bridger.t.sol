// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@kinto-core/interfaces/IBridger.sol";
import "@kinto-core/bridger/Bridger.sol";

import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/harness/BridgerHarness.sol";
import "@kinto-core-test/SharedSetup.t.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract ERC20PermitToken is ERC20, ERC20Permit {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {}
}

contract BridgerTest is SignatureHelper, SharedSetup {
    address internal constant l1ToL2Router = 0xD9041DeCaDcBA88844b373e7053B4AC7A3390D60;
    address internal constant kintoWalletL2 = address(33);
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant senderAccount = address(100);
    address internal constant l2Vault = address(99);
    address internal constant EXCHANGE_PROXY = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address internal constant WETH = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address internal constant USDE = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address internal constant SUSDE = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address internal constant WSTETH = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address internal constant weETH = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    BridgerHarness internal bridger;

    ERC20PermitToken internal sDAI;

    function setUp() public override {
        super.setUp();
        sDAI = new ERC20PermitToken("sDAI", "sDAI");

        // deploy a new Bridger contract
        BridgerHarness implementation = new BridgerHarness(EXCHANGE_PROXY, WETH, DAI, USDE, SUSDE, WSTETH);
        address proxy = address(new UUPSProxy{salt: 0}(address(implementation), ""));
        bridger = BridgerHarness(payable(proxy));

        vm.prank(_owner);
        bridger.initialize(senderAccount);

        address[] memory assets = new address[](1);
        assets[0] = address(sDAI);
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        vm.prank(_owner);
        bridger.whitelistFinalAssets(assets, flags);
    }

    /* ============ Bridger Deposit ============ */

    // deposit sDAI (no swap)
    function testDepositBySig_sDAI_WhenNoSwap() public {
        address assetToDeposit = address(sDAI);
        uint256 amountToDeposit = 1e18;
        uint256 balanceBefore = ERC20(assetToDeposit).balanceOf(address(bridger));
        deal(assetToDeposit, _user, amountToDeposit);

        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);

        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            assetToDeposit,
            amountToDeposit,
            amountToDeposit,
            _userPk,
            block.timestamp + 1000
        );

        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        uint256 nonce = bridger.nonces(_user);

        vm.prank(_owner);

        bridger.depositBySig(permitSignature, sigdata, bytes(""));

        assertEq(bridger.nonces(_user), nonce + 1);
        assertEq(ERC20(assetToDeposit).balanceOf(address(bridger)), balanceBefore + amountToDeposit);
    }

    function testDepositBySig_RevertWhen_CallerIsNotOwnerOrSender() public {
        address assetToDeposit = address(sDAI);
        uint256 amountToDeposit = 1e18;
        deal(address(assetToDeposit), _user, amountToDeposit);

        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            assetToDeposit,
            amountToDeposit,
            1,
            _userPk,
            block.timestamp + 1000
        );

        vm.expectRevert(IBridger.OnlyOwner.selector);
        vm.prank(_user);
        bridger.depositBySig(bytes(""), sigdata, bytes(""));
    }

    function testDepositBySig_RevertWhen_AmountIsZero() public {
        address assetToDeposit = address(sDAI);
        uint256 amountToDeposit = 0;
        deal(address(assetToDeposit), _user, amountToDeposit);

        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            assetToDeposit,
            amountToDeposit,
            amountToDeposit,
            _userPk,
            block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );
        vm.expectRevert(abi.encodeWithSelector(IBridger.InvalidAmount.selector, uint256(0)));
        vm.prank(_owner);
        bridger.depositBySig(permitSignature, sigdata, bytes(""));
    }

    /* ============ Bridger ETH Deposit ============ */

    function testDepositETH_RevertWhen_FinalAssetisNotAllowed() public {
        uint256 amountToDeposit = 1e18;
        vm.deal(_user, amountToDeposit);
        vm.startPrank(_owner);
        vm.expectRevert(abi.encodeWithSelector(IBridger.InvalidFinalAsset.selector, address(1)));
        bridger.depositETH{value: amountToDeposit}(
            kintoWalletL2, address(1), 1, bytes("")

        );
        vm.stopPrank();
    }

    function testDepositETH_RevertWhen_AmountIsLessThanAllowed() public {
        uint256 amountToDeposit = 0.05 ether;
        vm.deal(_user, amountToDeposit);
        vm.startPrank(_owner);
        vm.expectRevert(abi.encodeWithSelector(IBridger.InvalidAmount.selector, amountToDeposit));
        bridger.depositETH{value: amountToDeposit}(
            kintoWalletL2, address(sDAI), 1,bytes("") 
        );
        vm.stopPrank();
    }

    /* ============ Whitelist ============ */

    function testWhitelistAsset() public {
        address asset = address(768);
        address[] memory assets = new address[](1);
        assets[0] = asset;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        vm.prank(_owner);
        bridger.whitelistAssets(assets, flags);
        assertEq(bridger.allowedAssets(asset), true);
    }

    function testWhitelistAsset_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        bridger.whitelistAssets(new address[](1), new bool[](1));
    }

    function testWhitelistAsset_RevertWhen_LengthMismatch() public {
        vm.expectRevert(IBridger.InvalidAssets.selector);
        vm.prank(_owner);
        bridger.whitelistAssets(new address[](1), new bool[](2));
    }

    /* ============ Pause ============ */

    function testPauseWhenOwner() public {
        assertEq(bridger.paused(), false);
        vm.prank(_owner);
        bridger.pause();
        assertEq(bridger.paused(), true);
    }

    function testPause_RevertWhen_NotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        bridger.pause();
    }

    function testUnpauseWhenOwner() public {
        vm.prank(_owner);
        bridger.pause();

        assertEq(bridger.paused(), true);
        vm.prank(_owner);
        bridger.unpause();
        assertEq(bridger.paused(), false);
    }

    function testUnpause_RevertWhen_NotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        bridger.unpause();
    }

    /* ============ Sender account ============ */

    function testSetSenderAccount_RevertWhen_NotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        bridger.setSenderAccount(address(0xdead));
    }

    /* ============ EIP712 ============ */

    function testDomainSeparatorV4() public view {
        assertEq(
            bridger.domainSeparatorV4(),
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("Bridger")), // this contract's name
                    keccak256(bytes("1")), // version
                    block.chainid,
                    address(bridger)
                )
            ),
            "Domain separator is invalid"
        );
    }

    function testHashSignatureData(
        address kintoWallet,
        address signer,
        address inputAsset,
        address finalAsset,
        uint256 amount,
        uint256 minReceive,
        uint256 nonce,
        uint256 expiresAt,
        bytes calldata signature
    ) public view {
        IBridger.SignatureData memory data = IBridger.SignatureData({
            kintoWallet: kintoWallet,
            signer: signer,
            inputAsset: inputAsset,
            finalAsset: finalAsset,
            amount: amount,
            minReceive: minReceive,
            nonce: nonce,
            expiresAt: expiresAt,
            signature: signature
        });
        assertEq(
            bridger.hashSignatureData(data),
            keccak256(
                abi.encode(
                    keccak256(
                        "SignatureData(address kintoWallet,address signer,address inputAsset,uint256 amount,uint256 minReceive,address finalAsset,uint256 nonce,uint256 expiresAt)"
                    ),
                    kintoWallet,
                    signer,
                    inputAsset,
                    amount,
                    minReceive,
                    finalAsset,
                    nonce,
                    expiresAt
                )
            ),
            "Signature data is invalid"
        );
    }
}
