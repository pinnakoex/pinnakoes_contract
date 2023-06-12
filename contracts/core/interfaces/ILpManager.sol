// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILpManager {
    function isLpVault(address _vault) external view returns(bool);
    function getLpVaultsList() external view returns (address[] memory);
    function weth() external view returns (address);
    function pid() external view returns (address);
    function plpToken(address _vault) external view returns (address);
    function plpManager(address _vault) external view returns (address);
    function stakingTracker(address _vault) external view returns (address);

}