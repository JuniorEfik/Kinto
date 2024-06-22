// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";

import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {Constants} from "@kinto-core-script/migrations/const.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";

import {console2} from "forge-std/console2.sol";

contract KintoMigration77DeployScript is MigrationHelper {
    using LibString for *;
    using Strings for string;

    function run() public override {
        super.run();

        // deploy token
        address impl = address(new BridgedKinto{salt: keccak256(abi.encodePacked("K"))}());
        address proxy = _getChainDeployment("KINTO");

        BridgedKinto bridgedToken = BridgedKinto(proxy);
        IKintoWallet adminWallet = IKintoWallet(_getChainDeployment("KintoWallet-admin"));
        replaceOwner(adminWallet, 0x4632F4120DC68F225e7d24d973Ee57478389e9Fd);
        _whitelistApp(proxy);
        _upgradeTo(proxy, impl, deployerPrivateKey);

        require(bridgedToken.decimals() == 18, "Decimals mismatch");
        require(bridgedToken.symbol().equal("K"), "");
        require(bridgedToken.name().equal("Kinto Token"), "");

        console2.log("All checks passed!");
        console2.log("implementation deployed @%s", impl);

        saveContractAddress(string.concat(bridgedToken.symbol(), "V2", "-impl"), impl);
    }
}
