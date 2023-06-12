// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


interface ITOKEN {
    function burn(uint256 _amounts) external;
}

contract PNKStaking is  ReentrancyGuard, Ownable { //IERC20,
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // reward parameters
    uint256 public constant REWARD_PRECISION = 10 ** 20;
    uint256 public totalRewardPerDay;
    uint256 public poolRewardPerSec_PREC; // = totalRewardPerDay * REWARD_PRECISION / (24day seconds)
    uint256 public poolTokenRewardPerSec_PREC;

    // reward record
    uint256 public cumulativeRewardPerToken;
    uint256 public lastDistributionTime;
    uint256 public totalDepositSupply;
    address public depositToken;
    address public rewardToken;

    uint256 public cumulativeReward;

    // fee
    uint256 public feeRatio = 50;
    uint256 public constant FEE_PRECISION = 10000;

    mapping (address => uint256) public stakedAmounts;
    mapping (address => uint256) public claimableReward;
    mapping (address => uint256) public entryCumulatedRewardPerToken;


    event Claim(address account, uint256 amount, address _receiver);
    event Stake(address account, uint256 amount, uint256 latestAmount);
    event Unstake(address account, uint256 amount, uint256 latestAmount);
    event UpdateRate(uint256 rate, uint256 totalSupply);

    function initialize(address _depositToken, address _rewardToken) external onlyOwner {
        depositToken = _depositToken;
        rewardToken = _rewardToken;
    }  

    function updatePoolRewardRate(uint256 _totalRewardPerDay) external onlyOwner {
        _updateRewards(address(0));
        totalRewardPerDay = _totalRewardPerDay;
        poolRewardPerSec_PREC = totalRewardPerDay.mul(REWARD_PRECISION).div(24*60*60);
    }

    function withdrawToken(address _token, address _account, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }
    
    function setFeeRatio(uint256 _ratio) external onlyOwner{
        feeRatio = _ratio;
    }

    //--- Func. for user
    function stake(uint256 _amount) external nonReentrant {
        _stake(msg.sender, msg.sender, depositToken, _amount);
    }

    function unstake(uint256 _amount) external nonReentrant {
        _unstake(msg.sender, depositToken, _amount, msg.sender);
    }

    function claim(address _receiver) external nonReentrant returns (uint256) {
        return _claim(msg.sender, _receiver);
    }

    function updateRewardsForUser(address _account) external nonReentrant {
        _updateRewards(_account);
    }

    function claimable(address _account) external view returns (uint256) {
        // latest cum reward
        uint256 latest_cumulativeRewardPerToken = cumulativeRewardPerToken.add(_pendingRewards());

        uint256 accountReward = stakedAmounts[_account].mul(latest_cumulativeRewardPerToken.sub(entryCumulatedRewardPerToken[_account])).div(REWARD_PRECISION);
        return claimableReward[_account].add(accountReward);
    }

    function totalReward() external view returns (uint256) {
        return cumulativeReward.add(_pendingRewards().mul(totalDepositSupply).div(REWARD_PRECISION));
    }


    // internal func.
    function _pendingRewards() private view returns (uint256) {
        uint256 timeDiff = block.timestamp.sub(lastDistributionTime);
        return timeDiff > 0 ? poolTokenRewardPerSec_PREC.mul(timeDiff) : 0;
    }

    function _updateRewards(address _account) private {
        uint256 blockReward = _pendingRewards();
        cumulativeReward = cumulativeReward.add(blockReward.mul(totalDepositSupply).div(REWARD_PRECISION));
        lastDistributionTime = block.timestamp;

        cumulativeRewardPerToken = cumulativeRewardPerToken.add(blockReward);

        if (_account != address(0)) {
            uint256 accountReward = stakedAmounts[_account].mul(cumulativeRewardPerToken.sub(entryCumulatedRewardPerToken[_account])).div(REWARD_PRECISION);
            claimableReward[_account] = claimableReward[_account].add(accountReward);
            entryCumulatedRewardPerToken[_account] = cumulativeRewardPerToken;
        }
    }


    function _claim(address _account, address _receiver) private returns (uint256) {
        _updateRewards(_account);

        uint256 tokenAmount = claimableReward[_account];
        claimableReward[_account] = 0;

        if (tokenAmount > 0) {
            IERC20(rewardToken).safeTransfer(_receiver, tokenAmount);
            emit Claim(_account, tokenAmount, _receiver);
        }
        return tokenAmount;
    }


    function _updateBalanceAndRate(uint256 _amount, bool _isIncrease) private {
        if (_isIncrease)
            totalDepositSupply = totalDepositSupply.add(_amount);
        else{
            require(totalDepositSupply >= _amount, "balance is smaller than decrease");
            totalDepositSupply = totalDepositSupply.sub(_amount);
        }

        // Update Rate
        poolTokenRewardPerSec_PREC = totalDepositSupply > 0 ? poolRewardPerSec_PREC.div(totalDepositSupply) : 0;
        emit UpdateRate(poolTokenRewardPerSec_PREC, totalDepositSupply);

    }

    function _stake(address _fundingAccount, address _account, address _depositToken, uint256 _amount) private {
        require(_amount > 0, "RewardTracker: invalid _amount");
        require(_depositToken == depositToken, "Invalid deposit token");

        IERC20(_depositToken).safeTransferFrom(_fundingAccount, address(this), _amount);
        uint256 fee = _amount.mul(feeRatio).div(FEE_PRECISION);
        ITOKEN(depositToken).burn(fee);
        uint256 _amountAfterFee = _amount.sub(fee);
        _updateRewards(_account);
        stakedAmounts[_account] = stakedAmounts[_account].add(_amountAfterFee);
        emit Stake(_account, _amountAfterFee, stakedAmounts[_account]);

        _updateBalanceAndRate(_amount, true);
    }

    function _unstake(address _account, address _depositToken, uint256 _amount, address _receiver) private {
        require(_amount > 0, "RewardTracker: invalid _amount");
        require(_depositToken == depositToken, "Invalid deposit token");
        require(stakedAmounts[_account] >= _amount, "RewardTracker: _amount exceeds stakedAmount");

        _updateRewards(_account);
        stakedAmounts[_account] = stakedAmounts[_account].sub(_amount);
        _updateBalanceAndRate(_amount, false);
        emit Unstake(_account, _amount, stakedAmounts[_account]);

        IERC20(_depositToken).safeTransfer(_receiver, _amount);
    }


    // Func. for public view
    function balanceOf(address _account) external view returns (uint256) {
        return stakedAmounts[_account];
    }

}
