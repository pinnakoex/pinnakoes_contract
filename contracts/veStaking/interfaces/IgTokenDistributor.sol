// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IgTokenDistributor {
    function checkpointOtherUser(address _addr) external;

    function getYieldUser(address _addr) external returns (uint256 yield0);
}