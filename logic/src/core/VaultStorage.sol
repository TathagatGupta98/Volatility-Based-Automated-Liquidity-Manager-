// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/* --------------------------------- import --------------------------------- */

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/**
 * @title VaultStorage
 * @notice Single source of truth for all state in the vault system.
 *         No functions. No logic. Only state declarations.
 *         Every other contract in the system inherits from this.
 */

/* -------------------------------------------------------------------------- */
/*                                  Contract                                  */
/* -------------------------------------------------------------------------- */

abstract contract VaultStorage {

/* --------------------------------- errors --------------------------------- */
    error NotOwner();
    error VaultPaused();
    error VaultNotInitialized();
    error ZeroDeposit();
    error BelowMinimumDeposit(uint256 valueUsdc, uint256 minimumUsdc);
    error InsufficientShares(uint256 requested, uint256 available);
    error ZeroShares();
    error NavStale(uint256 lastTimestamp, uint256 currentTimestamp);
    error InvalidTickSpacing(int24 slotWidth, int24 poolTickSpacing);
    error InvalidAlpha(uint256 alpha);
    error PositionNotFound(uint256 tokenId);
    error BufferEmpty();
    error NativeTransferFailed();

/* -------------------------------- Constants ------------------------------- */
uint256 internal constant WAD = 1e18;

    uint256 internal constant USDC_DECIMALS = 1e6;
    uint256 internal constant USDC_TO_ETH_PRECISION = 1e12;
    uint256 internal constant ETH_DECIMALS = 1e18;
    uint256 internal constant MIN_DEPOSIT_USDC = 20 * USDC_DECIMALS;
    uint256 internal constant BUFFER_LOWER_BOUND = 5e16; 
    uint256 internal constant BUFFER_UPPER_BOUND = 1e17; 
    uint256 internal constant INITIAL_DEAD_SHARES = 1000;

/* ------------------------------- immutables ------------------------------- */
    IPoolManager public immutable poolManager;
    IPositionManager public immutable positionManager;
    IAllowanceTransfer public immutable permit2;
    address public immutable USDC;
    address public immutable ethUsdPriceFeed;
    PoolKey public poolKey;

/* --------------------------- Type Decralrations --------------------------- */
    struct User {
        uint256 ethDeposited;
        uint256 usdcDeposited;
        uint256 sharesOwned;
        uint256 depositTimeStamp;
        bool isActive;
    }

    struct PositionInfo{
        uint256 tokenId;      
        int24 tickLower;      
        int24 tickUpper;      
        uint128 liquidity;    
        uint8 slotIndex;      
        bool isActive; 
    }

    struct WithdrawalRequest {
        address user;               
        uint256 sharesBurning;      
        uint256 requestTimestamp;   
        bool fulfilled;             
    }

/* ----------------------------- State Variables ---------------------------- */
    User[] public users;

    mapping(address => uint256) usersIndex;

    uint256 totalShares;
    uint256 totalEthDeposited;
    uint256 totalUsdcDeposited;
    uint256 idleEth;
    uint256 idleUsdc;
    uint256 lastNavEth; 
    uint256 lastNavTimestamp;
    uint256 totalPositions;

    uint8 volatility_check;
    uint256 public ewmaVariance;
    uint256 public lastObservationTimestamp;
    uint256 public ewmaAlpha;


    PositionInfo[] public positions;

    mapping(uint256 => uint256) public tokenIdToPositionIndex;
        
    uint256 public activePositionCount;
    int24 public distributionCenterTick;
    int24 public slotWidthTicks;

    address public owner;
    bool public paused;
    bool public initialized;

/* --------------------------------- events --------------------------------- */
    event Deposited(
        address indexed user,
        uint256 ethAmount,
        uint256 usdcAmount,
        uint256 sharesMinted,
        uint256 navAtDeposit
    );

    event Withdrawal(
        address indexed user,
        uint256 sharesBurned,
        uint256 ethReturned,
        uint256 usdcReturned,
        uint256 navAtWithdrawal
    );

    event WithdrawalPartial(
        address indexed user,
        uint256 sharesRequested,
        uint256 sharesBurned,
        uint256 ethReturned,
        uint256 usdcReturned
    );

    event NavUpdated(
        uint256 newNavUsdc,
        uint256 timestamp
    );

    event VolatilityUpdated(
        uint8  newClassification,
        uint256 newEwmaVariance,
        uint256 timestamp
    );

    event RebalanceTriggered(
        int24  oldCenterTick,
        int24  newCenterTick,
        uint8  volatilityClassification,
        uint256 navAtRebalance
    );

    event BufferReplenished(
        uint256 ethAdded,
        uint256 usdcAdded,
        uint256 newIdleEth,
        uint256 newIdleUsdc
    );

    event BufferDeployed(
        uint256 ethDeployed,
        uint256 usdcDeployed,
        uint256 remainingIdleEth,
        uint256 remainingIdleUsdc
    );

    event PositionMinted(
        uint256 indexed tokenId,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        uint8   slotIndex
    );

    event LiquidityIncreased(
        uint256 indexed tokenId,
        uint128 liquidityAdded,
        uint128 newTotalLiquidity
    );

    event LiquidityDecreased(
        uint256 indexed tokenId,
        uint128 liquidityRemoved,
        uint128 newTotalLiquidity,
        uint256 ethReceived,
        uint256 usdcReceived
    );

    event FeesCollected(
        uint256 indexed tokenId,
        uint256 ethFees,
        uint256 usdcFees
    );

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    event Paused(address indexed by);
    event Unpaused(address indexed by);

/* ------------------------------- Constructor ------------------------------ */
    constructor(
        address _poolManager,
        address _positionManager,
        address _permit2,
        address _usdc,
        PoolKey memory _poolKey,
        int24 _slotWidthTicks,
        uint256 _ewmaAlpha
    ) {
        if (_slotWidthTicks <= 0 || _slotWidthTicks % _poolKey.tickSpacing != 0)
            revert InvalidTickSpacing(_slotWidthTicks, _poolKey.tickSpacing);

        if (_ewmaAlpha == 0 || _ewmaAlpha >= WAD)
            revert InvalidAlpha(_ewmaAlpha);

        poolManager      = IPoolManager(_poolManager);
        positionManager  = IPositionManager(_positionManager);
        permit2          = IAllowanceTransfer(_permit2);
        USDC             = _usdc;

        poolKey          = _poolKey;
        slotWidthTicks   = _slotWidthTicks;

        ewmaAlpha        = _ewmaAlpha;
        volatility_check  = 1; 

        owner            = msg.sender;

        users.push(User({
            ethDeposited:     0,
            usdcDeposited:    0,
            sharesOwned:      0,
            depositTimeStamp: 0,
            isActive:         false
        }));
    }

    receive() external payable {}
}
