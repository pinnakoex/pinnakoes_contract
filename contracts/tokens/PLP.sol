// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol"; 
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPLP.sol";
import "./interfaces/IMintable.sol";
import "../staking/interfaces/IRewardTracker.sol";
import "../staking/InstStaking.sol";

contract PLP is IERC20, IPLP, InstStaking {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public override totalSupply;
    uint256 public nonStakingSupply;

    // address public EUSDDistributor;
    mapping (address => bool) public isMinter;
   
    mapping (address => uint256) public balances;
    mapping (address => mapping (address => uint256)) public allowances;
    mapping (address => bool) public isHandler;

    address public plpStakingTracker;


    //----- end of EDIST
    constructor(string memory _name, string memory _symbol) InstStaking(address(this)){
        name = _name;
        symbol = _symbol;
    }


    modifier onlyMinter() {
        require(isMinter[msg.sender], "forbidden");
        _;
    }
    
    function setStakingTracker(address _plpStakingTracker) external onlyOwner {
        plpStakingTracker = _plpStakingTracker;
    }

    function setMinter(address _minter, bool _isActive) external onlyOwner {
        isMinter[_minter] = _isActive;
    }

    function mint(address _account, uint256 _amount) external onlyMinter {
        _mint(_account, _amount);
    }



    function burn(uint256 _amount) external  {
        // _updateRewardsLight(msg.sender);
        _burn(msg.sender, _amount);
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }

    function balanceOf(address _account) external view override returns (uint256) {
        return balances[_account];
    }

    function transfer(address _recipient, uint256 _amount) external override returns (bool) {
        require(msg.sender!= _recipient, "Self transfer is not allowed");
        // _updateRewards(msg.sender);
        // _updateRewards(_recipient);
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }
    
    function allowance(address _owner, address _spender) external view override returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external override returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external override returns (bool) {
        // _updateRewards(_sender);
        // _updateRewards(_recipient);
        updateRewards(msg.sender);    
        updateRewards(_sender);    
        if (isHandler[msg.sender]) {
            _transfer(_sender, _recipient, _amount);
            return true;
        }
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(_amount, "PLP: transfer amount exceeds allowance");
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "PLP: mint to the zero address");
        updateRewards(_account);    
        totalSupply = totalSupply.add(_amount);
        balances[_account] = balances[_account].add(_amount);
        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "PLP: burn from the zero address");
        updateRewards(_account);    
        balances[_account] = balances[_account].sub(_amount, "PLP: burn amount exceeds balance");
        totalSupply = totalSupply.sub(_amount);

        emit Transfer(_account, address(0), _amount);
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) internal {
        require(_sender != address(0), "PLP: transfer from the zero address");
        require(_recipient != address(0), "PLP: transfer to the zero address");
        updateRewards(_sender);    
        updateRewards(_recipient);    
        balances[_sender] = balances[_sender].sub(_amount, "PLP: transfer amount exceeds balance");
        balances[_recipient] = balances[_recipient].add(_amount);

        emit Transfer(_sender, _recipient,_amount);
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "PLP: approve from the zero address");
        require(_spender != address(0), "PLP: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    //rewrite part of inst satking
    function userDeposit(address _account) public view override returns (uint256) {
        return balances[_account].add(plpStakingTracker == address(0) ? 0 : IRewardTracker(plpStakingTracker).balanceOf(_account));
    }
    function totalDeposit() public view override returns (uint256) {
        return totalSupply;
    }
    function stake(uint256 _amount) public virtual override {
        revert("not supported function");
    }   
    function unstake(uint256 _amount) public virtual override returns (address[] memory, uint256[] memory ) {
        revert("not supported function");
    }
}
