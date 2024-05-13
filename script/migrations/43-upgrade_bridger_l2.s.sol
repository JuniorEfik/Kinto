// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/bridger/BridgerL2.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration43DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(BridgerL2).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        address implementation = _deployImplementation("BridgerL2", "V9", bytecode);
        console.log("implementation: %s", implementation);

        address proxy = _getChainDeployment("BridgerL2");
        console.log("proxy: %s", proxy);
        _upgradeTo(proxy, implementation, deployerPrivateKey);

        // _deployImplementationAndUpgrade("BridgerL2", "V9", bytecode);
    }
}
