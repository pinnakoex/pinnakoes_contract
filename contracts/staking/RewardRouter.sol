// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardRouter.sol";
import "../oracle/interfaces/IVaultPriceFeed.sol";
import "../core/interfaces/IVault.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../utils/EnumerableValues.sol";
import "../DID/interfaces/IPID.sol";
import "../staking/interfaces/IInstStaking.sol";
import "../fee/interfaces/IUserFeeResv.sol";

contract RewardRouter is ReentrancyGuard, Ownable, IRewardRouter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;


    // address public weth;
    address public weth;
    address public pid;
    address public feeRouter;
    address public rewardToken;
    address public userFeeResv;
    // address[] public allWhitelistedToken;
    // mapping (address => bool) public whitelistedToken;

    // address[] public allWhitelistedPLPn;
    // uint256 public whitelistedPLPnCount;
    // mapping (address => bool) public whitelistedPLPn;
    EnumerableSet.AddressSet allWhitelistedPLPn;
    address[] public whitelistedPLPn;
    // mapping (address => bool) public whitelistedSPLPn;
    // mapping (address => address) public correspondingSPLPn;
    // mapping (address => address) public SPLPn_correspondingPLPn;

    mapping (address => address) public stakedPLPnTracker;
    mapping (address => address) public stakedPLPnVault;


    event StakePlp(address account, uint256 amount);
    event UnstakePlp(address account, uint256 amount);

    //===
    event UserStakePlp(address account, uint256 amount);
    event UserUnstakePlp(address account, uint256 amount);

    event Claim(address receiver, uint256 amount);

    event ClaimPIDFee(address _account, uint256 claimAmount);


    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }
    
    function initialize(address _rewardToken,  address _weth, address _pid, address _feeRouter, address _userFeeResv) external onlyOwner {
        rewardToken = _rewardToken;
        weth = _weth;
        pid = _pid;
        feeRouter = _feeRouter;
        userFeeResv = _userFeeResv;
    }
    

    function setPLPn(address _plp_n, address _stakedPLPnVault, address _stakedPlpTracker) external onlyOwner {
        if (!allWhitelistedPLPn.contains(_plp_n)) {
            // whitelistedPLPnCount = whitelistedPLPnCount.add(1);
            allWhitelistedPLPn.add(_plp_n);
        }
        //ATTENTION! set this contract as selp-n minter before initialize.
        //ATTENTION! set elpn reawardTracker as pnk minter before initialize.
        stakedPLPnTracker[_plp_n] = _stakedPlpTracker;
        stakedPLPnVault[_plp_n] = _stakedPLPnVault;   
        whitelistedPLPn = allWhitelistedPLPn.valuesAt(0, allWhitelistedPLPn.length());
    }

    function clearPLPn(address _plp_n) external onlyOwner {
        require(allWhitelistedPLPn.contains(_plp_n), "not included");
        allWhitelistedPLPn.remove(_plp_n);
        delete stakedPLPnTracker[_plp_n];
        whitelistedPLPn = allWhitelistedPLPn.valuesAt(0, allWhitelistedPLPn.length());
    }

    function withdrawToken(address _token, address _account, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    //===============================================================================================================

    
    //PLPn staking part --------------------------------------------------------------------------------------------- 
    function stakedPlpnAmount() external view returns (address[] memory, uint256[] memory, uint256[] memory) {
        uint256 poolLength = whitelistedPLPn.length;
        uint256[] memory _stakedAmount = new uint256[](poolLength);
        address[] memory _stakedPLPn = new address[](poolLength);
        uint256[] memory _poolRewardRate = new uint256[](poolLength);
        for (uint80 i = 0; i < poolLength; i++) {
            _stakedPLPn[i] = whitelistedPLPn[i];
            _stakedAmount[i] = IRewardTracker(stakedPLPnTracker[whitelistedPLPn[i]]).poolStakedAmount();
            _poolRewardRate[i] = IRewardTracker(stakedPLPnTracker[whitelistedPLPn[i]]).poolTokenRewardPerInterval();
        }
        return (_stakedPLPn, _stakedAmount, _poolRewardRate);
    }
    
    function stakePlpn(address _plp_n, uint256 _plpAmount) external nonReentrant override returns (uint256) {
        require(_plpAmount > 0, "RewardRouter: invalid _amount");
        require(allWhitelistedPLPn.contains(_plp_n), "RewardTracker: invalid stake PLP Token"); 
        address account = msg.sender;
        IRewardTracker(stakedPLPnTracker[_plp_n]).stakeForAccount(account, account, _plp_n, _plpAmount);
        emit UserStakePlp(account, _plpAmount);
        return _plpAmount;
    }
    
    function unstakePlpn(address _plp_n, uint256 _tokenInAmount) external nonReentrant override returns (uint256) {
        address account = msg.sender;
        require(_tokenInAmount > 0, "RewardRouter: invalid _plpAmount");
        require(allWhitelistedPLPn.contains(_plp_n), "RewardTracker: invalid stake Token"); 
        IRewardTracker(stakedPLPnTracker[_plp_n]).unstakeForAccount(account, _plp_n, _tokenInAmount, account);
        emit UserUnstakePlp(account, _tokenInAmount);
        return _tokenInAmount;
    }

    function claimPlpnStakingRewardForAccount(address _account) external nonReentrant returns (uint256) {
        address account =_account == address(0) ? msg.sender : _account;
        return _claimPlp(account);
    }
    function claimPlpnStakingReward() external nonReentrant returns (uint256) {
        address account = msg.sender;
        return _claimPlp(account);
    }
    function _claimPlp(address _account) private returns (uint256) {
        // uint256 this_reward  = IRewardTracker(stakedPLPnTracker[_tokenIn]).claimForAccount(account, account);   
        uint256 totalClaimReward = 0;
        for (uint80 i = 0; i < whitelistedPLPn.length; i++) {
            uint256 this_reward  = IRewardTracker(stakedPLPnTracker[whitelistedPLPn[i]]).claimForAccount(_account, _account);
            totalClaimReward = totalClaimReward.add(this_reward);
        }
        return totalClaimReward;
    }
    function claimablePlpList(address _account) external view returns (address[] memory, uint256[] memory) {
        uint256 poolLength = whitelistedPLPn.length;
        address[] memory _stakedPLPn = new address[](poolLength);
        uint256[] memory _rewardList = new uint256[](poolLength);
        address account =_account == address(0) ? msg.sender : _account;
        for (uint80 i = 0; i < whitelistedPLPn.length; i++) {
            _rewardList[i] = IRewardTracker(stakedPLPnTracker[whitelistedPLPn[i]]).claimable(account);
            _stakedPLPn[i] = whitelistedPLPn[i];
        }
        return (_stakedPLPn, _rewardList);
    }
    function claimablePlp(address _account) external view returns (uint256) {
        address account = _account == address(0) ? msg.sender : _account;
        uint256 rewardAcum = 0;
        for (uint80 i = 0; i < whitelistedPLPn.length; i++) {
            rewardAcum = rewardAcum.add(IRewardTracker(stakedPLPnTracker[whitelistedPLPn[i]]).claimable(account));
        }
        return rewardAcum;
    }
    //End of PLPn staking part --------------------------------------------------------------------------------------------- 




    //Trading Fee Reward for PLP holders --------------------------------------------------------------------------------------------- 
    function claimablePlpFee(address _plp, address _account) public nonReentrant returns (address[] memory, uint256[] memory) {
        address account =_account == address(0) ? msg.sender : _account;
        return IInstStaking(_plp).claimable(account);
    }
    function claimPlpFeeForAccount(address _account) public nonReentrant {
        address account =_account == address(0) ? msg.sender : _account;
        _claimPlpFee(account);
    }
    function claimPlpFee() public nonReentrant {
        address account = msg.sender;
        _claimPlpFee(account);
    }
    function _claimPlpFee(address _account) private {
        address account = _account == address(0) ? msg.sender : _account;
        for (uint80 i = 0; i < whitelistedPLPn.length; i++) {
            IInstStaking(whitelistedPLPn[i]).claimForAccount(account); //todo: convert list to usd.
        }
    }
    //End of Trading Fee Reward for PLP holders --------------------------------------------------------------------------------------------- 


    //Rebate & Discount Fee Reward for PID --------------------------------------------------------------------------------------------- 
    function claimablePIDFee(address _account) external view returns (address[] memory, uint256[] memory)  {
        return IUserFeeResv(userFeeResv).claimable(_account);
    }
    function claimPIDFee() public {
        //todo: from fee router
        IUserFeeResv(userFeeResv).claim(msg.sender);
    }
    //End of Rebate&Discount Fee Reward for PID --------------------------------------------------------------------------------------------- 



    //------ Fee Part 
    function getPLPnList() external view returns (address[] memory){
        return allWhitelistedPLPn.valuesAt(0, allWhitelistedPLPn.length());
    }

}
