// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./External.sol";

struct StakeStore {
    uint64  stakeStart;
    uint64  capitalAdded;
    uint120 stakePoints;
    bool    isActive;
    uint80  payoutPreCapitalAddIcsa;
    uint80  payoutPreCapitalAddHdrn;
    uint80  stakeAmount;
    uint16  minStakeLength;
}

struct StakeCache {
    uint256 _stakeStart;
    uint256 _capitalAdded;
    uint256 _stakePoints;
    bool    _isActive;
    uint256 _payoutPreCapitalAddIcsa;
    uint256 _payoutPreCapitalAddHdrn;
    uint256 _stakeAmount;
    uint256 _minStakeLength;
}