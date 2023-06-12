// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IgToken_call {
    function create_lock(address _addr, uint256 _value, uint256 _unlock_time) external;

    function increase_amount(address _addr, uint256 _value) external;

    function increase_unlock_time(address _addr, uint256 _unlock_time) external;

    function checkpoint() external;

}