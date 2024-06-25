// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/Bridger.sol";

import "@kinto-core-test/fork/const.sol";
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

import "forge-std/console2.sol";

abstract contract BridgeDataHelper is Constants {
    // chainid => asset => bridger data
    mapping(uint256 => mapping(address => IBridger.BridgeData)) internal bridgeData;

    IBridger.BridgeData internal emptyBridgerData;

    constructor() {
        emptyBridgerData = IBridger.BridgeData({
            vault: address(0),
            gasFee: 0,
            msgGasLimit: 0,
            connector: address(0),
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ETHEREUM_CHAINID][wstETH_ETHEREUM] = IBridger.BridgeData({
            vault: 0xc5d01939Af7Ce9Ffc505F0bb36eFeDde7920f2dc,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0x83C6d6597891Ad48cF5e0BA901De55120C37C6bE,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ETHEREUM_CHAINID][WETH_ETHEREUM] = IBridger.BridgeData({
            vault: 0xeB66259d2eBC3ed1d3a98148f6298927d8A36397,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xE2c2291B80BFC8Bd0e4fc8Af196Ae5fc9136aeE0,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ETHEREUM_CHAINID][sDAI_ETHEREUM] = IBridger.BridgeData({
            vault: 0x5B8Ae1C9c5970e2637Cf3Af431acAAebEf7aFb85,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xF5992B6A0dEa32dCF6BE7bfAf762A4D94f139Ea7,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ETHEREUM_CHAINID][sUSDe_ETHEREUM] = IBridger.BridgeData({
            vault: 0x43b718Aa5e678b08615CA984cbe25f690B085b32,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xE274dB6b891159547FbDC18b07412EE7F4B8d767,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ETHEREUM_CHAINID][ENA_ETHEREUM] = IBridger.BridgeData({
            vault: 0x351d8894fB8bfa1b0eFF77bFD9Aab18eA2da8fDd,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0x266abd77Da7F877cdf93c0dd5782cC61Fa29ac96,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ARBITRUM_CHAINID][wUSDM] = IBridger.BridgeData({
            vault: 0x500c8337782a9f82C5376Ea71b66A749cE42b507,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xe5FA8E712B8932AdBB3bcd7e1d49Ea1E7cC0F58D,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ARBITRUM_CHAINID][SOLV_BTC_ARBITRUM] = IBridger.BridgeData({
            vault: 0x25a1baC7314Ff40Ee8CD549251924D066D7d5bC6,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0x5817bF28f6f0B0215f310837BAB88A127d29aBF3,
            execPayload: bytes(""),
            options: bytes("")
        });
    }
}

contract BridgerTest is SignatureHelper, ForkTest, ArtifactsReader, BridgeDataHelper {
    using stdJson for string;

    address internal constant kintoWalletL2 = address(33);

    address internal DAI;
    address internal USDC;
    address internal WETH;
    address internal USDe;
    address internal sUSDe;
    address internal ENA;
    address internal wstETH;
    address internal weETH;
    address internal usdmCurvePool;

    BridgerHarness internal bridger;

    uint256 internal amountIn = 1e18;

    function setUp() public override {
        super.setUp();

        upgradeBridger();
    }

    function setUpChain() public virtual override {
        setUpEthereumFork();
    }

    function upgradeBridger() internal {
        vm.deal(_owner, 1e20);

        bridger = BridgerHarness(payable(_getChainDeployment("Bridger")));

        // transfer owner's ownership to _owner
        vm.prank(bridger.owner());
        bridger.transferOwnership(_owner);

        WETH = address(bridger.WETH());
        DAI = bridger.DAI();
        USDe = bridger.USDe();
        sUSDe = bridger.sUSDe();
        wstETH = bridger.wstETH();

        BridgerHarness newImpl = new BridgerHarness(
            EXCHANGE_PROXY,
            block.chainid == ARBITRUM_CHAINID ? USDM_CURVE_POOL_ARBITRUM : address(0),
            block.chainid == ARBITRUM_CHAINID ? USDC_ARBITRUM : address(0),
            WETH,
            DAI,
            USDe,
            sUSDe,
            wstETH
        );
        vm.prank(bridger.owner());
        bridger.upgradeTo(address(newImpl));
    }

    /* ============ Bridger Deposit ============ */

    // deposit wstETH (no swap)
    function testDepositBySig_wstETH_WhenNoSwap() public {
        address asset = bridger.wstETH();
        uint256 amountToDeposit = 1e18;
        IBridger.BridgeData memory data = bridgeData[block.chainid][bridger.wstETH()];
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
        IBridger.BridgeData memory data = bridgeData[block.chainid][sUSDe];
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
        IBridger.BridgeData memory data = bridgeData[block.chainid][wstETH];
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
        assertEq(
            ERC20(assetOut).balanceOf(data.vault),
            vaultAssetOutBalanceBefore + 229930130833080,
            "Invalid Vault assetOut balance"
        );
    }

    // DAI to wUSDM
    function testDepositBySig_WhenDaiToWUSDM() public {
        setUpArbitrumFork();
        vm.rollFork(221170245); // block number in which the 0x API data was fetched
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[block.chainid][wUSDM];
        address assetToDeposit = DAI_ARBITRUM;
        uint256 amountToDeposit = 1e18;
        uint256 sharesBefore = ERC20(wUSDM).balanceOf(address(bridger));
        uint256 vaultSharesBefore = ERC20(wUSDM).balanceOf(address(data.vault));

        deal(assetToDeposit, _user, amountToDeposit);
        deal(_user, data.gasFee);

        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);

        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            wUSDM,
            amountToDeposit,
            968e3,
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

        // DAI to USDC quote's swapData
        // curl 'https://arbitrum.api.0x.org/swap/v1/quote?buyToken=0xaf88d065e77c8cC2239327C5EDb3A432268e5831&sellToken=0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1&sellAmount=1000000000000000000' --header '0x-api-key: key' | jq > ./test/data/swap-dai-to-usdc-arb.json
        bytes memory swapCalldata = vm.readFile("./test/data/swap-dai-to-usdc-arb.json").readBytes(".data");

        vm.prank(_owner);
        bridger.depositBySig{value: data.gasFee}(permitSignature, sigdata, swapCalldata, data);
        assertEq(bridger.nonces(_user), nonce + 1);

        uint256 shares = ERC4626(wUSDM).previewDeposit(999377507945232038);
        assertEq(ERC20(wUSDM).balanceOf(address(bridger)), sharesBefore, "Invalid balance of the Bridger");
        assertEq(ERC20(wUSDM).balanceOf(data.vault), vaultSharesBefore + shares, "Invalid balance of the Vault");
    }

    // ETH to wUSDM
    function testDepositETH_WhenEthToWUSDM() public {
        setUpArbitrumFork();
        vm.rollFork(221170245); // block number in which the 0x API data was fetched
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[block.chainid][wUSDM];
        uint256 amountToDeposit = 1e18;
        uint256 sharesBefore = ERC20(wUSDM).balanceOf(address(bridger));
        uint256 vaultSharesBefore = ERC20(wUSDM).balanceOf(address(data.vault));

        deal(_user, amountToDeposit);
        deal(_user, data.gasFee);

        // ETH to USDC quote's swapData
        // curl 'https://arbitrum.api.0x.org/swap/v1/quote?buyToken=0xaf88d065e77c8cC2239327C5EDb3A432268e5831&sellToken=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1&sellAmount=1000000000000000000' --header '0x-api-key: key' | jq > ./test/data/swap-weth-to-usdc-arb.json
        bytes memory swapCalldata = vm.readFile("./test/data/swap-weth-to-usdc-arb.json").readBytes(".data");

        vm.prank(_owner);
        bridger.depositETH{value: data.gasFee + amountToDeposit}(
            amountToDeposit, kintoWalletL2, wUSDM, 3460596206951588256619, swapCalldata, data
        );

        uint256 shares = ERC4626(wUSDM).previewDeposit(3577796244115359404856);
        assertEq(ERC20(wUSDM).balanceOf(address(bridger)), sharesBefore, "Invalid balance of the Bridger");
        assertEq(ERC20(wUSDM).balanceOf(data.vault), vaultSharesBefore + shares, "Invalid balance of the Vault");
    }

    // USDC to SolvBTC
    function testDepositERC20_WhenUsdcToSolvBtc() public {
        setUpArbitrumFork();
        vm.rollFork(225593361); // block number in which the 0x API data was fetched
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[block.chainid][SOLV_BTC_ARBITRUM];
        address assetToDeposit = USDC_ARBITRUM;
        uint256 amountToDeposit = 1e6;
        uint256 solvBtcBalanceBefore = ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(bridger));
        uint256 vaultSolvBtcBalanceBefore = ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(data.vault));

        deal(assetToDeposit, _user, amountToDeposit);
        deal(_user, data.gasFee);

        // USDC to WBTC quote's swapData
        // curl 'https://arbitrum.api.0x.org/swap/v1/quote?buyToken=0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f&sellToken=0xaf88d065e77c8cC2239327C5EDb3A432268e5831&sellAmount=1000000' --header '0x-api-key: key' | jq > ./test/data/swap-usdc-to-wbtc-arb.json
        bytes memory swapCalldata = vm.readFile("./test/data/swap-usdc-to-wbtc-arb.json").readBytes(".data");

        vm.prank(_user);
        IERC20(assetToDeposit).approve(address(bridger), amountToDeposit);

        vm.prank(_user);
        bridger.depositERC20{value: data.gasFee}(
            assetToDeposit, amountToDeposit, kintoWalletL2, SOLV_BTC_ARBITRUM, 1618e10, swapCalldata, data
        );

        assertEq(
            ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(bridger)), solvBtcBalanceBefore, "Invalid balance of the Bridger"
        );
        assertEq(
            ERC20(SOLV_BTC_ARBITRUM).balanceOf(data.vault),
            vaultSolvBtcBalanceBefore + 1618e10,
            "Invalid balance of the Vault"
        );
    }

    // WBTC to SolvBTC
    function testDepositERC20_WhenWBtcToSolvBtc() public {
        setUpArbitrumFork();
        vm.rollFork(225593361); // block number in which the 0x API data was fetched
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[block.chainid][SOLV_BTC_ARBITRUM];
        address assetToDeposit = WBTC_ARBITRUM;
        uint256 amountToDeposit = 1e8;
        uint256 solvBtcBalanceBefore = ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(bridger));
        uint256 vaultSolvBtcBalanceBefore = ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(data.vault));

        deal(assetToDeposit, _user, amountToDeposit);
        deal(_user, data.gasFee);

        vm.prank(_user);
        IERC20(assetToDeposit).approve(address(bridger), amountToDeposit);

        vm.prank(_user);
        bridger.depositERC20{value: data.gasFee}(
            assetToDeposit, amountToDeposit, kintoWalletL2, SOLV_BTC_ARBITRUM, amountToDeposit * 1e10, bytes(""), data
        );

        assertEq(
            ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(bridger)), solvBtcBalanceBefore, "Invalid balance of the Bridger"
        );
        assertEq(
            ERC20(SOLV_BTC_ARBITRUM).balanceOf(data.vault),
            vaultSolvBtcBalanceBefore + amountToDeposit * 1e10,
            "Invalid balance of the Vault"
        );
    }

    // SolvBTC to SolvBTC
    function testDepositERC20_WhenSolvBtcToSolvBtc() public {
        setUpArbitrumFork();
        vm.rollFork(225593361); // block number in which the 0x API data was fetched
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[block.chainid][SOLV_BTC_ARBITRUM];
        address assetToDeposit = SOLV_BTC_ARBITRUM;
        uint256 amountToDeposit = 1e18;
        uint256 solvBtcBalanceBefore = ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(bridger));
        uint256 vaultSolvBtcBalanceBefore = ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(data.vault));

        deal(assetToDeposit, _user, amountToDeposit);
        deal(_user, data.gasFee);

        vm.prank(_user);
        IERC20(assetToDeposit).approve(address(bridger), amountToDeposit);

        vm.prank(_user);
        bridger.depositERC20{value: data.gasFee}(
            assetToDeposit, amountToDeposit, kintoWalletL2, SOLV_BTC_ARBITRUM, amountToDeposit, bytes(""), data
        );

        assertEq(
            ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(bridger)), solvBtcBalanceBefore, "Invalid balance of the Bridger"
        );
        assertEq(
            ERC20(SOLV_BTC_ARBITRUM).balanceOf(data.vault),
            vaultSolvBtcBalanceBefore + amountToDeposit,
            "Invalid balance of the Vault"
        );
    }

    /* ============ Bridger ETH Deposit ============ */

    function testDepositETH() public {
        uint256 amountToDeposit = 1e18;
        IBridger.BridgeData memory data = bridgeData[block.chainid][bridger.wstETH()];
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

    function testDepositETH_WhenSwapEthTosDai() public {
        vm.rollFork(19919468); // block number in which the 0x API data was fetched
        upgradeBridger();

        address assetOut = sDAI_ETHEREUM;

        IBridger.BridgeData memory data = bridgeData[block.chainid][sDAI_ETHEREUM];
        amountIn = 1 ether;
        // top-up `_user` ETH balance
        vm.deal(_user, amountIn + data.gasFee);

        // WETH to sDAI quote's swapData
        // curl 'https://api.0x.org/swap/v1/quote?sellToken=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&buyToken=0x83F20F44975D03b1b09e64809B757c47f942BEeA&sellAmount=1000000000000000000' --header '0x-api-key: KEY' | jq > ./test/data/swap-eth-to-sdai-quote.json
        bytes memory swapCalldata = vm.readFile("./test/data/swap-eth-to-sdai-quote.json").readBytes(".data");

        uint256 bridgerBalanceBefore = address(bridger).balance;
        uint256 vaultAssetOutBalanceBefore = ERC20(assetOut).balanceOf(data.vault);
        uint256 amountOut = 3451919521402214642420;

        vm.prank(_user);
        bridger.depositETH{value: amountIn + data.gasFee}(
            amountIn, kintoWalletL2, assetOut, amountOut, swapCalldata, data
        );

        assertEq(_user.balance, 0, "User balance should be zero");
        assertEq(address(bridger).balance, bridgerBalanceBefore); // there's no ETH since it was swapped
        // sDai should be sent to the vault
        assertEq(
            ERC20(assetOut).balanceOf(data.vault),
            vaultAssetOutBalanceBefore + amountOut,
            "Invalid Vault assetOut balance"
        );
    }
}
