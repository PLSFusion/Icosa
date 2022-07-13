// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "../interfaces/HEX.sol";

struct HEXGlobals {
    uint72 lockedHeartsTotal;
    uint72 nextStakeSharesTotal;
    uint40 shareRate;
    uint72 stakePenaltyTotal;
    uint16 dailyDataCount;
    uint72 stakeSharesTotal;
    uint40 latestStakeId;
    uint128 claimStats;
}

struct HEXStake {
    uint40 stakeId;
    uint72 stakedHearts;
    uint72 stakeShares;
    uint16 lockedDay;
    uint16 stakedDays;
    uint16 unlockedDay;
    bool   isAutoStake;
}

struct HEXStakeMinimal {
    uint40 stakeId;
    uint72 stakeShares;
    uint16 lockedDay;
    uint16 stakedDays;
}

struct HDRNDailyData {
    uint72 dayMintedTotal;
    uint72 dayLoanedTotal;
    uint72 dayBurntTotal;
    uint32 dayInterestRate;
    uint8  dayMintMultiplier;
}

struct HDRNShareCache {
    HEXStakeMinimal _stake;
    uint256         _mintedDays;
    uint256         _launchBonus;
    uint256         _loanStart;
    uint256         _loanedDays;
    uint256         _interestRate;
    uint256         _paymentsMade;
    bool            _isLoaned;
}