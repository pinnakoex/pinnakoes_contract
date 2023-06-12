// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

library PIDData {
    // bytes32 constant opeProtectIdx = keccak256("opeProtectIdx");
    // using EnumerableSet for EnumerableSet.UintSet;
    // using EnumerableValues for EnumerableSet.UintSet;
    
    uint256 constant SCORE_PRECISION = 10 ** 18;
    uint256 constant PRICE_PRECISION = 10**30;
    uint256 constant USD_TO_SCORE_PRECISION = 10 ** 12;

    uint256 constant PERCENT_PRECISION = 10 ** 6;


    bytes32 constant REFERRAL_PARRENT = keccak256("REFERRAL_PARRENT");
    bytes32 constant REFERRAL_CHILD = keccak256("REFERRAL_CHILD");
    bytes32 constant ACCUM_POSITIONSIZE = keccak256("ACCUM_POSITIONSIZE");
    bytes32 constant ACCUM_SWAP = keccak256("ACCUM_SWAP");
    bytes32 constant ACCUM_ADDLIQUIDITY = keccak256("ACCUM_ADDLIQUIDITY");
    bytes32 constant ACCUM_SCORE = keccak256("ACCUM_SCORE");
    bytes32 constant TIME_SOCRE_DEC= keccak256("TIME_SOCRE_DEC");
    bytes32 constant TIME_RANK_UPD = keccak256("TIME_RANK_UPD"); 

    bytes32 constant VALID_SCORE_UPDATER = keccak256("VALID_SCORE_UPDATER");
    bytes32 constant MIN_MINT_TRADING_VALUE = keccak256("MIN_MINT_TRADING_VALUE");
    bytes32 constant INTERVAL_RANK_UPDATE = keccak256("INTERVAL_RANK_UPDATE");
    bytes32 constant INTERVAL_SCORE_UPDATE = keccak256("INTERVAL_SCORE_UPDATE");
   

    
    struct PIDStr {
        address owner;
        string nickName;
        string refCode;
        uint256 createTime;
        uint256 latestUpdateTime;
        uint256 score;
    }


    struct PIDDetailed {
        address owner;
        string nickName;
        string refCode;
        uint256 createTime;
        uint256 latestUpdateTime;
        uint256 score;

        uint256 rank;
        uint256 tradeVolume;
        uint256 swapVolume;
        uint256 liqVolume;

        address ref;
        address[] child;
    }

}