// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {UUPSUpgradeable as UUPSUpgradeable5} from
    "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@kinto-core/wallet/KintoWalletFactory.sol";
import "@kinto-core/paymasters/SponsorPaymaster.sol";
import "@kinto-core/apps/KintoAppRegistry.sol";

import "@kinto-core/interfaces/ISponsorPaymaster.sol";
import "@kinto-core/interfaces/IKintoWallet.sol";

import "@kinto-core-test/helpers/Create2Helper.sol";
import "@kinto-core-test/helpers/ArtifactsReader.sol";
import "@kinto-core-test/helpers/UserOp.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";
import {DeployerHelper} from "@kinto-core/libraries/DeployerHelper.sol";

import {Constants} from "@kinto-core-script/migrations/const.sol";

import {SaltHelper} from "@kinto-core-script/utils/SaltHelper.sol";

import "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

interface IInitialize {
    function initialize() external;
}

contract MigrationHelper is Script, DeployerHelper, UserOp, SaltHelper, Constants {
    using ECDSAUpgradeable for bytes32;
    using stdJson for string;

    bool testMode;
    uint256 deployerPrivateKey;
    address deployer;
    KintoWalletFactory factory;

    function run() public virtual {
        try vm.envBool("TEST_MODE") returns (bool _testMode) {
            testMode = _testMode;
        } catch {}

        console2.log("Running on chain with id:", vm.toString(block.chainid));
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        factory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));
        vm.stopBroadcast();
    }

    /// @dev deploys proxy contract via factory from deployer address
    function _deployProxy(string memory contractName, address implementation, bytes32 salt)
        internal
        returns (address _proxy)
    {
        bool isEntryPoint = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("EntryPoint"));
        bool isWallet = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("KintoWallet"));

        if (isWallet || isEntryPoint) revert("EntryPoint and KintoWallet do not use UUPPS Proxy");

        // deploy Proxy contract
        vm.broadcast(deployerPrivateKey);
        _proxy = address(new UUPSProxy{salt: salt}(address(implementation), ""));

        console.log(string.concat(contractName, ": ", vm.toString(address(_proxy))));
    }

    function _deployProxy(string memory contractName, address implementation) internal returns (address _proxy) {
        return _deployProxy(contractName, implementation, bytes32(0));
    }

    /// @dev deploys implementation contracts via entrypoint from deployer address
    /// @dev if contract is ownable, it will transfer ownership to msg.sender
    function _deployImplementation(
        string memory contractName,
        string memory version,
        bytes memory bytecode,
        bytes32 salt
    ) internal returns (address _impl) {
        // deploy new implementation via factory
        // vm.stopBroadcast();
        vm.broadcast(deployerPrivateKey);
        _impl = factory.deployContract(msg.sender, 0, bytecode, salt);

        console.log(string.concat(contractName, version, "-impl: ", vm.toString(address(_impl))));
    }

    function _deployImplementation(string memory contractName, string memory version, bytes memory bytecode)
        internal
        returns (address _impl)
    {
        return _deployImplementation(contractName, version, bytecode, bytes32(0));
    }

    /// @notice deploys implementation contracts via factory from deployer address and upgrades them
    /// @dev if contract is KintoWallet we call upgradeAllWalletImplementations
    /// @dev if contract is allowed to receive EOA calls, we call upgradeTo directly. Otherwise, we use EntryPoint to upgrade
    function _deployImplementationAndUpgrade(string memory contractName, string memory version, bytes memory bytecode)
        internal
        returns (address _impl)
    {
        console.log('aaa');
        bool isWallet = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("KintoWallet"));
        address proxy = _getChainDeployment(contractName);

        if (!isWallet) require(proxy != address(0), "Need to execute main deploy script first");

        // (1). deploy new implementation via wallet factory
        _impl = _deployImplementation(contractName, version, bytecode);
        console.log('heree');
        // (2). call upgradeTo to set new implementation
        if (!testMode) {
            if (isWallet) {
                _upgradeWallet(_impl, deployerPrivateKey);
            } else {
                try Ownable(proxy).owner() returns (address owner) {
                    if (owner != _getChainDeployment("KintoWallet-admin")) {
                        console.log(
                            "%s contract is not owned by the KintoWallet-admin, its owner is %s",
                            contractName,
                            vm.toString(owner)
                        );
                        revert("Contract is not owned by KintoWallet-admin");
                    }
                    _upgradeTo(proxy, _impl, deployerPrivateKey);
                } catch {
                    _upgradeTo(proxy, _impl, deployerPrivateKey);
                }
            }
        } else {
            if (isWallet) {
                vm.prank(factory.owner());
                factory.upgradeAllWalletImplementations(IKintoWallet(_impl));
            } else {
                // todo: ideally, on testMode, we should use the KintoWallet-admin and adjust tests so they use the handleOps
                try Ownable(proxy).owner() returns (address owner) {
                    vm.prank(owner);
                    UUPSUpgradeable(proxy).upgradeTo(_impl);
                } catch {}
            }
        }
    }

    function _upgradeWallet(address _impl, uint256 _signerPk) internal {
        address payable from = payable(_getChainDeployment("KintoWallet-admin"));
        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = _signerPk;
        privKeys[1] = 0; // Ledger

        bytes memory data = abi.encodeWithSelector(KintoWalletFactory.upgradeAllWalletImplementations.selector, _impl);

        _handleOps(data, from, address(factory), 0, address(0), privKeys);
    }

    function _upgradeTo(address proxy, address _newImpl, uint256 _signerPk) internal {
        address payable from = payable(_getChainDeployment("KintoWallet-admin"));
        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = _signerPk;
        privKeys[1] = 0; // Ledger

        // if UUPS contract has UPGRADE_INTERFACE_VERSION set to 5.0.0, we use upgradeToAndCall
        bytes memory data = abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, address(_newImpl));
        try UUPSUpgradeable5(proxy).UPGRADE_INTERFACE_VERSION() returns (string memory _version) {
            if (keccak256(abi.encode(_version)) == keccak256(abi.encode("5.0.0"))) {
                data = abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, address(_newImpl), bytes(""));
            }
        } catch {}

        _handleOps(data, from, proxy, 0, address(0), privKeys);
    }

    // TODO: should be extended to work with other initialize() that receive params
    function _initialize(address _proxy, uint256 _signerPk) internal {
        // fund _proxy in the paymaster if necessary
        if (_isGethAllowed(_proxy)) {
            IInitialize(_proxy).initialize();
        } else {
            if (ISponsorPaymaster(payable(_getChainDeployment("SponsorPaymaster"))).balances(_proxy) == 0) {
                _fundPaymaster(_proxy, _signerPk);
            }
            bytes memory selectorAndParams = abi.encodeWithSelector(IInitialize.initialize.selector);
            _handleOps(selectorAndParams, _proxy, _signerPk);
        }
    }

    /// @notice transfers ownership of a contract to a new owner
    /// @dev from is the KintoWallet-admin
    /// @dev _newOwner cannot be an EOA if contract is not allowed to receive EOA calls
    function _transferOwnership(address _proxy, uint256 _signerPk, address _newOwner) internal {
        require(_newOwner != address(0), "New owner cannot be 0");

        if (_isGethAllowed(_proxy)) {
            Ownable(_proxy).transferOwnership(_newOwner);
        } else {
            // we don't want to allow transferring ownership to an EOA (e.g LEDGER_ADMIN) when contract is not allowed to receive EOA calls
            if (_newOwner.code.length == 0) revert("Cannot transfer ownership to EOA");
            _handleOps(abi.encodeWithSelector(Ownable.transferOwnership.selector, _newOwner), _proxy, _signerPk);
        }
    }

    /// @notice whitelists an app in the KintoWallet
    function _whitelistApp(address _app, uint256 _signerPk, bool _whitelist) internal {
        address payable _wallet = payable(_getChainDeployment("KintoWallet-admin"));
        _whitelistApp(_app, _wallet, _signerPk, _whitelist);
    }

    function _whitelistApp(address _app, address _wallet, uint256 _signerPk, bool _whitelist) internal {
        address[] memory apps = new address[](1);
        apps[0] = _app;

        bool[] memory flags = new bool[](1);
        flags[0] = _whitelist;

        _handleOps(abi.encodeWithSelector(IKintoWallet.whitelistApp.selector, apps, flags), _wallet, _wallet, _signerPk);
    }

    function _whitelistApp(address _app, uint256 _signerPk) internal {
        _whitelistApp(_app, _signerPk, true);
    }

    // @notice handles ops with KintoWallet-admin as the from address
    // @dev does not use a sponsorPaymaster
    // @dev does not use a hardware wallet
    function _handleOps(bytes memory _selectorAndParams, address _to, uint256 _signerPk) internal {
        _handleOps(_selectorAndParams, payable(_getChainDeployment("KintoWallet-admin")), _to, address(0), _signerPk);
    }

    // @notice handles ops with custom from address
    // @dev does not use a sponsorPaymaster
    // @dev does not use a hardware wallet
    function _handleOps(bytes memory _selectorAndParams, address _from, address _to, uint256 _signerPk) internal {
        _handleOps(_selectorAndParams, _from, _to, address(0), _signerPk);
    }

    // @notice handles ops with KintoWallet-admin as the from address
    // @dev does not use a hardware wallet
    function _handleOps(
        bytes memory _selectorAndParams,
        address _from,
        address _to,
        address _sponsorPaymaster,
        uint256 _signerPk
    ) internal {
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = _signerPk;
        _handleOps(_selectorAndParams, _from, _to, 0, _sponsorPaymaster, privateKeys);
    }

    // @notice handles ops with custom params
    // @dev receives a hardware wallet type (e.g "trezor", "ledger", "none")
    // if _hwType is "trezor" or "ledger", it will sign the user op with the hardware wallet
    function _handleOps(
        bytes memory _selectorAndParams,
        address _from,
        address _to,
        uint256 value,
        address _sponsorPaymaster,
        uint256[] memory _privateKeys
    ) internal {
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            block.chainid,
            _from,
            _to,
            value,
            IKintoWallet(_from).getNonce(),
            _privateKeys,
            _selectorAndParams,
            _sponsorPaymaster
        );
        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(_privateKeys[0])));
    }

    // @notice handles ops with multiple ops and destinations
    // @dev does not use a sponsorPaymaster
    // @dev does not use a hardware wallet
    function _handleOps(bytes[] memory _selectorAndParams, address[] memory _tos, uint256 _signerPk) internal {
        _handleOps(_selectorAndParams, _tos, address(0), _signerPk);
    }

    // @notice handles ops with multiple ops but same destinations
    // @dev does not use a sponsorPaymaster
    // @dev does not use a hardware wallet
    function _handleOps(bytes[] memory _selectorAndParams, address _to, uint256 _signerPk) internal {
        address[] memory _tos;
        for (uint256 i = 0; i < _selectorAndParams.length; i++) {
            _tos[i] = _to;
        }
        _handleOps(_selectorAndParams, _tos, address(0), _signerPk);
    }

    // @notice handles ops with multiple ops and destinations
    // @dev uses a sponsorPaymaster
    // @dev does not use a hardware wallet
    function _handleOps(
        bytes[] memory _selectorAndParams,
        address[] memory _tos,
        address _sponsorPaymaster,
        uint256 _signerPk
    ) internal {
        require(_selectorAndParams.length == _tos.length, "_selectorAndParams and _tos mismatch");
        address payable _from = payable(_getChainDeployment("KintoWallet-admin"));
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = _signerPk;

        UserOperation[] memory userOps = new UserOperation[](_selectorAndParams.length);
        uint256 nonce = IKintoWallet(_from).getNonce();
        for (uint256 i = 0; i < _selectorAndParams.length; i++) {
            userOps[i] = _createUserOperation(
                block.chainid, _from, _tos[i], 0, nonce, privateKeys, _selectorAndParams[i], _sponsorPaymaster
            );
            nonce++;
        }
        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(_signerPk)));
    }

    function _fundPaymaster(address _proxy, uint256 _signerPk) internal {
        ISponsorPaymaster _paymaster = ISponsorPaymaster(_getChainDeployment("SponsorPaymaster"));
        vm.broadcast(_signerPk);
        _paymaster.addDepositFor{value: 0.00000001 ether}(_proxy);
        assertEq(_paymaster.balances(_proxy), 0.00000001 ether);
    }

    function _isGethAllowed(address _contract) internal returns (bool _isAllowed) {
        // contracts allowed to receive EOAs calls
        address[6] memory GETH_ALLOWED_CONTRACTS = [
            _getChainDeployment("EntryPoint"),
            _getChainDeployment("KintoWalletFactory"),
            _getChainDeployment("SponsorPaymaster"),
            _getChainDeployment("KintoID"),
            _getChainDeployment("KintoAppRegistry"),
            _getChainDeployment("BundleBulker")
        ];

        // check if contract is a geth allowed contract
        for (uint256 i = 0; i < GETH_ALLOWED_CONTRACTS.length; i++) {
            if (_contract == GETH_ALLOWED_CONTRACTS[i]) {
                _isAllowed = true;
                break;
            }
        }
    }

    // @dev this is a workaround to get the address of the KintoWallet-admin in test mode
    function _getChainDeployment(string memory _contractName) internal override returns (address _contract) {
        if (testMode && keccak256(abi.encode(_contractName)) == keccak256(abi.encode("KintoWallet-admin"))) {
            return vm.envAddress("KINTO_ADMIN_WALLET");
        }
        return super._getChainDeployment(_contractName);
    }

    function etchWallet(address wallet) internal {
        console.log('etching wallet:', vm.toString(wallet));
        KintoWallet impl = new KintoWallet(
            IEntryPoint(_getChainDeployment("EntryPoint")),
            IKintoID(_getChainDeployment("KintoID")),
            IKintoAppRegistry(_getChainDeployment("KintoAppRegistry"))
        );
        vm.etch(wallet, address(impl).code);
    }

    function replaceOwner(IKintoWallet wallet, address newOwner) internal {
        address[] memory owners = new address[](3);
        owners[0] = wallet.owners(0);
        owners[1] = newOwner;
        owners[2] = wallet.owners(2);

        uint8 policy = wallet.signerPolicy();
        vm.prank(address(wallet));
        wallet.resetSigners(owners, policy);

        require(wallet.owners(1) == newOwner, "Failed to replace signer");
    }
}
