// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../../src/bridger/Bridger.sol";

import "../../../test/helpers/Create2Helper.sol";
import "../../../test/helpers/ArtifactsReader.sol";
import "../../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

contract KintoMainnetMigration5DeployScript is Create2Helper, ArtifactsReader, Test {
    Bridger _bridger;

    function setUp() public {}

    function run() public {
        if (block.chainid != 1) {
            console.log("This script is meant to be run on the mainnet");
            return;
        }
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // If not using ledger, replace
        console.log("Executing with address", msg.sender);
        vm.startBroadcast();
        address bridgerAddress = _getChainDeployment("Bridger", 1);
        if (bridgerAddress == address(0)) {
            console.log("Not deployed bridger", bridgerAddress);
            return;
        }
        _bridger = Bridger(payable(bridgerAddress));
        address[] memory _assets = new address[](7);
        _assets[0] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        _assets[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        _assets[2] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI
        _assets[3] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH
        _assets[4] = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee; // weeth
        _assets[5] = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f; // GHO
        _assets[6] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3; // USDe
        bool[] memory _flags = new bool[](7);
        _flags[0] = true;
        _flags[1] = true;
        _flags[2] = true;
        _flags[3] = true;
        _flags[4] = true;
        _flags[5] = true;
        _flags[6] = true;
        _bridger.whitelistAssets(_assets, _flags);
        // transfer to safe
        _bridger.transferOwnership(0xf152Abda9E4ce8b134eF22Dc3C6aCe19C4895D82);
        vm.stopBroadcast();

        // Checks
        for (uint256 i = 0; i < _assets.length; i++) {
            assertEq(_bridger.allowedAssets(_assets[i]), true);
        }
        assertEq(_bridger.owner(), 0xf152Abda9E4ce8b134eF22Dc3C6aCe19C4895D82);
    }
}
