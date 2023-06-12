// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IInstStaking {
    function claimForAccount(address _account) external  returns (address[] memory, uint256[] memory);
    function claimable(address _account) external view  returns (address[] memory, uint256[] memory);
}
