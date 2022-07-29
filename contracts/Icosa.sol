// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "./interfaces/Hedron.sol";
import "./interfaces/HEXStakeInstance.sol";
import "./interfaces/HEXStakeInstanceManager.sol";
import "./auxiliary/WeAreAllTheSA.sol";

// needed to patch some libraries for solc 8
import "./uniswap/TickMath.sol";
import "./uniswap/FullMath.sol";

/* Icosa is a collection of Ethereum / PulseChain smart contracts that  *
 * build upon the Hedron smart contract to provide additional functionality */

contract Icosa is ERC20 {

    IHEX    private _hx;
    IHedron private _hdrn;
    IHEXStakeInstanceManager private _hsim;

    // tunables
    uint8   private constant _stakeTypeHDRN         = 0;
    uint8   private constant _stakeTypeICSA         = 1;
    uint8   private constant _stakeTypeNFT          = 2;
    uint256 private constant _decimalResolution     = 1000000000000000000;
    uint16  private constant _icsaIntitialSeedDays  = 360;
    uint16  private constant _minStakeLengthDefault = 30;
    uint16  private constant _minStakeLengthSquid   = 90;
    uint16  private constant _minStakeLengthDolphin = 180;
    uint16  private constant _minStakeLengthShark   = 240;
    uint16  private constant _minStakeLengthWhale   = 360;
    uint8   private constant _stakeBonusDefault     = 0;
    uint8   private constant _stakeBonusSquid       = 5;
    uint8   private constant _stakeBonusDolphin     = 10;
    uint8   private constant _stakeBonusShark       = 15;
    uint8   private constant _stakeBonusWhale       = 20;
    uint8   private constant _twapInterval          = 15;
    uint8   private constant _waatsaEventLength     = 14;

    // address constants
    address         private constant _wethAddress     = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address         private constant _usdcAddress     = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address         private constant _hexAddress      = address(0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39);
    address         private constant _hdrnAddress     = address(0x3819f64f282bf135d62168C1e513280dAF905e06);
    address         private constant _maxiAddress     = address(0x0d86EB9f43C57f6FF3BC9E23D8F9d82503f0e84b);
    address payable private constant _hdrnFlowAddress = payable(address(0xF447BE386164dADfB5d1e7622613f289F17024D8));

    // We Are All the SA
    WeAreAllTheSA               private _waatsa;
    mapping(address => address) private _uniswapPools;
    address                     public  waatsa;

    // informational
    uint256 public launchDay;
    uint256 public currentDay;

    // seed liquidity spread out over multiple days
    mapping(uint256 => uint256) public hdrnSeedLiquidity;
    mapping(uint256 => uint256) public icsaSeedLiquidity;

    // HDRN Staking
    mapping(uint256 => uint256)    public hdrnPoolPoints;
    mapping(uint256 => uint256)    public hdrnPoolPayout;
    mapping(address => StakeStore) public hdrnStakes;
    uint256                        public hdrnPoolPointsRemoved;
    uint256                        public hdrnPoolIcsaCollected;
    
    // ICSA Staking
    mapping(uint256 => uint256)    public icsaPoolPoints;
    mapping(uint256 => uint256)    public icsaPoolPayoutIcsa;
    mapping(uint256 => uint256)    public icsaPoolPayoutHdrn;
    mapping(address => StakeStore) public icsaStakes;
    uint256                        public icsaPoolPointsRemoved;
    uint256                        public icsaPoolIcsaCollected;
    uint256                        public icsaPoolHdrnCollected;
    
    // NFT Staking
    mapping(uint256 => uint256)    public nftPoolPoints;
    mapping(uint256 => uint256)    public nftPoolPayout;
    mapping(uint256 => StakeStore) public nftStakes;
    uint256                        public nftPoolPointsRemoved;
    uint256                        public nftPoolIcsaCollected;

    constructor()
        ERC20("IcosaV2", "ICSAV2")
    {
        _hx   = IHEX(payable(_hexAddress));
        _hdrn = IHedron(_hdrnAddress);
        _hsim = IHEXStakeInstanceManager(_hdrn.hsim());

        // get total amount of burnt HDRN
        launchDay = currentDay = _hdrn.currentDay();
        uint256 hdrnBurntTotal;
        for (uint256 i = 0; i <= currentDay; i++) {
            HDRNDailyData memory hdrn = _hdrnDailyDataLoad(i);
            hdrnBurntTotal += hdrn.dayBurntTotal;
        }

        // calculate and seed intitial ICSA liquidity
        HEXGlobals memory hx = _hexGlobalsLoad();
        uint256 icsaInitialSeedTotal = hdrnBurntTotal / hx.shareRate;
        uint256 seedEnd = currentDay + _icsaIntitialSeedDays + 1;
        for (uint256 i = currentDay + 1; i < seedEnd; i++) {
            icsaSeedLiquidity[i] = icsaInitialSeedTotal / _icsaIntitialSeedDays;
        }

        // set up proof of benevolence
        _hdrn.approve(_hdrnAddress, type(uint256).max);

        // initialize We Are All the SA
        waatsa = address(new WeAreAllTheSA());
        _waatsa = WeAreAllTheSA(waatsa);

        // fill uniswap mappings
        _uniswapPools[_wethAddress] = address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640); // WETH/USDC V3 0.05%
        _uniswapPools[_hexAddress]  = address(0x69D91B94f0AaF8e8A2586909fA77A5c2c89818d5); // HEX/USDC  V3 0.3%
        _uniswapPools[_hdrnAddress] = address(0xE859041c9C6D70177f83DE991B9d757E13CEA26E); // HDRN/USDC V3 1.0%
        _uniswapPools[_maxiAddress] = address(0xF5595d56ccB6Cb87a463C558cAD04f49Faa61149); // MAXI/USDC V3 1.0%
    }

    function decimals()
        public
        view
        virtual
        override
        returns (uint8) 
    {
        return 9;
    }

     event HSIBuyBack(
        uint256         price,
        address indexed seller,
        uint40  indexed stakeId
    );

     event HDRNStakeStart(
        uint256         data,
        address indexed staker
    );

    event HDRNStakeAddCapital(
        uint256         data,
        address indexed staker
    );

    event HDRNStakeEnd(
        uint256         data,
        address indexed staker
    );

    event ICSAStakeStart(
        uint256         data,
        address indexed staker
    );

    event ICSAStakeAddCapital(
        uint256         data,
        address indexed staker
    );

    event ICSAStakeEnd(
        uint256         data0,
        uint256         data1,
        address indexed staker
    );

    event NFTStakeStart(
        uint256         data,
        address indexed staker,
        uint96  indexed nftId,
        address indexed tokenAddress
    );

    event NFTStakeEnd(
        uint256         data,
        address indexed staker,
        uint96  indexed nftId
    );

    /**
     * @dev Loads HEX global values from the HEX contract into a "Globals" object.
     * @return "HEXGlobals" object containing the global values returned by the HEX contract.
     */
    function _hexGlobalsLoad()
        internal
        view
        returns (HEXGlobals memory)
    {
        uint72  lockedHeartsTotal;
        uint72  nextStakeSharesTotal;
        uint40  shareRate;
        uint72  stakePenaltyTotal;
        uint16  dailyDataCount;
        uint72  stakeSharesTotal;
        uint40  latestStakeId;
        uint128 claimStats;

        (lockedHeartsTotal,
         nextStakeSharesTotal,
         shareRate,
         stakePenaltyTotal,
         dailyDataCount,
         stakeSharesTotal,
         latestStakeId,
         claimStats) = _hx.globals();

        return HEXGlobals(
            lockedHeartsTotal,
            nextStakeSharesTotal,
            shareRate,
            stakePenaltyTotal,
            dailyDataCount,
            stakeSharesTotal,
            latestStakeId,
            claimStats
        );
    }

    /**
     * @dev Loads Hedron daily values from the Hedron contract into a "HDRNDailyData" object.
     * @param hdrnDay The Hedron day to retrieve daily data for.
     * @return "HDRNDailyData" object containing the daily values returned by the Hedron contract.
     */
    function _hdrnDailyDataLoad(uint256 hdrnDay)
        internal
        view
        returns (HDRNDailyData memory)
    {
        uint72 dayMintedTotal;
        uint72 dayLoanedTotal;
        uint72 dayBurntTotal;
        uint32 dayInterestRate;
        uint8  dayMintMultiplier;

        (dayMintedTotal,
         dayLoanedTotal,
         dayBurntTotal,
         dayInterestRate,
         dayMintMultiplier
         ) = _hdrn.dailyDataList(hdrnDay);

        return HDRNDailyData(
            dayMintedTotal,
            dayLoanedTotal,
            dayBurntTotal,
            dayInterestRate,
            dayMintMultiplier
        );
    }

    /**
     * @dev Loads share data from a HEX stake instance (HSI) into a "HDRNShareCache" object.
     * @param hsi The HSI to load share data from.
     * @return "HDRNShareCache" object containing the share data of the HSI.
     */
    function _hsiLoad(
        IHEXStakeInstance hsi
    ) 
        internal
        view
        returns (HDRNShareCache memory)
    {
        HEXStakeMinimal memory stake;

        uint16 mintedDays;
        uint8  launchBonus;
        uint16 loanStart;
        uint16 loanedDays;
        uint32 interestRate;
        uint8  paymentsMade;
        bool   isLoaned;

        (stake,
         mintedDays,
         launchBonus,
         loanStart,
         loanedDays,
         interestRate,
         paymentsMade,
         isLoaned) = hsi.share();

        return HDRNShareCache(
            stake,
            mintedDays,
            launchBonus,
            loanStart,
            loanedDays,
            interestRate,
            paymentsMade,
            isLoaned
        );
    }

    /**
     * @dev Calculates the minimum stake length (in days) based on staker class.
     * @param stakerClass Number representing a stakes percentage of total supply
     * @return Calculated minimum stake length (in days).
     */
    function _calcMinStakeLength(
        uint256 stakerClass
    )
        internal
        pure
        returns (uint256)
    {
        uint256 minStakeLength = _minStakeLengthDefault;

        if (stakerClass >= (_decimalResolution / 100)) {
            minStakeLength = _minStakeLengthWhale;
        } else if (stakerClass >= (_decimalResolution / 1000)) {
            minStakeLength = _minStakeLengthShark;
        } else if (stakerClass >= (_decimalResolution / 10000)) {
            minStakeLength = _minStakeLengthDolphin;
        } else if (stakerClass >= (_decimalResolution / 100000)) {
            minStakeLength = _minStakeLengthSquid;
        }

        return minStakeLength;
    }

    /**
     * @dev Calculates the end stake bonus based on staker class (in days) and base payout.
     * @param stakerClass Number representing a stakes percentage of total supply
     * @param payout Base payout of the stake.
     * @return Amount of bonus tokens
     */
    function _calcStakeBonus(
        uint256 stakerClass,
        uint256 payout
    )
        internal
        pure
        returns (uint256)
    {
        uint256 bonus = payout;

        if (stakerClass >= (_decimalResolution / 100)) {
            bonus = (payout * (_stakeBonusWhale + _decimalResolution)) / _decimalResolution;
        } else if (stakerClass >= (_decimalResolution / 1000)) {
            bonus = (payout * (_stakeBonusShark + _decimalResolution)) / _decimalResolution;
        } else if (stakerClass >= (_decimalResolution / 10000)) {
            bonus = (payout * (_stakeBonusDolphin + _decimalResolution)) / _decimalResolution;
        } else if (stakerClass >= (_decimalResolution / 100000)) {
            bonus = (payout * (_stakeBonusSquid + _decimalResolution)) / _decimalResolution;
        }

        return (bonus - payout);
    }

    /**
     * @dev Calculates the end stake penalty based on time served.
     * @param minStakeDays Minimum stake length of the stake.
     * @param servedDays Number of days actually served.
     * @param amount Amount of tokens to caculate the penalty against.
     * @return The penalized payout and the penalty as separate values.
     */
    function _calcStakePenalty (
        uint256 minStakeDays,
        uint256 servedDays,
        uint256 amount
    )
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 payout;
        uint256 penalty;

        if (servedDays > 0) {
            uint256 servedPercentage = (minStakeDays * _decimalResolution) / servedDays;
            payout = (amount * _decimalResolution) / servedPercentage;
            penalty = (amount - payout);
        }
        else {
            payout = 0;
            penalty = amount;
        }

        return (payout, penalty); 
    }

    /**
     * @dev Adds a new stake to the stake mappings.
     * @param stakeType Type of stake to add.
     * @param stakePoints Amount of points the stake has been allocated.
     * @param stakeAmount Amount of tokens staked.
     * @param tokenId Token ID of the stake NFT (WAATSA only).
     * @param staker Address of the staker (HDRN / ICSA stakes only).
     * @param minStakeLength Minimum length the stake must serve without penalties.
     */
    function _stakeAdd(
        uint8   stakeType,
        uint256 stakePoints,
        uint256 stakeAmount,
        uint256 tokenId,
        address staker,
        uint256 minStakeLength
    )
        internal
    {
        if (stakeType == _stakeTypeHDRN) {
            hdrnStakes[staker] =
                StakeStore(
                    uint64(currentDay),
                    uint64(currentDay),
                    uint120(stakePoints),
                    true,
                    uint80(0),
                    uint80(0),
                    uint80(stakeAmount),
                    uint16(minStakeLength)
                );
        } else if (stakeType == _stakeTypeICSA) {
            icsaStakes[staker] =
                StakeStore(
                    uint64(currentDay),
                    uint64(currentDay),
                    uint120(stakePoints),
                    true,
                    uint80(0),
                    uint80(0),
                    uint80(stakeAmount),
                    uint16(minStakeLength)
                );
        } else if (stakeType == _stakeTypeNFT) {
            nftStakes[tokenId] =
                StakeStore(
                    uint64(currentDay),
                    uint64(currentDay),
                    uint120(stakePoints),
                    true,
                    uint80(0),
                    uint80(0),
                    uint80(stakeAmount),
                    uint16(minStakeLength)
                );
        } else {
            revert();
        }
    }

    /**
     * @dev Loads values from a "StakeStore" object into a "StakeCache" object.
     * @param stakeStore "StakeStore" object to be loaded.
     * @param stake "StakeCache" object to be populated with storage data.
     */
    function _stakeLoad(
        StakeStore storage stakeStore,
        StakeCache memory  stake
    )
        internal
        view
    {
        stake._stakeStart              = stakeStore.stakeStart;
        stake._capitalAdded            = stakeStore.capitalAdded;
        stake._stakePoints             = stakeStore.stakePoints;
        stake._isActive                = stakeStore.isActive;
        stake._payoutPreCapitalAddIcsa = stakeStore.payoutPreCapitalAddIcsa;
        stake._payoutPreCapitalAddHdrn = stakeStore.payoutPreCapitalAddHdrn;
        stake._stakeAmount             = stakeStore.stakeAmount;
        stake._minStakeLength          = stakeStore.minStakeLength;
    }

    /**
     * @dev Updates a "StakeStore" object with values stored in a "StakeCache" object.
     * @param stakeStore "StakeStore" object to be updated.
     * @param stake "StakeCache" object with updated values.
     */
    function _stakeUpdate(
        StakeStore storage stakeStore,
        StakeCache memory  stake
    )
        internal
    {
        stakeStore.stakeStart              = uint64 (stake._stakeStart);
        stakeStore.capitalAdded            = uint64 (stake._capitalAdded);
        stakeStore.stakePoints             = uint120(stake._stakePoints);
        stakeStore.isActive                = stake._isActive;
        stakeStore.payoutPreCapitalAddIcsa = uint80 (stake._payoutPreCapitalAddIcsa);
        stakeStore.payoutPreCapitalAddHdrn = uint80 (stake._payoutPreCapitalAddHdrn);
        stakeStore.stakeAmount             = uint80 (stake._stakeAmount);
        stakeStore.minStakeLength          = uint16 (stake._minStakeLength);
    }

    /**
     * @dev Updates all stake values which must wait for the follwing day to be
     *      properly accounted for. Primarily keeps track of payout per point
     *      and stake points per day.
     */
    function _stakeDailyUpdate ()
        internal
    {
        // Most of the magic happens in this function
        
        uint256 hdrnDay = _hdrn.currentDay();

        if (currentDay < hdrnDay) {
            uint256 daysPast = hdrnDay - currentDay;
            
            for (uint256 i = 0; i < daysPast; i++) {
                HEXGlobals    memory hx   = _hexGlobalsLoad();
                HDRNDailyData memory hdrn = _hdrnDailyDataLoad(currentDay);

                uint256 newPoolPoints;

                // HDRN Staking
                uint256 newHdrnPoolPayout;
                newPoolPoints = (hdrnPoolPoints[currentDay + 1] + hdrnPoolPoints[currentDay]) - hdrnPoolPointsRemoved;

                // if there are stakes in the pool, else carry the previous day forward.
                if (newPoolPoints > 0) {
                    // calculate next day's payout per point
                    newHdrnPoolPayout = ((hdrn.dayBurntTotal * _decimalResolution) / hx.shareRate) + (hdrnPoolIcsaCollected * _decimalResolution) + (icsaSeedLiquidity[currentDay + 1] * _decimalResolution);
                    newHdrnPoolPayout /= newPoolPoints;
                    newHdrnPoolPayout += hdrnPoolPayout[currentDay];

                    // drain the collection
                    hdrnPoolIcsaCollected = 0;
                } else {
                    newHdrnPoolPayout = hdrnPoolPayout[currentDay];
                    
                    // carry the would be payout forward until there are stakes in the pool
                    hdrnPoolIcsaCollected += (hdrn.dayBurntTotal / hx.shareRate) + icsaSeedLiquidity[currentDay + 1];
                }

                hdrnPoolPayout[currentDay + 1] = newHdrnPoolPayout;
                hdrnPoolPoints[currentDay + 1] = newPoolPoints;
                hdrnPoolPointsRemoved = 0;

                // ICSA Staking
                uint256 newIcsaPoolPayoutIcsa;
                uint256 newIcsaPoolPayoutHdrn;
                newPoolPoints = (icsaPoolPoints[currentDay + 1] + icsaPoolPoints[currentDay]) - icsaPoolPointsRemoved;

                // if there are stakes in the pool, else carry the previous day forward.
                if (newPoolPoints > 0) {
                    // calculate next day's ICSA payout per point
                    newIcsaPoolPayoutIcsa = ((hdrn.dayBurntTotal * _decimalResolution) / hx.shareRate) + (icsaPoolIcsaCollected * _decimalResolution) + (icsaSeedLiquidity[currentDay + 1] * _decimalResolution);
                    newIcsaPoolPayoutIcsa /= newPoolPoints;
                    newIcsaPoolPayoutIcsa += icsaPoolPayoutIcsa[currentDay];

                    // calculate next day's HDRN payout per point
                    newIcsaPoolPayoutHdrn = (icsaPoolHdrnCollected * _decimalResolution) + (hdrnSeedLiquidity[currentDay + 1] * _decimalResolution);
                    newIcsaPoolPayoutHdrn /= newPoolPoints;
                    newIcsaPoolPayoutHdrn += icsaPoolPayoutHdrn[currentDay];
                    // drain the collections
                    icsaPoolIcsaCollected = 0;
                    icsaPoolHdrnCollected = 0;
                } else {
                    newIcsaPoolPayoutIcsa = icsaPoolPayoutIcsa[currentDay];
                    newIcsaPoolPayoutHdrn = icsaPoolPayoutHdrn[currentDay];

                    // carry the would be payout forward until there are stakes in the pool
                    icsaPoolIcsaCollected += (hdrn.dayBurntTotal / hx.shareRate) + icsaSeedLiquidity[currentDay + 1];
                    icsaPoolHdrnCollected += hdrnSeedLiquidity[currentDay + 1];
                }

                icsaPoolPayoutIcsa[currentDay + 1] = newIcsaPoolPayoutIcsa;
                icsaPoolPayoutHdrn[currentDay + 1] = newIcsaPoolPayoutHdrn;
                icsaPoolPoints[currentDay + 1] = newPoolPoints;
                icsaPoolPointsRemoved = 0;

                // NFT Staking
                uint256 newNftPoolPayout;
                newPoolPoints = (nftPoolPoints[currentDay + 1] + nftPoolPoints[currentDay]) - nftPoolPointsRemoved;

                // if there are stakes in the pool, else carry the previous day forward.
                if (newPoolPoints > 0) {
                    // calculate next day's payout per point
                    newNftPoolPayout = ((hdrn.dayBurntTotal * _decimalResolution) / hx.shareRate) + (nftPoolIcsaCollected * _decimalResolution) + (icsaSeedLiquidity[currentDay + 1] * _decimalResolution);
                    newNftPoolPayout /= newPoolPoints;
                    newNftPoolPayout += nftPoolPayout[currentDay];

                    // drain the collection
                    nftPoolIcsaCollected = 0;
                } else {
                    newNftPoolPayout = nftPoolPayout[currentDay];

                    // carry the would be payout forward until there are stakes in the pool
                    nftPoolIcsaCollected += (hdrn.dayBurntTotal / hx.shareRate) + icsaSeedLiquidity[currentDay + 1];
                }
                
                nftPoolPayout[currentDay + 1] = newNftPoolPayout;
                nftPoolPoints[currentDay + 1] = newPoolPoints;
                nftPoolPointsRemoved = 0;

                // all math is done, advance to the next day
                currentDay++;
            }
        }
    }

    /**
     * @dev Fetches time weighted price square root (scaled 2 ** 96) from a uniswap v3 pool. 
     * @param uniswapV3Pool Address of the uniswap v3 pool.
     * @return Time weighted square root token price (scaled 2 ** 96).
     */
    function getSqrtTwapX96(
        address uniswapV3Pool
    )
        internal
        view 
        returns (uint160)
    {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = _twapInterval;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(uniswapV3Pool).observe(secondsAgos);

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives[1] - tickCumulatives[0]) / int8(_twapInterval))
        );

        return sqrtPriceX96;
    }

    /**
     * @dev Converts a uniswap v3 square root price into a token price (scaled 2 ** 96).
     * @param sqrtPriceX96 Square root uniswap pool price (scaled 2 ** 96).
     * @return Token price (scaled 2 ** 96).
     */
    function getPriceX96FromSqrtPriceX96(
        uint160 sqrtPriceX96
    )
        internal 
        pure
        returns(uint256)
    {
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }

    // External Functions

    // HSI Buy-Back

    /**
     * @dev Sells an HSI NFT token to the Icosa contract.
     * @param tokenId Token ID of the HSI NFT.
     * @return Amount of ICSA paid to the seller.
     */
    function hexStakeSell (
        uint256 tokenId
    )
        external
        returns (uint256)
    {
        _stakeDailyUpdate();

        require(_hsim.ownerOf(tokenId) == msg.sender,
            "ICSA: Selling requires token ownership");

        // load HSI stake data and HEX share rate
        HDRNShareCache memory share  = _hsiLoad(IHEXStakeInstance(_hsim.hsiToken(tokenId)));
        HEXGlobals memory hexGlobals = _hexGlobalsLoad();

        // mint ICSA to the caller
        uint256 borrowableHdrn = share._stake.stakeShares * (share._stake.stakedDays - share._mintedDays);
        uint256 payout         = borrowableHdrn / (hexGlobals.shareRate / 10);
        
        require(payout > 0,
            "ICSA: Insufficient HSI value");

        uint256 qcBonus;
        uint256 hlBonus = ((payout * (1000 + share._launchBonus)) / 1000) - payout;

        if (share._stake.stakedDays == 5555) {
            qcBonus = ((payout * 110) / 100) - payout;
        }

        nftPoolIcsaCollected += qcBonus + hlBonus;

        _mint(msg.sender, (payout + qcBonus + hlBonus));

        // transfer and detokenize the HSI
        _hsim.transferFrom(msg.sender, address(this), tokenId);
        address hsiAddress = _hsim.hexStakeDetokenize(tokenId);
        uint256 hsiCount   = _hsim.hsiCount(address(this));

        // borrow HDRN against the HSI
        icsaPoolHdrnCollected += _hdrn.loanInstanced(hsiCount - 1, hsiAddress);

        emit HSIBuyBack(payout, msg.sender, share._stake.stakeId);

        return (payout + qcBonus + hlBonus);
    }

    // HDRN Staking

    /**
     * @dev Starts a HDRN stake.
     * @param amount Amount of HDRN to stake.
     * @return Number of stake points allocated to the stake.
     */
    function hdrnStakeStart (
        uint256 amount
    )
        external
        returns (uint256)
    {
        _stakeDailyUpdate();

        // load stake into memory
        StakeCache memory stake;
        _stakeLoad(hdrnStakes[msg.sender], stake);

        require(stake._isActive == false,
            "ICSA: Stake already exists");

        require(_hdrn.balanceOf(msg.sender) >= amount,
            "ICSA: Insufficient HDRN balance");

        // get the HEX share rate and calculate stake points
        HEXGlobals memory hexGlobals = _hexGlobalsLoad();
        uint256 stakePoints = amount / hexGlobals.shareRate;

        uint256 stakerClass = (amount * _decimalResolution) / _hdrn.totalSupply();
        
        require(stakePoints > 0,
            "ICSA: Insufficient stake size");

        uint256 minStakeLength = _calcMinStakeLength(stakerClass);

        // add stake entry
        _stakeAdd (
            _stakeTypeHDRN,
            stakePoints,
            amount,
            0,
            msg.sender,
            minStakeLength
        );

        // add stake to the pool (following day)
        hdrnPoolPoints[currentDay + 1] += stakePoints;

        // transfer HDRN to the contract and return stake points
        _hdrn.transferFrom(msg.sender, address(this), amount);

        emit HDRNStakeStart(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint120(stakePoints))    << 40)
                |  (uint256(uint80 (amount))         << 160)
                |  (uint256(uint16 (minStakeLength)) << 240),
            msg.sender
        );

        return stakePoints;
    }

    /**
     * @dev Adds more HDRN to an existing stake.
     * @param amount Amount of HDRN to add to the stake.
     * @return Number of stake points allocated to the stake.
     */
    function hdrnStakeAddCapital (
        uint256 amount
    )
        external
        returns (uint256)
    {
        _stakeDailyUpdate();

        // load stake into memory
        StakeCache memory stake;
        _stakeLoad(hdrnStakes[msg.sender], stake);

        require(stake._isActive == true,
            "ICSA: Stake does not exist");

        require(_hdrn.balanceOf(msg.sender) >= amount,
            "ICSA: Insufficient HDRN balance");

        // get the HEX share rate and calculate additional stake points
        HEXGlobals memory hexGlobals = _hexGlobalsLoad();
        uint256 stakePoints = amount / hexGlobals.shareRate;

        uint256 stakerClass = ((stake._stakeAmount + amount) * _decimalResolution) / _hdrn.totalSupply();

        require(stakePoints > 0,
            "ICSA: Insufficient stake size");

        // lock in payout from previous stake points
        uint256 payoutPerPoint = hdrnPoolPayout[currentDay] - hdrnPoolPayout[stake._capitalAdded];
        uint256 payout = (stake._stakePoints * payoutPerPoint) / _decimalResolution;

        uint256 minStakeLength = _calcMinStakeLength(stakerClass);

        // update stake entry
        stake._capitalAdded             = currentDay;
        stake._stakePoints             += stakePoints;
        stake._payoutPreCapitalAddIcsa += payout;
        stake._stakeAmount             += amount;
        stake._minStakeLength           = minStakeLength;
        _stakeUpdate(hdrnStakes[msg.sender], stake);

        // add additional points to the pool (following day)
        hdrnPoolPoints[currentDay + 1] += stakePoints;

        // transfer HDRN to the contract and return stake points
        _hdrn.transferFrom(msg.sender, address(this), amount);

        emit HDRNStakeAddCapital(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint120(stakePoints))    << 40)
                |  (uint256(uint80 (amount))         << 160)
                |  (uint256(uint16 (minStakeLength)) << 240),
            msg.sender
        );

        return stake._stakePoints;
    }

    /**
     * @dev Ends a HDRN stake.
     * @return ICSA yield, HDRN principal penalty, ICSA yield penalty.
     */
    function hdrnStakeEnd () 
        external
        returns (uint256, uint256, uint256)
    {
        _stakeDailyUpdate();

        // load stake into memory
        StakeCache memory stake;
        _stakeLoad(hdrnStakes[msg.sender], stake);

        require(stake._isActive == true,
            "ICSA: Stake does not exist");

        // ended pending stake, just reverse it.
        if (stake._stakeStart == currentDay) {
            // return staked principal
            _hdrn.transfer(msg.sender, stake._stakeAmount);

            // remove points from the pool
            hdrnPoolPointsRemoved += stake._stakePoints;

            // update stake entry
            stake._stakeStart              = 0;
            stake._capitalAdded            = 0;
            stake._stakePoints             = 0;
            stake._isActive                = false;
            stake._payoutPreCapitalAddIcsa = 0;
            stake._stakeAmount             = 0;
            stake._minStakeLength          = 0;
            _stakeUpdate(hdrnStakes[msg.sender], stake);

            emit HDRNStakeEnd(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint72(0)) << 40)
                |  (uint256(uint72(0)) << 112)
                |  (uint256(uint72(0)) << 184),
            msg.sender
            );

            return (0,0,0);
        }

        // calculate payout per point
        uint256 payoutPerPoint = hdrnPoolPayout[currentDay] - hdrnPoolPayout[stake._capitalAdded];

        uint256 payout;
        uint256 bonus;
        uint256 payoutPenalty;
        uint256 principal;
        uint256 principalPenalty;

        if ((stake._capitalAdded + stake._minStakeLength) > currentDay) {
            uint256 servedDays = currentDay - stake._capitalAdded;
            
            payout = stake._payoutPreCapitalAddIcsa + ((stake._stakePoints * payoutPerPoint) / _decimalResolution);
            (payout, payoutPenalty) = _calcStakePenalty(stake._minStakeLength, servedDays, payout);

            // distribute ICSA penalties
            hdrnPoolIcsaCollected += payoutPenalty / 3;
            icsaPoolIcsaCollected += payoutPenalty / 3;
            nftPoolIcsaCollected  += payoutPenalty / 3;

            principal = stake._stakeAmount;
            (principal, principalPenalty) = _calcStakePenalty(stake._minStakeLength, servedDays, principal);

            // distribute HDRN penalties
            _hdrn.proofOfBenevolence(principalPenalty / 2);
            icsaPoolHdrnCollected += principalPenalty / 2;
        } else {
            uint256 stakerClass = (stake._stakeAmount * _decimalResolution) / _hdrn.totalSupply();

            payout = stake._payoutPreCapitalAddIcsa + ((stake._stakePoints * payoutPerPoint) / _decimalResolution);
            bonus  = _calcStakeBonus(stakerClass, payout);
            principal = stake._stakeAmount;
        }

        // remove points from the pool
        hdrnPoolPointsRemoved += stake._stakePoints;

        // update stake entry
        stake._stakeStart              = 0;
        stake._capitalAdded            = 0;
        stake._stakePoints             = 0;
        stake._isActive                = false;
        stake._payoutPreCapitalAddIcsa = 0;
        stake._stakeAmount             = 0;
        stake._minStakeLength          = 0;
        _stakeUpdate(hdrnStakes[msg.sender], stake);

        nftPoolIcsaCollected += bonus;

        // mint ICSA and return payout
        if (payout > 0) { _mint(msg.sender, (payout + bonus)); }

        // return staked principal
        if (principal > 0) { _hdrn.transfer(msg.sender, principal); }

        emit HDRNStakeEnd(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint72(payout + bonus))   << 40)
                |  (uint256(uint72(principalPenalty)) << 112)
                |  (uint256(uint72(payoutPenalty))    << 184),
            msg.sender
        );

        return ((payout + bonus), principalPenalty, payoutPenalty);
    }

    // ICSA Staking

    /**
     * @dev Starts an ICSA stake.
     * @param amount Amount of ICSA to stake.
     * @return Number of stake points allocated to the stake.
     */
    function icsaStakeStart (
        uint256 amount
    )
        external
        returns (uint256)
    {
        _stakeDailyUpdate();

        // load stake into memory
        StakeCache memory stake;
        _stakeLoad(icsaStakes[msg.sender], stake);

        require(stake._isActive == false,
            "ICSA: Stake already exists");

        require(balanceOf(msg.sender) >= amount,
            "ICSA: Insufficient ICSA balance");

        // get the HEX share rate and calculate stake points
        HEXGlobals memory hexGlobals = _hexGlobalsLoad();
        uint256 stakePoints = amount / hexGlobals.shareRate;

        uint256 stakerClass = (amount * _decimalResolution) / totalSupply();
        
        require(stakePoints > 0,
            "ICSA: Insufficient stake size");

        uint256 minStakeLength = _calcMinStakeLength(stakerClass);

        // add stake entry
        _stakeAdd (
            _stakeTypeICSA,
            stakePoints,
            amount,
            0,
            msg.sender,
            minStakeLength
        );

        // add stake to the pool (following day)
        icsaPoolPoints[currentDay + 1] += stakePoints;

        // temporarily burn stakers ICSA
        _burn(msg.sender, amount);

        emit ICSAStakeStart(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint120(stakePoints))    << 40)
                |  (uint256(uint80 (amount))         << 160)
                |  (uint256(uint16 (minStakeLength)) << 240),
            msg.sender
        );

        return stakePoints;
    }

    /**
     * @dev Adds more ICSA to an existing stake.
     * @param amount Amount of ICSA to add to the stake.
     * @return Number of stake points allocated to the stake.
     */
    function icsaStakeAddCapital (
        uint256 amount
    )
        external
        returns (uint256)
    {
        _stakeDailyUpdate();

        // load stake into memory
        StakeCache memory stake;
        _stakeLoad(icsaStakes[msg.sender], stake);

        require(stake._isActive == true,
            "ICSA: Stake does not exist");

        require(balanceOf(msg.sender) >= amount,
            "ICSA: Insufficient ICSA balance");

        // get the HEX share rate and calculate additional stake points
        HEXGlobals memory hexGlobals = _hexGlobalsLoad();
        uint256 stakePoints = amount / hexGlobals.shareRate;

        uint256 stakerClass = ((stake._stakeAmount + amount) * _decimalResolution) / totalSupply();

        require(stakePoints > 0,
            "ICSA: Insufficient stake size");

        // lock in payout from previous stake points
        uint256 payoutPerPointIcsa = icsaPoolPayoutIcsa[currentDay] - icsaPoolPayoutIcsa[stake._capitalAdded];
        uint256 payoutIcsa = (stake._stakePoints * payoutPerPointIcsa) / _decimalResolution;

        uint256 payoutPerPointHdrn = icsaPoolPayoutHdrn[currentDay] - icsaPoolPayoutHdrn[stake._capitalAdded];
        uint256 payoutHdrn = (stake._stakePoints * payoutPerPointHdrn) / _decimalResolution;

        uint256 minStakeLength = _calcMinStakeLength(stakerClass);

        // update stake entry
        stake._capitalAdded             = currentDay;
        stake._stakePoints             += stakePoints;
        stake._payoutPreCapitalAddIcsa += payoutIcsa;
        stake._payoutPreCapitalAddHdrn += payoutHdrn;
        stake._stakeAmount             += amount;
        stake._minStakeLength           = minStakeLength;
        _stakeUpdate(icsaStakes[msg.sender], stake);

        // add additional points to the pool (following day)
        icsaPoolPoints[currentDay + 1] += stakePoints;

        // temporarily burn stakers ICSA
        _burn(msg.sender, amount);

        emit ICSAStakeAddCapital(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint120(stakePoints))    << 40)
                |  (uint256(uint80 (amount))         << 160)
                |  (uint256(uint16 (minStakeLength)) << 240),
            msg.sender
        );

        return stake._stakePoints;
    }

    /**
     * @dev Ends an ICSA stake.
     * @return ICSA yield, HDRN yield, ICSA principal penalty, HDRN yield penalty, ICSA yield penalty.
     */
    function icsaStakeEnd () 
        external
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        _stakeDailyUpdate();

        // load stake into memory
        StakeCache memory stake;
        _stakeLoad(icsaStakes[msg.sender], stake);

        require(stake._isActive == true,
            "ICSA: Stake does not exist");

        // ended pending stake, just reverse it.
        if (stake._stakeStart == currentDay) {
            // return staked principal
            _mint(msg.sender, stake._stakeAmount);
            
            // remove points from the pool
            icsaPoolPointsRemoved += stake._stakePoints;

            // update stake entry
            stake._stakeStart              = 0;
            stake._capitalAdded            = 0;
            stake._stakePoints             = 0;
            stake._isActive                = false;
            stake._payoutPreCapitalAddIcsa = 0;
            stake._payoutPreCapitalAddHdrn = 0;
            stake._stakeAmount             = 0;
            stake._minStakeLength          = 0;
            _stakeUpdate(icsaStakes[msg.sender], stake);

            emit ICSAStakeEnd(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint72(0)) << 40)
                |  (uint256(uint72(0)) << 112)
                |  (uint256(uint72(0)) << 184),
            uint256(uint128(0))
                |  (uint256(uint128(0)) << 128),
            msg.sender
            );

            return (0,0,0,0,0);
        }

        // calculate payout per point
        uint256 payoutPerPointIcsa = icsaPoolPayoutIcsa[currentDay] - icsaPoolPayoutIcsa[stake._capitalAdded];
        uint256 payoutPerPointHdrn = icsaPoolPayoutHdrn[currentDay] - icsaPoolPayoutHdrn[stake._capitalAdded];

        uint256 payoutIcsa;
        uint256 bonusIcsa;
        uint256 payoutHdrn;
        uint256 payoutPenaltyIcsa;
        uint256 payoutPenaltyHdrn;
        uint256 principal;
        uint256 principalPenalty;

        if ((stake._capitalAdded + stake._minStakeLength) > currentDay) {
            uint256 servedDays = currentDay - stake._capitalAdded;
            
            payoutIcsa = stake._payoutPreCapitalAddIcsa + ((stake._stakePoints * payoutPerPointIcsa) / _decimalResolution);
            (payoutIcsa, payoutPenaltyIcsa) = _calcStakePenalty(stake._minStakeLength, servedDays, payoutIcsa);

            payoutHdrn = stake._payoutPreCapitalAddHdrn + ((stake._stakePoints * payoutPerPointHdrn) / _decimalResolution);
            (payoutHdrn, payoutPenaltyHdrn) = _calcStakePenalty(stake._minStakeLength, servedDays, payoutHdrn);

            principal = stake._stakeAmount;
            (principal, principalPenalty) = _calcStakePenalty(stake._minStakeLength, servedDays, principal);

            // distribute ICSA penalties
            hdrnPoolIcsaCollected += (payoutPenaltyIcsa + principalPenalty) / 3;
            icsaPoolIcsaCollected += (payoutPenaltyIcsa + principalPenalty) / 3;
            nftPoolIcsaCollected  += (payoutPenaltyIcsa + principalPenalty) / 3;

            // distribute HDRN penalties
            _hdrn.proofOfBenevolence(payoutPenaltyHdrn / 2);
            icsaPoolHdrnCollected += payoutPenaltyHdrn / 2;
        } else {
            uint256 stakerClass = (stake._stakeAmount * _decimalResolution) / totalSupply();

            payoutIcsa = stake._payoutPreCapitalAddIcsa + ((stake._stakePoints * payoutPerPointIcsa) / _decimalResolution);
            payoutHdrn = stake._payoutPreCapitalAddHdrn + ((stake._stakePoints * payoutPerPointHdrn) / _decimalResolution);
            bonusIcsa = _calcStakeBonus(stakerClass, payoutIcsa);
            principal = stake._stakeAmount;
        }

        // remove points from the pool
        icsaPoolPointsRemoved += stake._stakePoints;

        // update stake entry
        stake._stakeStart              = 0;
        stake._capitalAdded            = 0;
        stake._stakePoints             = 0;
        stake._isActive                = false;
        stake._payoutPreCapitalAddIcsa = 0;
        stake._payoutPreCapitalAddHdrn = 0;
        stake._stakeAmount             = 0;
        stake._minStakeLength          = 0;
        _stakeUpdate(icsaStakes[msg.sender], stake);

        nftPoolIcsaCollected += bonusIcsa;

        // mint ICSA
        if (payoutIcsa + principal > 0) { _mint(msg.sender, (payoutIcsa + principal + bonusIcsa)); }

        // transfer HDRN
        if (payoutHdrn > 0) { _hdrn.transfer(msg.sender, payoutHdrn); }

        emit ICSAStakeEnd(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint72(payoutIcsa + bonusIcsa))       << 40)
                |  (uint256(uint72(payoutHdrn))       << 112)
                |  (uint256(uint72(principalPenalty)) << 184),
            uint256(uint128(payoutPenaltyIcsa))
                |  (uint256(uint128(payoutPenaltyHdrn)) << 128),
            msg.sender
        );

        return ((payoutIcsa + bonusIcsa), payoutHdrn, principalPenalty, payoutPenaltyIcsa, payoutPenaltyHdrn);
    }

    // NFT Staking

    /**
     * @dev Starts an NFT stake.
     * @param amount Amount of tokens to buy the NFT with.
     * @param tokenAddress Address of the token contract.
     * @return Number of stake points allocated to the stake.
     */
    function nftStakeStart (
        uint256 amount,
        address tokenAddress
    )
        external
        payable
        returns (uint256)
    {
        _stakeDailyUpdate();

        require(currentDay < (launchDay + _waatsaEventLength),
            "ICSA: WAATSA entry has closed");

        // Fallback in case PulseChain launches mid-WAATSA
        //require(block.chainid == 1, 
        //    "ICSA: WAATSA is only supported on Ethereum");

        uint256 tokenPrice;
        uint256 stakePoints;

        IERC20 token = IERC20(tokenAddress);

        // ETH handler
        if (tokenAddress == address(0)) {

            // weth pools are backwards for some reason.
            tokenPrice = getPriceX96FromSqrtPriceX96(getSqrtTwapX96(_uniswapPools[_wethAddress]));
            stakePoints = (amount * (2**96)) / tokenPrice;
            
            _hdrnFlowAddress.transfer(amount);
        }

        // ERC20 handler
        else {    
            address uniswapPool = _uniswapPools[tokenAddress];

            require(token.balanceOf(msg.sender) >= amount,
                "ICSA: Insufficient token balance");

            if (tokenAddress != _usdcAddress) {
                require(uniswapPool != address(0),
                    "ICSA: Invalid token address");

                // weth pools are backwards for some reason.
                if (tokenAddress == _wethAddress) {
                    tokenPrice = getPriceX96FromSqrtPriceX96(getSqrtTwapX96(uniswapPool));
                    stakePoints = (amount * (2**96)) / tokenPrice;
                }

                else {
                    tokenPrice = getPriceX96FromSqrtPriceX96(getSqrtTwapX96(uniswapPool));
                    stakePoints = (amount * tokenPrice) / (2 ** 96);
                }
            }

            else {
                stakePoints = amount;
            }

            token.transferFrom(msg.sender, _hdrnFlowAddress, amount);
        }
        
        uint256 nftId = _waatsa.mintStakeNft(msg.sender);

        require(stakePoints > 0,
            "ICSA: Insufficient stake size");

        // add stake entry
        _stakeAdd (
            _stakeTypeNFT,
            stakePoints,
            0,
            nftId,
            address(0),
            0
        );

        // add stake to the pool (following day)
        nftPoolPoints[currentDay + 1] += stakePoints;

        emit NFTStakeStart(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint216(stakePoints)) << 40),
            msg.sender,
            uint96(nftId),
            tokenAddress
        );

        return stakePoints;
    }

    /**
     * @dev Ends an NFT stake.
     * @param nftId Token id of the staking NFT.
     * @return ICSA yield.
     */
    function nftStakeEnd (
        uint256 nftId
    ) 
        external
        returns (uint256)
    {
        _stakeDailyUpdate();

        require(_waatsa.ownerOf(nftId) == msg.sender,
            "ICSA: Ending WAATSA stake requires token ownership");
        
        // load stake into memory
        StakeCache memory stake;
        _stakeLoad(nftStakes[nftId], stake);

        require(stake._isActive == true,
            "ICSA: Stake does not exist");

        uint256 payoutPerPoint = nftPoolPayout[currentDay] - nftPoolPayout[stake._capitalAdded];
        uint256 payout = (stake._stakePoints * payoutPerPoint) / _decimalResolution;

        // remove points from the pool
        nftPoolPointsRemoved += stake._stakePoints;

        // update stake entry
        stake._stakeStart              = 0;
        stake._capitalAdded            = 0;
        stake._stakePoints             = 0;
        stake._isActive                = false;
        stake._payoutPreCapitalAddIcsa = 0;
        stake._payoutPreCapitalAddHdrn = 0;
        stake._stakeAmount             = 0;
        stake._minStakeLength          = 0;
        _stakeUpdate(nftStakes[nftId], stake);

        // mint ICSA
        if (payout > 0 ) { _mint(msg.sender, payout); }
        _waatsa.burnStakeNft(nftId);

        emit NFTStakeEnd(
            uint256(uint40 (block.timestamp))
                |  (uint256(uint216(payout)) << 40),
            msg.sender,
            uint96(nftId)
        );

        return payout;
    }

    function injectSeedLiquidity (
        uint256 amount,
        uint256 seedDays
    ) 
        external
    {
        require(_hdrn.balanceOf(msg.sender) >= amount,
            "ICSA: Insufficient HDRN balance");

        require(seedDays >= 1,
            "ICSA: Seed days must be at least 1");

        // calculate and seed ICSA liquidity
        HEXGlobals memory hx = _hexGlobalsLoad();
        uint256 icsaSeedTotal = amount / hx.shareRate;
        uint256 seedEnd = currentDay + seedDays + 1;

        for (uint256 i = currentDay + 1; i < seedEnd; i++) {
            icsaSeedLiquidity[i] += icsaSeedTotal / seedDays;
            hdrnSeedLiquidity[i] += amount / seedDays;
        }

        _hdrn.transferFrom(msg.sender, address(this), amount);
    }

    // Overrides

    /* In short, _stakeDailyUpdate needs to be called in all possible cases.
       This is to ensure the gas limit is never exceeded. By overriding these
       functions we ensure it is always called given any contract interraction. */
    
    function approve(
        address spender,
        uint256 amount
    ) 
        public
        virtual
        override
        returns (bool) 
    {
        _stakeDailyUpdate();
        return super.approve(spender, amount);
    }

    function transfer(
        address to,
        uint256 amount
    )
        public
        virtual
        override
        returns (bool)
    {
        _stakeDailyUpdate();
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) 
        public
        virtual
        override
        returns (bool)
    {
        _stakeDailyUpdate();
        return super.transferFrom(from, to, amount);
    }

    // REMOVE BEFORE LAUNCH TESTNET ONLY
        function tradeV1 (
        uint256 amount
    ) 
        external
    {
        IERC20 icsav1 = IERC20(address(0x3f9A1B67F3a3548e0ea5c9eaf43A402d12b6a273));

        require(icsav1.balanceOf(msg.sender) >= amount,
            "ICSA: Insufficient ICSAV1 balance");

        _mint(msg.sender, amount);       
        icsav1.transferFrom(msg.sender, _hdrnFlowAddress, amount);
    }
}