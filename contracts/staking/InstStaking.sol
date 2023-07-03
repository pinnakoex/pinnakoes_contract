// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../utils/EnumerableValues.sol";
import "./interfaces/IInstStaking.sol";
interface IFeeRouter {
    function distribute() external;
}

contract InstStaking is Ownable, IInstStaking{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct RewardInfo {
        address token;
        uint256 balance;
        uint256 cumulatedRewardPerToken_PREC;
    }
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;

    mapping (address => RewardInfo) rewardInfo;

    address public feeRouter;
    address public depositToken;
    address[] public rewardTokens;

    uint256 public totalDepositBalance;
    uint256 public constant REWARD_PRECISION = 10 ** 20;
   
    //record for accounts
    mapping(address => uint256) public userDepositBalance;
    mapping(address => mapping(address => uint256)) public entryCumulatedReward_PREC;
    mapping(address => mapping(address => uint256)) public unclaimedReward;
    mapping(address => mapping(uint256 => uint256)) public rewardRecord;

    EnumerableSet.AddressSet noCountAddress;


    constructor(address _depositToken) {
        depositToken = _depositToken;
        noCountAddress.add(address(this));
    }

    //-- public view func.
    function userDeposit(address _account) public virtual view returns (uint256) {
        return userDepositBalance[_account];
    }
    function totalDeposit() public virtual view returns (uint256) {
        return totalDepositBalance;
    }
    function _increaseDeposit(address _account, uint256 _amount) private {
        userDepositBalance[_account] = userDepositBalance[_account].add(_amount);
        totalDepositBalance = totalDepositBalance.add(_amount);
    }
    function _decreaseDeposit(address _account, uint256 _amount) private {
        userDepositBalance[_account] = userDepositBalance[_account].sub(_amount);
        totalDepositBalance = totalDepositBalance.sub(_amount);
    }

    function getRewardInfo(address _token) public view returns (RewardInfo memory){
        return rewardInfo[_token];
    }

    function getRewardTokens() public view returns (address[] memory) {
        return rewardTokens;
    }

    function pendingReward(address _token) public view returns (uint256) {
        uint256 currentBalance = IERC20(_token).balanceOf(address(this));
        return currentBalance > rewardInfo[_token].balance ? currentBalance.sub(rewardInfo[_token].balance) : 0;
    }

    function claimable(address _account) public view override returns (address[] memory, uint256[] memory){
        uint256[] memory claimable_list = new uint256[](rewardTokens.length);
        if (isNoCount(_account)){
            return (rewardTokens, claimable_list);
        }
        for(uint8 i = 0; i < rewardTokens.length; i++){
            address _tk = rewardTokens[i];
            claimable_list[i] = unclaimedReward[_account][_tk];
            if (userDeposit(_account) > 0 && totalDeposit() > 0){
                uint256 pending_reward = pendingReward(_tk);
                claimable_list[i] = claimable_list[i]
                    .add(userDeposit(_account).mul(pending_reward).div(totalDeposit()))
                    .add(userDeposit(_account).mul(rewardInfo[_tk].cumulatedRewardPerToken_PREC.sub(entryCumulatedReward_PREC[_account][_tk])).div(REWARD_PRECISION));
            }
        }
        return (rewardTokens, claimable_list);
    }

    //-- owner 
    function setRewards(address[] memory _rewardTokens) external onlyOwner {
        rewardTokens = _rewardTokens;
    }

    function setFeeRouter(address _feeRouter) external onlyOwner {
        feeRouter = _feeRouter;
    }

    function setNoCountAddress(address[] memory _addList, bool _status) external onlyOwner{
        if (_status){
            for(uint64 i = 0; i < _addList.length; i++){
                if (!noCountAddress.contains(_addList[i])){
                    noCountAddress.add(_addList[i]);
                }
            }
        }
        else{
            for(uint64 i = 0; i < _addList.length; i++){
                if (noCountAddress.contains(_addList[i])){
                    noCountAddress.remove(_addList[i]);
                }
            }
        }
    }

    function isNoCount(address _add) public view returns (bool){
        return noCountAddress.contains(_add);
    }

    function withdrawToken(address _token, address _account, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function aprRecord(address _token) public view returns (uint256, uint256) {
        uint256 total_reward = 0;
        uint256 currentBalance = IERC20(_token).balanceOf(address(this));
        if (currentBalance > rewardInfo[_token].balance) 
            total_reward = currentBalance.sub(rewardInfo[_token].balance);   
        uint256 _cur_hour =  block.timestamp.div(3600);
        for(uint i = 0; i < 24; i++){
            total_reward = total_reward.add(rewardRecord[_token][_cur_hour-i]);
        }
        return (total_reward, totalDeposit());
    }

    function _distributeReward(address _token) private {
        uint256 currentBalance = IERC20(_token).balanceOf(address(this));
        if (currentBalance <= rewardInfo[_token].balance) 
            return;

        uint256 rewardToDistribute = currentBalance.sub(rewardInfo[_token].balance);
        uint256 _hour = block.timestamp.div(3600);
        rewardRecord[_token][_hour] = rewardRecord[_token][_hour].add(rewardToDistribute);
        // calculate cumulated reward
        if (totalDeposit() > 0){
            rewardInfo[_token].cumulatedRewardPerToken_PREC = 
                rewardInfo[_token].cumulatedRewardPerToken_PREC.add(rewardToDistribute.mul(REWARD_PRECISION).div(totalDeposit()));
        }
        //update balance
        rewardInfo[_token].balance = currentBalance;
    }


    function _transferOut(address _receiver, address _token, uint256 _amount) private {
        if (_amount == 0) return;
        require(rewardInfo[_token].balance >= _amount, "[InstStaking] Insufficient token balance");
        rewardInfo[_token].balance = rewardInfo[_token].balance.sub(_amount);
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    function stake(uint256 _amount) public virtual{
        address _account = msg.sender;
        updateRewards(_account);    
        IERC20(depositToken).safeTransferFrom(_account, address(this), _amount);
        _increaseDeposit(_account,_amount);
    }   
    
    
    function unstake(uint256 _amount) public virtual returns (address[] memory, uint256[] memory ) {
        address _account = msg.sender;
        require(userDeposit(_account) >= _amount, "insufficient balance");
        uint256[] memory claim_res = _claim(_account);
        _decreaseDeposit(_account, _amount);
        IERC20(depositToken).safeTransfer(_account, _amount);
        return (rewardTokens, claim_res);
    }

    function claim() public returns (address[] memory, uint256[] memory ) {  
        return (rewardTokens, _claim(msg.sender));
    }

    function claimForAccount(address _account) public override returns (address[] memory, uint256[] memory){
        return (rewardTokens, _claim(_account));
    }

    function _claim(address _account) private returns (uint256[] memory ) {
        uint256[] memory claim_res = new uint256[](rewardTokens.length);
        if (isNoCount(_account)){
            return claim_res;
        }      
        updateRewards(_account);    
        for(uint8 i = 0; i < rewardTokens.length; i++){
            _transferOut(_account,rewardTokens[i], unclaimedReward[_account][rewardTokens[i]]);
            claim_res[i] = unclaimedReward[_account][rewardTokens[i]] ;
            unclaimedReward[_account][rewardTokens[i]] = 0;
        }
        return claim_res;
    }

    function updateRewards(address _account) public {
        if (feeRouter != address(0))
            IFeeRouter(feeRouter).distribute();
        for(uint8 i = 0; i < rewardTokens.length; i++){
            _distributeReward(rewardTokens[i]);
        }
        if (_account != address(0) && _account != address(this)){
            if (userDeposit(_account) > 0){
                for(uint8 i = 0; i < rewardTokens.length; i++){
                    unclaimedReward[_account][rewardTokens[i]] = unclaimedReward[_account][rewardTokens[i]].add(
                        userDeposit(_account).mul(rewardInfo[rewardTokens[i]].cumulatedRewardPerToken_PREC.sub(entryCumulatedReward_PREC[_account][rewardTokens[i]])).div(REWARD_PRECISION)
                        );
                }
            }
            
            for(uint8 i = 0; i < rewardTokens.length; i++){
                entryCumulatedReward_PREC[_account][rewardTokens[i]] = rewardInfo[rewardTokens[i]].cumulatedRewardPerToken_PREC;
            }
        }
    }
}
