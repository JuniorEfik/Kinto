// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/viewers/KYCViewer.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration25DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(
            type(KYCViewer).creationCode,
            abi.encode(_getChainDeployment("KintoWalletFactory"), _getChainDeployment("Faucet"))
        );
        address implementation = _deployImplementation("KYCViewer", "V4", bytecode);
        address proxy = _deployProxy("KYCViewer", implementation);

        _whitelistApp(proxy, deployerPrivateKey);
        _initialize(proxy, deployerPrivateKey);
    }
}
