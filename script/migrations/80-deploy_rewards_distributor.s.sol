// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {console2} from "forge-std/console2.sol";

contract DeployRewardsDistributorScript is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    function run() public override {
        super.run();

        address KINTO = _getChainDeployment("KINTO");
        address ENGEN = _getChainDeployment("EngenCredits");

        vm.broadcast(deployerPrivateKey);
        uint256 LIQUIDITY_MINING_START_DATE = 1718690400; // June 18th 2024
        address impl = address(
            new RewardsDistributor{salt: keccak256("0")}(IERC20(KINTO), IERC20(ENGEN), LIQUIDITY_MINING_START_DATE)
        );

        bytes32 initCodeHash = keccak256(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(impl, "")));
        (bytes32 salt, address expectedAddress) = mineSalt(initCodeHash, "d15790");

        vm.broadcast(deployerPrivateKey);
        address proxy = address(new UUPSProxy{salt: salt}(address(impl), ""));
        RewardsDistributor distr = RewardsDistributor(proxy);

        // replaceOwner(IKintoWallet(kintoAdminWallet), 0x4632F4120DC68F225e7d24d973Ee57478389e9Fd);
        // hardwareWalletType = 1;

        _whitelistApp(proxy);

        // initialize
        _handleOps(abi.encodeWithSelector(RewardsDistributor.initialize.selector, bytes(""), 0), proxy);

        console2.log("Proxy deployed @%s", proxy);

        assertEq(proxy, expectedAddress);

        assertEq(address(distr.KINTO()), 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87);
        assertEq(address(distr.ENGEN()), 0xD1295F0d8789c3E0931A04F91049dB33549E9C8F);

        console2.log("All checks passed!");

        saveContractAddress(string.concat("RewardsDistributor", "-impl"), impl);
        saveContractAddress("RewardsDistributor", proxy);
    }
}
