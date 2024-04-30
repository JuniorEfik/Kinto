// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {EntryPoint} from "@aa/core/EntryPoint.sol";

import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {AccessRegistry} from "../../src/access/AccessRegistry.sol";
import {AccessPoint} from "../../src/access/AccessPoint.sol";
import {IAccessPoint} from "../../src/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "../../src/interfaces/IAccessRegistry.sol";
import {WithdrawWorkflow} from "../../src/access/workflows/WithdrawWorkflow.sol";
import {WethWorkflow} from "../../src/access/workflows/WethWorkflow.sol";
import {SwapWorkflow} from "../../src/access/workflows/SwapWorkflow.sol";

import {DeployerHelper} from "../../src/libraries/DeployerHelper.sol";
import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract DeployAccessProtocolScript is ArtifactsReader, DeployerHelper {
    // Entry Point address is the same on all chains.
    address payable internal constant ENTRY_POINT = payable(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
    // Exchange Proxy address is the same on all chains.
    address internal constant EXCHANGE_PROXY = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    AccessRegistry registry;
    UpgradeableBeacon beacon;
    WithdrawWorkflow withdrawWorkflow;
    WethWorkflow wethWorkflow;
    SwapWorkflow swapWorkflow;

    function deployContracts(address deployer) internal override {
        address accessRegistryAddr = _getChainDeployment("AccessRegistry");
        if (accessRegistryAddr != address(0)) {
            console.log("Access Protocol is already deployed:", accessRegistryAddr);
            return;
        }

        address dummyAccessPointImpl = create2(
            "DummyAccessPoint-impl",
            abi.encodePacked(type(AccessPoint).creationCode, abi.encode(ENTRY_POINT, address(0)))
        );
        beacon = UpgradeableBeacon(
            create2(
                "AccessRegistryBeacon",
                abi.encodePacked(
                    type(UpgradeableBeacon).creationCode, abi.encode(dummyAccessPointImpl, address(deployer))
                )
            )
        );
        address accessRegistryImpl =
            create2("AccessRegistry-impl", abi.encodePacked(type(AccessRegistry).creationCode, abi.encode(beacon)));
        address accessRegistryProxy = create2(
            "AccessRegistry", abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(accessRegistryImpl, ""))
        );

        registry = AccessRegistry(address(accessRegistryProxy));
        UpgradeableBeacon(beacon).transferOwnership(address(registry));
        address accessPointImpl = create2(
            "AccessPoint-impl", abi.encodePacked(type(AccessPoint).creationCode, abi.encode(ENTRY_POINT, registry))
        );

        registry.initialize();
        registry.upgradeAll(IAccessPoint(accessPointImpl));

        withdrawWorkflow = new WithdrawWorkflow();
        registry.allowWorkflow(address(withdrawWorkflow));

        wethWorkflow = new WethWorkflow(getWethByChainId(block.chainid));
        registry.allowWorkflow(address(wethWorkflow));

        swapWorkflow = new SwapWorkflow(EXCHANGE_PROXY);
        registry.allowWorkflow(address(swapWorkflow));
    }

    function checkContracts(address deployer) internal override {
        require(registry.beacon() == beacon, "Beacon is not set properly");
        require(registry.isWorkflowAllowed(address(withdrawWorkflow)), "Workflow is not set properly");
        require(registry.isWorkflowAllowed(address(wethWorkflow)), "Workflow is not set properly");
        require(registry.isWorkflowAllowed(address(swapWorkflow)), "Workflow is not set properly");
    }
}
