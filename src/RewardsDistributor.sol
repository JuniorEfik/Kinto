// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin-5.0.1/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";

/**
 * @title Rewards Distributor
 * @notice Distributes rewards using a Merkle tree for verification.
 */
contract RewardsDistributor is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /* ============ Events ============ */

    /**
     * @notice Emitted when the bonus amount is updated.
     * @param newBonusAmount The new bonus amount.
     * @param oldBonusAmount The old bonus amount.
     */
    event BonusAmountUpdated(uint256 indexed newBonusAmount, uint256 indexed oldBonusAmount);

    /**
     * @notice Emitted when the maximum rate per second is updated.
     * @param newMaxRatePerSecond The new maximum rate per second.
     * @param oldMaxRatePerSecond The old maximum rate per second.
     */
    event MaxRatePerSecondUpdated(uint256 indexed newMaxRatePerSecond, uint256 indexed oldMaxRatePerSecond);

    /**
     * @notice Updates a root of the merkle tree.
     * @param newRoot The new root.
     * @param oldRoot The old root.
     */
    event RootUpdated(bytes32 indexed newRoot, bytes32 indexed oldRoot);

    /**
     * @notice Emitted once `user` claims `amount` of tokens.
     * @param user The user which claimed.
     * @param amount Amount of tokens claimed.
     */
    event UserClaimed(address indexed user, uint256 indexed amount);

    event UserEngenClaimed(address indexed user, uint256 indexed amount);

    /* ============ Errors ============ */

    /**
     * @notice Thrown when the maximum limit for token distribution is exceeded.
     * @param amount The amount attempted to be claimed.
     * @param limit The maximum allowable limit.
     */
    error MaxLimitReached(uint256 amount, uint256 limit);

    /**
     * @notice Thrown when the provided proof does not match the leaf.
     * @param proof The provided proof.
     * @param leaf The leaf node.
     */
    error InvalidProof(bytes32[] proof, bytes32 leaf);

    /* ============ Constants & Immutables ============ */

    /// @notice Starting time of the mining program.
    uint256 public immutable startTime;

    /// @notice The address of Kinto token.
    IERC20 public immutable KINTO;

    /// @notice The address of ENGEN token.
    IERC20 public immutable ENGEN;

    /// @notice The multiplier to convert Engen tokens to Kinto tokens.
    uint256 public constant ENGEN_MULTIPLIER = 22e16;

    /// @notice The bonus given to Engen holders.
    uint256 public constant ENGEN_HOLDER_BONUS = 25e16;

    /* ============ State Variables ============ */

    /// @notice The root of the merkle tree for Kinto token distribition.
    bytes32 public root;

    /// @notice Total amount of claimed tokens.
    uint256 public totalClaimed;

    /// @notice Returns the amount of tokens claimed by a user.
    mapping(address => uint256) public claimedByUser;

    /// @notice Amount of funds preloaded at the start.
    uint256 public bonusAmount;

    /// @notice The maximum rate of token per second which can be distributed.
    uint256 public maxRatePerSecond;

    /// @notice Engen users which kept the capital.
    mapping(address => bool) public engenHolders;

    /// @notice Total amount of Kinto claimed tokens from Engen program.
    uint256 public totalKintoFromEngenClaimed;

    /* ============ Constructor ============ */

    /**
     * @notice Initializes the contract with the given parameters.
     * @param kinto_ The address of the Kinto token.
     * @param root_ The initial root of the Merkle tree.
     * @param bonusAmount_ The initial bonus amount of tokens.
     * @param maxRatePerSecond_ The maximum rate of tokens per second.
     * @param startTime_ The starting time of the mining program.
     */
    constructor(IERC20 kinto_, IERC20 engen_, bytes32 root_, uint256 bonusAmount_, uint256 maxRatePerSecond_, uint256 startTime_)
        Ownable(msg.sender)
    {
        KINTO = kinto_;
        ENGEN = engen_;
        root = root_;
        bonusAmount = bonusAmount_;
        maxRatePerSecond = maxRatePerSecond_;
        startTime = startTime_;
    }

    /* ============ External ============ */

    /**
     * @notice Allows a user to claim tokens if they provide a valid proof.
     * @param proof The Merkle proof.
     * @param user The address of the user claiming tokens.
     * @param amount The amount of tokens to claim.
     */
    function claim(bytes32[] memory proof, address user, uint256 amount) external nonReentrant {
        // Generate the leaf node from the user's address and the amount they are claiming
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user, amount))));

        // Verify the provided proof against the stored Merkle root
        if (MerkleProof.verify(proof, root, leaf) == false) {
            revert InvalidProof(proof, leaf);
        }

        // Check if the total claimed amount exceeds the allowable limit
        if (totalClaimed + amount > getTotalLimit()) {
            revert MaxLimitReached(totalClaimed + amount, getTotalLimit());
        }

        // Update the total claimed amount and the amount claimed by the user
        totalClaimed += amount;
        claimedByUser[user] += amount;

        // Transfer the claimed tokens to the user
        KINTO.safeTransfer(user, amount);

        // Emit an event indicating that the user has claimed tokens
        emit UserClaimed(user, amount);
    }

    function claimEngen() external nonReentrant {
        // Amount of Kinto tokens to claim is EngenBalance * multiplier
        uint256 amount = ENGEN.balanceOf(msg.sender) * ENGEN_MULTIPLIER / 1e18;

        // Engen holder get an extra holder bonus
        amount = engenHolders[msg.sender] ? amount * ENGEN_HOLDER_BONUS / 1e18 : amount;

        totalKintoFromEngenClaimed += amount;

        // Transfer Kinto tokens to the user
        KINTO.safeTransfer(msg.sender, amount);

        // Emit an event indicating that the user has claimed tokens
        emit UserEngenClaimed(msg.sender, amount);
    }

    /**
     * @notice Updates the root of the Merkle tree.
     * @param newRoot The new root.
     */
    function updateRoot(bytes32 newRoot) external onlyOwner {
        emit RootUpdated(newRoot, root);
        root = newRoot;
    }

    /**
     * @notice Updates the bonus amount of tokens.
     * @param newBonusAmount The new bonus amount.
     */
    function updateBonusAmount(uint256 newBonusAmount) external onlyOwner {
        emit BonusAmountUpdated(newBonusAmount, bonusAmount);
        bonusAmount = newBonusAmount;
    }

    /**
     * @notice Updates the maximum rate of tokens per second.
     * @param newMaxRatePerSecond The new maximum rate per second.
     */
    function updateMaxRatePerSecond(uint256 newMaxRatePerSecond) external onlyOwner {
        emit MaxRatePerSecondUpdated(newMaxRatePerSecond, maxRatePerSecond);
        maxRatePerSecond = newMaxRatePerSecond;
    }

    /* ============ View ============ */

    /**
     * @notice Returns the total limit of tokens that can be distributed.
     * @return The total limit of tokens.
     */
    function getTotalLimit() public view returns (uint256) {
        return maxRatePerSecond * (block.timestamp - startTime) + bonusAmount;
    }

    /**
     * @notice Returns the remaining unclaimed limit of tokens.
     * @return The remaining unclaimed limit of tokens.
     */
    function getUnclaimedLimit() external view returns (uint256) {
        return maxRatePerSecond * (block.timestamp - startTime) + bonusAmount - totalClaimed;
    }
}
