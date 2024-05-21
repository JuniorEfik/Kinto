// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

interface IDAI {
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

interface IsUSDe is IERC20 {
    function deposit(uint256 amount, address recipient) external returns (uint256);
}

interface IBridger {
    /* ============ Errors ============ */
    error OnlySender();
    error OnlyOwner();
    error SignatureExpired();
    error InvalidNonce();
    error InvalidSigner();
    error InvalidAmount(uint256 amount);
    error InvalidAssets();
    error SwapsDisabled();
    error GasFeeTooHigh();
    error SwapCallFailed();
    error FailedToStakeEth();
    error SlippageError(uint256 boughtAmount, uint256 minReceive);

    /* ============ Structs ============ */

    struct SignatureData {
        address kintoWallet; // Kinto Wallet Address on L2 where tokens will be deposited
        address signer;
        address inputAsset;
        address finalAsset;
        uint256 amount;
        uint256 minReceive; // Minimum amount of finalAsset to receive
        uint256 nonce;
        uint256 expiresAt;
        bytes signature;
    }

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    struct BridgeData {
        address vault;
        uint256 gasFee;
        uint256 msgGasLimit;
        address connector;
        bytes execPayload;
        bytes options;
    }

    /* ============ State Change ============ */

    function depositBySig(
        bytes calldata permitSignature,
        IBridger.SignatureData calldata signatureData,
        bytes calldata swapCallData,
        BridgeData calldata bridgeData
    ) external payable;

    function depositERC20(
        address inputAsset,
        uint256 amount,
        address kintoWallet,
        address finalAsset,
        uint256 minReceive,
        bytes calldata swapCallData,
        BridgeData calldata bridgeData
    ) external payable;

    function depositETH(
        uint256 amount,
        address kintoWallet,
        address finalAsset,
        uint256 minReceive,
        bytes calldata swapCallData,
        BridgeData calldata bridgeData
    ) external payable;

    function pause() external;

    function unpause() external;

    function setSenderAccount(address senderAccount) external;

    /* ============ View ============ */

    function nonces(address account) external view returns (uint256);

    function domainSeparator() external view returns (bytes32);

    function l2Vault() external view returns (address);

    function senderAccount() external view returns (address);

    function swapRouter() external view returns (address);
}
