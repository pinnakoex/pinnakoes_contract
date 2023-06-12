// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFeeRouter {
    function claimableFeeReserves( )  external view returns (uint256);
    function claimFeeToken(address _token) external returns (uint256);
    function claimFeeReserves( ) external returns (uint256) ;

    function feeReservesRecord(uint256 _day) external view returns (uint256);
    function claimPLPReward() external returns (uint256);
}