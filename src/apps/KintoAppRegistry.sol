// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/IKintoID.sol";
import "../interfaces/IKintoAppRegistry.sol";
import "../interfaces/IKintoWalletFactory.sol";
import "../interfaces/IKintoWallet.sol";

/**
 * @title KintoAppRegistry
 * @dev A contract that holds all the information of a KintoApp
 */
contract KintoAppRegistry is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IKintoAppRegistry
{
    /* ============ Constants ============ */

    uint256 public constant override RATE_LIMIT_PERIOD = 1 minutes;
    uint256 public constant override RATE_LIMIT_THRESHOLD = 10;
    uint256 public constant override GAS_LIMIT_PERIOD = 30 days;
    uint256 public constant override GAS_LIMIT_THRESHOLD = 0.01 ether;

    address public constant CREATE2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /* ============ State Variables ============ */

    IKintoWalletFactory public immutable override walletFactory;

    mapping(address => IKintoAppRegistry.Metadata) private _appMetadata;

    // mapping between an app and all the contracts that it sponsors (that belong to the app)
    mapping(address => address) public override childToParentContract; // child => parent (app)

    // contracts the app decides to sponsor (that dont belong to the app)
    mapping(address => mapping(address => bool)) private _sponsoredContracts;

    mapping(uint256 => address) public override tokenIdToApp; // token ID => app metadata

    uint256 public override appCount;

    IKintoID public immutable kintoID;

    address public constant ADMIN_DEPLOYER = 0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c;

    mapping(address => address) public override devEoaToApp;

    address[] public override systemContracts;
    mapping(address => bool) public override isSystemContract;

    /* ============ Events ============ */

    event AppRegistered(address indexed _app, address _owner, uint256 _timestamp);
    event AppUpdated(address indexed _app, address _owner, uint256 _timestamp);
    event AppDSAEnabled(address indexed _app, uint256 _timestamp);
    event SystemContractsUpdated(address[] oldSystemContracts, address[] newSystemContracts);

    /* ============ Constructor & Initializers ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IKintoWalletFactory _walletFactory) {
        _disableInitializers();
        walletFactory = _walletFactory;
        kintoID = IKintoID(_walletFactory.kintoID());
    }

    function initialize() external initializer {
        __ERC721_init("Kinto APP", "KINTOAPP");
        __ERC721Enumerable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(msg.sender);
    }

    /**
     * @dev Authorize the upgrade. Only by the upgrader role.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the implementation is upgraded
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ============ Token name, symbol & URI ============ */

    /**
     * @dev Gets the token name.
     * @return string representing the token name
     */
    function name() public pure override(ERC721Upgradeable, IKintoAppRegistry) returns (string memory) {
        return "Kinto APP";
    }

    /**
     * @dev Gets the token symbol.
     * @return string representing the token symbol
     */
    function symbol() public pure override(ERC721Upgradeable, IKintoAppRegistry) returns (string memory) {
        return "KINTOAPP";
    }

    /**
     * @dev Returns the base token URI. ID is appended
     * @return token URI.
     */
    function _baseURI() internal pure override returns (string memory) {
        return "https://kinto.xyz/metadata/kintoapp/";
    }

    /* ============ App Registration ============ */

    /**
     * @dev Register a new app and mints the NFT to the creator
     * @param _name The name of the app
     * @param parentContract The address of the parent contract
     * @param appContracts The addresses of the child contracts
     * @param appLimits The limits of the app
     * @param devEOAs The addresses of the developers EOAs to be whitelisted
     */
    function registerApp(
        string calldata _name,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits,
        address[] calldata devEOAs
    ) external override {
        if (!kintoID.isKYC(msg.sender)) revert KYCRequired();
        if (_appMetadata[parentContract].tokenId != 0) revert AlreadyRegistered();
        if (childToParentContract[parentContract] != address(0)) revert ParentAlreadyChild();
        if (walletFactory.walletTs(parentContract) != 0) revert CannotRegisterWallet();

        appCount++;
        _updateMetadata(appCount, _name, parentContract, appContracts, appLimits, devEOAs);
        _safeMint(msg.sender, appCount);

        emit AppRegistered(parentContract, msg.sender, block.timestamp);
    }

    /**
     * @dev Allows the developer to update the metadata of the app
     * @param _name The name of the app
     * @param parentContract The address of the parent contract
     * @param appContracts The addresses of the child contracts
     * @param appLimits The limits of the app
     * @param devEOAs The addresses of the developers EOAs to be whitelisted
     */
    function updateMetadata(
        string calldata _name,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits,
        address[] calldata devEOAs
    ) external override {
        uint256 tokenId = _appMetadata[parentContract].tokenId;
        if (msg.sender != ownerOf(tokenId)) revert OnlyAppDeveloper();
        _updateMetadata(tokenId, _name, parentContract, appContracts, appLimits, devEOAs);

        emit AppUpdated(parentContract, msg.sender, block.timestamp);
    }

    /**
     * @dev Allows the developer to set sponsored contracts
     * @param _app The address of the app
     * @param _contracts The addresses of the contracts
     * @param _flags The flags of the contracts
     */
    function setSponsoredContracts(address _app, address[] calldata _contracts, bool[] calldata _flags)
        external
        override
    {
        if (_contracts.length != _flags.length) revert LengthMismatch();
        if (
            _appMetadata[_app].tokenId == 0
                || (msg.sender != ownerOf(_appMetadata[_app].tokenId) && msg.sender != owner())
        ) {
            revert InvalidSponsorSetter();
        }
        for (uint256 i = 0; i < _contracts.length; i++) {
            _sponsoredContracts[_app][_contracts[i]] = _flags[i];
        }
    }

    /**
     * @dev Allows the app to request PII data
     * @param app The name of the app
     */
    function enableDSA(address app) external override onlyOwner {
        if (_appMetadata[app].dsaEnabled) revert DSAAlreadyEnabled();
        _appMetadata[app].dsaEnabled = true;
        emit AppDSAEnabled(app, block.timestamp);
    }

    /**
     * @dev Allows the owner to override the parent contract of a child contract
     * @param child The address of the child contract
     * @param parent The address of the parent contract
     */
    function overrideChildToParentContract(address child, address parent) external override onlyOwner {
        childToParentContract[child] = parent;
    }

    /**
     * @dev Updates the system contracts array
     * @param newSystemContracts The new array of system contracts
     */
    function updateSystemContracts(address[] calldata newSystemContracts) external onlyOwner {
        emit SystemContractsUpdated(systemContracts, newSystemContracts);
        for (uint256 index = 0; index < systemContracts.length; index++) {
            isSystemContract[systemContracts[index]] = false;
        }
        for (uint256 index = 0; index < newSystemContracts.length; index++) {
            isSystemContract[newSystemContracts[index]] = true;
        }
        systemContracts = newSystemContracts;
    }

    /* ============ Getters ============ */

    /**
     * @dev Returns whether the contract implements the interface defined by the id
     * @param interfaceId id of the interface to be checked.
     * @return true if the contract implements the interface defined by the id.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns the metadata of the app
     * @param _contract The address of the app
     * @return The metadata of the app
     */
    function getAppMetadata(address _contract) external view override returns (IKintoAppRegistry.Metadata memory) {
        return
            _appMetadata[childToParentContract[_contract] != address(0) ? childToParentContract[_contract] : _contract];
    }

    /**
     * @dev Returns the limits of the app
     * @param _contract The address of the app
     * @return The limits of the app
     */
    function getContractLimits(address _contract) external view override returns (uint256[4] memory) {
        IKintoAppRegistry.Metadata memory metadata =
            _appMetadata[childToParentContract[_contract] != address(0) ? childToParentContract[_contract] : _contract];
        return [
            metadata.rateLimitPeriod != 0 ? metadata.rateLimitPeriod : RATE_LIMIT_PERIOD,
            metadata.rateLimitNumber != 0 ? metadata.rateLimitNumber : RATE_LIMIT_THRESHOLD,
            metadata.gasLimitPeriod != 0 ? metadata.gasLimitPeriod : GAS_LIMIT_PERIOD,
            metadata.gasLimitCost != 0 ? metadata.gasLimitCost : GAS_LIMIT_THRESHOLD
        ];
    }

    /**
     * @dev Returns whether a contract is sponsored by an app
     * @param _app The address of the app
     * @param _contract The address of the contract
     * @return bool true or false
     */
    function isSponsored(address _app, address _contract) external view override returns (bool) {
        return _contract == _app || childToParentContract[_contract] == _app || _sponsoredContracts[_app][_contract];
    }

    /**
     * @dev Returns the sponsoring contract for a given contract (aka parent contract)
     * @param _contract The address of the contract
     * @return The address of the contract that sponsors the contract
     */
    function getSponsor(address _contract) external view override returns (address) {
        address sponsor = childToParentContract[_contract];
        if (sponsor != address(0)) return sponsor;
        return _contract;
    }

    /**
     * @notice Determines if a contract call is allowed from an EOA (Externally Owned Account)
     * @dev This function checks various conditions to decide if an EOA can call a specific contract:
     *      1. Allows calls to system contracts from any EOA
     *      2. Checks if the EOA has a linked wallet
     *      3. Verifies if dev mode is enabled on the wallet
     *      4. Ensures the wallet owner has completed KYC
     *      5. Permits CREATE and CREATE2 operations for eligible EOAs
     *      6. Allows dev EOAs to call their respective apps
     * @param from The address of the EOA initiating the call
     * @param to The address of the contract being called
     * @return A boolean indicating whether the contract call is allowed (true) or not (false)
     */
    function isContractCallAllowedFromEOA(address from, address to) external view returns (bool) {
        // Calls to system contracts are allwed for any EOA.
        if (isSystemContract[to]) return true;

        // Find the wallet of the `from` EOA.
        address[] memory wallets = walletFactory.getSignerWallets(from);
        // Deny if there is no wallet linked to EOA.
        if (wallets.length == 0) return false;
        address wallet = wallets[0];

        // Deny if dev mode is not enabled on the wallet.
        if (IKintoWallet(wallet).devMode() == 0) return false;

        // Deny if wallet has no KYC
        if (!kintoID.isKYC(IKintoWallet(wallet).owners(0))) return false;

        // Signers of dev wallets are allowed to use CREATE and CREATE2.
        if (to == address(0) || to == CREATE2) {
            // Permit if EOA have a wallet, dev mode and KYC.
            return true;
        }

        // Contract calls are allowed only to dev EOAs.
        address app = childToParentContract[to] != address(0) ? childToParentContract[to] : to;
        // Dev EOAs are allowed to call their respective apps.
        if (devEoaToApp[from] == app) {
            return true;
        }
        return false;
    }

    /* =========== Internal methods =========== */

    function _updateMetadata(
        uint256 tokenId,
        string calldata _name,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits,
        address[] calldata devEOAs
    ) internal {
        // Cleanup old devEOAs
        address[] memory oldArray = _appMetadata[parentContract].devEOAs;
        for (uint256 i = 0; i < oldArray.length; i++) {
            devEoaToApp[oldArray[i]] = address(0);
        }

        // Cleanup old appContracts
        oldArray = _appMetadata[parentContract].appContracts;
        for (uint256 i = 0; i < oldArray.length; i++) {
            childToParentContract[oldArray[i]] = address(0);
        }

        IKintoAppRegistry.Metadata memory metadata = IKintoAppRegistry.Metadata({
            tokenId: tokenId,
            name: _name,
            dsaEnabled: false,
            rateLimitPeriod: appLimits[0],
            rateLimitNumber: appLimits[1],
            gasLimitPeriod: appLimits[2],
            gasLimitCost: appLimits[3],
            devEOAs: devEOAs,
            appContracts: appContracts
        });

        tokenIdToApp[tokenId] = parentContract;
        _appMetadata[parentContract] = metadata;

        // Sets Child to parent contract
        for (uint256 i = 0; i < appContracts.length; i++) {
            if (walletFactory.walletTs(appContracts[i]) > 0) revert CannotRegisterWallet();
            if (childToParentContract[appContracts[i]] != address(0)) revert ChildAlreadyRegistered();
            childToParentContract[appContracts[i]] = parentContract;
        }

        for (uint256 i = 0; i < devEOAs.length; i++) {
            devEoaToApp[devEOAs[i]] = parentContract;
        }
    }

    /**
     * @dev Hook that is called before any token transfer. Allow only mints and burns, no transfers.
     * @param from source address
     * @param to target address
     * @param batchSize The first id
     */
    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        if ((from != address(0) && from != ADMIN_DEPLOYER && from != owner()) || to == address(0)) {
            revert OnlyMintingAllowed();
        }
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }
}

contract KintoAppRegistryV7 is KintoAppRegistry {
    constructor(IKintoWalletFactory _walletFactory) KintoAppRegistry(_walletFactory) {}
}
