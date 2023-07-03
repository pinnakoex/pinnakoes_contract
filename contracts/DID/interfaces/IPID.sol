// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "../PIDData.sol";

interface IPID {
    function scorePara(uint256 _paraId) external view returns (uint256);
    function createTime(address _account) external view returns (uint256);
    function nickName(address _account) external view returns (string memory);
    function getReferralForAccount(address _account) external view returns (address[] memory , address[] memory);
    function userSizeSum(address _account) external view returns (uint256);
    function getFeeDet(address _account, uint256 _origFee) external view returns (uint256, uint256, address);
    function getPIDAddMpUintetRoles(address _mpaddress, bytes32 _key) external view returns (uint256[] memory);
    function updateScoreForAccount(address _account, address /*_vault*/, uint256 _amount, uint256 _reasonCode) external;
    function updateTradingScoreForAccount(address _account, address _vault, uint256 _amount, uint256 _refCode) external;
    function updateSwapScoreForAccount(address _account, address _vault, uint256 _amount) external;
    function updateAddLiqScoreForAccount(address _account, address _vault, uint256 _amount, uint256 _refCode) external;
    function getRefCode(address _account) external view returns (string memory);
    function accountToDisReb(address _account) external view returns (uint256, uint256);
    function rank(address _account) external view returns (uint256);
    function score(address _account) external view returns (uint256);
    function addressToTokenID(address _account) external view returns (uint256);
    function rankToDiscount(uint256 _rank) external view returns (uint256, uint256);
    function pidDetail(address _account) external view returns (PIDData.PIDDetailed memory);
    function exist(address _account) external view returns (bool);
    function tradeVol(address _account, uint256 _day) external view returns (uint256);
    function swapVol(address _account, uint256 _day) external view returns (uint256);
    function totalTradeVol(uint256 _day) external view returns (uint256);
    function totalSwapVol(uint256 _day) external view returns (uint256);
}


