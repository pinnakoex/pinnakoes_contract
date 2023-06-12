// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/Pausable.sol"; 

interface ITOKEN {
    function burn(uint256 _amounts) external;
    function burnV2(address _account, uint256 _amounts) external;
}
interface IPID {
    function updateScoreForAccount(address _account, address /*_vault*/, uint256 _amount, uint256 _reasonCode) external;
}

contract BurnToScore is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    address public pid;
    address public token;
    uint256 public rCode;
    uint256 public constant amountToScoreUSD = 10 ** 15;
    
    event Burn(address account, uint256 amount, uint256 rCode);
 
    function set(address _pid, address _token, uint256 _rCode) external onlyOwner{
        pid = _pid;
        token = _token;
        rCode = _rCode;
    }

    function burnToken(uint256 _amount) external nonReentrant whenNotPaused{
        require(_amount > 0);
        IERC20(token).safeTransferFrom(_msgSender(), address(this), _amount);
        ITOKEN(token).burn(_amount);
        IPID(pid).updateScoreForAccount(msg.sender, address(this), _amount.mul(amountToScoreUSD), rCode);
        emit Burn(msg.sender, _amount, rCode);
    }

    function burnTokenV2(uint256 _amount) external nonReentrant whenNotPaused{
        require(_amount > 0);
        IERC20(token).safeTransferFrom(_msgSender(), address(this), _amount);
        ITOKEN(token).burnV2(address(this), _amount);
        IPID(pid).updateScoreForAccount(msg.sender, address(this), _amount.mul(amountToScoreUSD), rCode);
        emit Burn(msg.sender, _amount, rCode);
    }
}

