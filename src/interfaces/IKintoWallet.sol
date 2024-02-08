// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IEntryPoint} from "@aa/core/BaseAccount.sol";
import {IKintoWalletFactory} from "./IKintoWalletFactory.sol";
import {IKintoID} from "./IKintoID.sol";
import {IKintoAppRegistry} from "./IKintoAppRegistry.sol";

interface IKintoWallet {
    /* ============ Structs ============ */

    /* ============ State Change ============ */

    function initialize(address anOwner, address _recoverer, uint256[4] calldata _blsPublicKey) external;

    function execute(address dest, uint256 value, bytes calldata func) external;

    function executeBatch(address[] calldata dest, uint256[] calldata values, bytes[] calldata func) external;

    function setSignerPolicy(uint8 policy) external;

    function resetSigners(address[] calldata newSigners, uint8 policy) external;

    function setPublicKey(uint256[4] calldata _blsPublicKey) external;

    function setFunderWhitelist(address[] calldata newWhitelist, bool[] calldata flags) external;

    function changeRecoverer(address newRecoverer) external;

    function startRecovery() external;

    function completeRecovery(address[] calldata newSigners) external;

    function cancelRecovery() external;

    function setAppKey(address app, address signer) external;

    function whitelistApp(address[] calldata apps, bool[] calldata flags) external;

    /* ============ Basic Viewers ============ */

    function getOwnersCount() external view returns (uint256);

    function getNonce() external view returns (uint256);

    function blsPublicKey(uint256 _idx) external view returns (uint256 blsKeyPart);

    /* ============ Constants and attrs ============ */

    function kintoID() external view returns (IKintoID);

    function inRecovery() external view returns (uint256);

    function owners(uint256 _index) external view returns (address);

    function recoverer() external view returns (address);

    function funderWhitelist(address funder) external view returns (bool);

    function isFunderWhitelisted(address funder) external view returns (bool);

    function appSigner(address app) external view returns (address);

    function appWhitelist(address app) external view returns (bool);

    function appRegistry() external view returns (IKintoAppRegistry);

    function signerPolicy() external view returns (uint8);

    function MAX_SIGNERS() external view returns (uint8);

    function SINGLE_SIGNER() external view returns (uint8);

    function MINUS_ONE_SIGNER() external view returns (uint8);

    function ALL_SIGNERS() external view returns (uint8);

    function RECOVERY_TIME() external view returns (uint256);

    function WALLET_TARGET_LIMIT() external view returns (uint256);
}
