// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/Bridger.sol";

import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/harness/BridgerHarness.sol";
import "@kinto-core-test/helpers/ArtifactsReader.sol";
import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/Bridger.sol";

contract BridgerTest is SignatureHelper, ForkTest, ArtifactsReader {
    using stdJson for string;

    address internal constant kintoWalletL2 = address(33);
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant sDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant senderAccount = address(100);
    address internal constant L2_VAULT = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address internal constant EXCHANGE_PROXY = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDe = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address internal constant sUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address internal constant ENA = 0x57e114B691Db790C35207b2e685D4A43181e6061;
    address internal constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant weETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

    BridgerHarness internal bridger;
    IBridger.BridgeData internal emptyBridgerData;

    address constant l2Vault = address(99);

    mapping(address => IBridger.BridgeData) internal bridgeData;

    uint256 internal amountIn = 1e18;


    function setUp() public override {
        super.setUp();

        vm.deal(_owner, 1e20);

        bridger = BridgerHarness(payable(_getChainDeployment("Bridger")));

        // transfer owner's ownership to _owner
        vm.prank(bridger.owner());
        bridger.transferOwnership(_owner);

        emptyBridgerData = IBridger.BridgeData({
            vault: address(0),
            gasFee: 0,
            msgGasLimit: 0,
            connector: address(0),
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[wstETH] = IBridger.BridgeData({
            vault: 0xc5d01939Af7Ce9Ffc505F0bb36eFeDde7920f2dc,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0x83C6d6597891Ad48cF5e0BA901De55120C37C6bE,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[weETH] = IBridger.BridgeData({
            vault: 0xeB66259d2eBC3ed1d3a98148f6298927d8A36397,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xE2c2291B80BFC8Bd0e4fc8Af196Ae5fc9136aeE0,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[sDAI] = IBridger.BridgeData({
            vault: 0x5B8Ae1C9c5970e2637Cf3Af431acAAebEf7aFb85,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xF5992B6A0dEa32dCF6BE7bfAf762A4D94f139Ea7,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[sUSDe] = IBridger.BridgeData({
            vault: 0x43b718Aa5e678b08615CA984cbe25f690B085b32,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xE274dB6b891159547FbDC18b07412EE7F4B8d767,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ENA] = IBridger.BridgeData({
            vault: 0x351d8894fB8bfa1b0eFF77bFD9Aab18eA2da8fDd,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0x266abd77Da7F877cdf93c0dd5782cC61Fa29ac96,
            execPayload: bytes(""),
            options: bytes("")
        });
    }

    function setUpChain() public virtual override {
        setUpEthereumFork();
    }

    function deployBridger() internal {
        // give some eth to _owner
        vm.deal(_owner, 1e20);

        BridgerHarness implementation = new BridgerHarness(L2_VAULT, EXCHANGE_PROXY, WETH, DAI, USDe, sUSDe, wstETH);
        address proxy = address(new UUPSProxy{salt: 0}(address(implementation), ""));
        bridger = BridgerHarness(payable(proxy));

        vm.prank(_owner);
        bridger.initialize(senderAccount);
    }

    function upgradeBridger() internal {
        // give some eth to _owner
        vm.deal(_owner, 1e20);

        BridgerHarness newImpl = new BridgerHarness(L2_VAULT, EXCHANGE_PROXY, WETH, DAI, USDe, sUSDe, wstETH);
        vm.prank(bridger.owner());
        bridger.upgradeTo(address(newImpl));
    }

    /* ============ Bridger Deposit ============ */

    // deposit wstETH (no swap)
    function testDepositBySig_wstETH_WhenNoSwap() public {
        upgradeBridger();

        address asset = bridger.wstETH();
        uint256 amountToDeposit = 1e18;
        IBridger.BridgeData memory data = bridgeData[bridger.wstETH()];
        uint256 bridgerBalanceBefore = ERC20(asset).balanceOf(address(bridger));
        uint256 vaultBalanceBefore = ERC20(asset).balanceOf(address(data.vault));
        deal(asset, _user, amountToDeposit);
        deal(_user, data.gasFee);

        assertEq(ERC20(asset).balanceOf(_user), amountToDeposit);

        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            asset,
            asset,
            amountToDeposit,
            amountToDeposit,
            _userPk,
            block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user, address(bridger), amountToDeposit, ERC20Permit(asset).nonces(_user), block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(asset)
        );

        uint256 nonce = bridger.nonces(_user);
        vm.prank(_owner);
        bridger.depositBySig{value: data.gasFee}(permitSignature, sigdata, bytes(""), data);
        assertEq(bridger.nonces(_user), nonce + 1);

        assertEq(ERC20(asset).balanceOf(address(bridger)), bridgerBalanceBefore);
        assertEq(ERC20(asset).balanceOf(address(data.vault)), vaultBalanceBefore + amountToDeposit);
    }

    // USDe to sUSDe
    function testDepositBySig_WhenUSDeTosUSDe() public {
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[sUSDe];
        address assetToDeposit = bridger.USDe();
        uint256 amountToDeposit = 1e18;
        uint256 sharesBefore = ERC20(sUSDe).balanceOf(address(bridger));
        uint256 vaultSharesBefore = ERC20(sUSDe).balanceOf(address(data.vault));

        deal(assetToDeposit, _user, amountToDeposit);
        deal(_user, data.gasFee);

        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);

        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2, bridger, _user, assetToDeposit, sUSDe, amountToDeposit, 1e17, _userPk, block.timestamp + 1000
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
        bridger.depositBySig{value: data.gasFee}(permitSignature, sigdata, bytes(""), data);
        assertEq(bridger.nonces(_user), nonce + 1);

        uint256 shares = ERC4626(sUSDe).previewDeposit(amountToDeposit);
        assertEq(ERC20(sUSDe).balanceOf(address(bridger)), sharesBefore);
        assertEq(ERC20(sUSDe).balanceOf(data.vault), vaultSharesBefore + shares);
    }

    // DAI to wstETH
    function testDepositBySig_WhenSwap_WhenDAItoWstETH() public {
        vm.rollFork(19919468); // block number in which the 0x API data was fetched
        upgradeBridger();

        // top-up _user DAI balance
        IBridger.BridgeData memory data = bridgeData[wstETH];
        address assetIn = DAI;
        address assetOut = wstETH;

        uint256 bridgerAssetInBalanceBefore = ERC20(assetIn).balanceOf(address(bridger));
        uint256 bridgerAssetOutBalanceBefore = ERC20(assetOut).balanceOf(address(bridger));
        uint256 vaultAssetOutBalanceBefore = ERC20(assetOut).balanceOf(data.vault);

        deal(assetIn, _user, amountIn);
        deal(_user, data.gasFee);

        // create a permit signature to allow the bridger to transfer the user's DAI
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user, address(bridger), amountIn, ERC20Permit(assetIn).nonces(_user), block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetIn)
        );

        // create a bridge signature to allow the bridger to deposit the user's DAI
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetIn,
            bridger.wstETH(),
            amountIn,
            224787412523677,
            _userPk,
            block.timestamp + 1000
        );
        uint256 nonce = bridger.nonces(_user);

        // DAI to wstETH quote's swapData
        // curl 'https://api.0x.org/swap/v1/quote?sellToken=0x6B175474E89094C44Da98b954EedeAC495271d0F&buyToken=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&sellAmount=1000000000000000000' --header '0x-api-key: KEY' | jq > ./test/data/swap-dai-to-wsteth-quote.json
        bytes memory swapCalldata = vm.readFile("./test/data/swap-dai-to-wsteth-quote.json").readBytes(".data");

        vm.prank(bridger.senderAccount());
        bridger.depositBySig{value: data.gasFee}(permitSignature, sigdata, swapCalldata, data);

        assertEq(bridger.nonces(_user), nonce + 1);
        // DAI balance should stay the same
        assertEq(ERC20(assetIn).balanceOf(address(bridger)), bridgerAssetInBalanceBefore);
        // wstETH balance should stay the same
        assertEq(ERC20(assetOut).balanceOf(address(bridger)), bridgerAssetOutBalanceBefore);
        // wstETH should be sent to the vault
        assertEq(ERC20(assetOut).balanceOf(data.vault), vaultAssetOutBalanceBefore);
    }

    /* ============ Bridger ETH Deposit ============ */

    function testDepositETH() public {
        upgradeBridger();

        uint256 amountToDeposit = 1e18;
        IBridger.BridgeData memory data = bridgeData[bridger.wstETH()];
        uint256 balanceBefore = ERC20(bridger.wstETH()).balanceOf(data.vault);
        vm.deal(_user, amountToDeposit + data.gasFee);

        vm.startPrank(_user);
        bridger.depositETH{value: amountToDeposit + data.gasFee}(
            amountToDeposit, kintoWalletL2, bridger.wstETH(), 1e17, bytes(""), data
        );
        vm.stopPrank();

        assertEq(bridger.nonces(_user), 0);
        uint256 balance = ERC20(bridger.wstETH()).balanceOf(data.vault);
        assertTrue(balance - balanceBefore > 0);
    }

    function testDepositETH_WhenSwap() public {
        vm.rollFork(19402998); // block number in which the 0x API data was fetched
        deployBridger(); // re-deploy the bridger on block

        // top-up `_user` ETH balance
        uint256 amountToDeposit = 1 ether;
        vm.deal(_user, amountToDeposit);

        // WETH to sDAI quote's swapData
        // https://api.0x.org/swap/v1/quote?sellToken=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&buyToken=0x83F20F44975D03b1b09e64809B757c47f942BEeA&sellAmount=1000000000000000000
        bytes memory data =
            hex"415565b0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000c8513a48734f22dbe500000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000000000000000000000000000009c000000000000000000000000000000000000000000000000000000000000000210000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000036000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e69737761705633000000000000000000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000e592427a0aece92de3edee1f18e0157c0586156400000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f4dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000210000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000054000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea00000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000004c0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000001942616c616e6365725632000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000c8513a48734f22dbe5000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000ba12222222228d8ba445958a75a0704d566bf2c8000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e079c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014049cbd67651fbabce12d1df18499896ec87bef46f00000000000000000000064a00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000079c58f70905f734641735bc61e45c19dd9ad60bc00000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000014e4e350d61dfbf9717023acbafebe4d";

        uint256 balanceBefore = address(bridger).balance;
        vm.startPrank(_user);
        bridger.depositETH{value: amountToDeposit}(
            amountToDeposit, kintoWalletL2, sDAI, 3695201885067717640192, data, emptyBridgerData
        );
        vm.stopPrank();

        assertEq(_user.balance, 0);
        assertEq(address(bridger).balance, balanceBefore); // there's no ETH since it was swapped
        assertApproxEqRel(ERC20(sDAI).balanceOf(address(bridger)), 3695201885067717640192, 0.01e18); // 1%
    }
}
