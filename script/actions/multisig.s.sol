// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/interfaces/IKintoWallet.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract MultisigScript is MigrationHelper {
    using stdJson for string;

    function run() public override {
        super.run();

        string memory json = vm.readFile("./script/data/multisig.json");

        address from = json.readAddress(string.concat(".", "from"));
        address to = json.readAddress(string.concat(".", "to"));
        address paymaster = json.readAddress(string.concat(".", "paymaster"));
        bytes memory data = json.readBytes(string.concat(".", "calldata"));
        uint256 value = json.readUint(string.concat(".", "value"));
        uint256 key = json.readUint(string.concat(".", "key"));

        // etchWallet(0xa158e30099C6F7D9546eF2a519F2118E46039307);
        // replaceOwner(IKintoWallet(from), 0x4632F4120DC68F225e7d24d973Ee57478389e9Fd);

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = key;
        _handleOps(
            data,
            from,
            to,
            value,
            paymaster,
            privKeys
        );
    }
}
