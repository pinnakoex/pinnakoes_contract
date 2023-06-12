// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../utils/EnumerableValues.sol";
import "./VaultMSData.sol";
import "./interfaces/IVault.sol";
import "./interfaces/ILpManager.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../DID/interfaces/IPID.sol";


pragma solidity ^0.8.0;

contract LpManager is ReentrancyGuard, Ownable, ILpManager {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;

    address public override weth;
    address public override pid;

    EnumerableSet.AddressSet lpVaults;
    mapping(address => address) public override plpToken;
    mapping(address => address) public override plpManager;
    mapping(address => address) public override stakingTracker;

    constructor(address _weth) {
        weth = _weth;
    }

    receive() external payable {
        require(msg.sender == weth, "invalid sender");
    }
    
    function withdrawToken(address _account, address _token, uint256 _amount) external onlyOwner{
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function setLP(address _vault, address _lptoken,  address _plpManager, address _plpStakingTracker) external onlyOwner {
        if (!lpVaults.contains(_vault)) {
            lpVaults.add(_vault);
        }   
        plpToken[_vault] = _lptoken;
        stakingTracker[_vault] = _plpStakingTracker;
        plpManager[_vault] = _plpManager;
    }

    function delLP(address _vault) external onlyOwner {
        if (lpVaults.contains(_vault)) {
            lpVaults.remove(_vault);
        }   
        plpToken[_vault] = address(0);
        stakingTracker[_vault] = address(0);
        plpManager[_vault] = address(0);
    }

    function getLpVaultsList() external view override returns (address[] memory){
        return lpVaults.valuesAt(0, lpVaults.length());
    }

    function isLpVault(address _vault) public view override returns(bool){
        return lpVaults.contains(_vault);
    }
}

