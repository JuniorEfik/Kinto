// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/Faucet.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration28DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(Faucet).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        _deployImplementationAndUpgrade("Faucet", "V4", bytecode);
    }
}
