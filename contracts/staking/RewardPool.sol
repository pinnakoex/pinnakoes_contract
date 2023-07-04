// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IRewardTracker.sol";
import "../DID/interfaces/IPID.sol";
import "../DID/PIDData.sol";

contract RewardPool is
    ReentrancyGuard,
    IRewardTracker,
    Ownable //IERC20,
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    uint256 public constant REWARD_PRECISION = 10 ** 20;

    uint256 public lastDistributionTime;
    uint256 public override poolTokenRewardPerInterval;
    uint256 public cumulativeRewardPerToken;
    struct UserInfo {
        uint256 stakeTime;
        uint256 amount;
        uint256 rank;
        uint256 totalAmount;
        uint256 boost;
    }

    mapping(address => uint256) public override stakedAmounts;
    mapping(address => uint256) public claimableReward;
    mapping(address => uint256) public previousCumulatedRewardPerToken;
    mapping(address => uint256) public override cumulativeRewards;
    mapping(address => uint256) public override averageStakedAmounts;
    mapping(address => UserInfo) public userInfo;
    mapping(uint256 => uint256) public rankIntegral; // 1 = 1* 100
    mapping(address => uint256) public rebatedQuota;

    address public pid;

    // uint256[] public rewardPerSec;
    // uint256[] public rewardPerSecUpdateTime;
    uint256 public maxPeriod = 7 days;
    address public depositToken;
    address public rewardToken;

    uint256 public totalDepositSupply;
    uint256 public totalShareSupply;
    mapping(address => mapping(address => uint256)) public allowances;

    bool public inPrivateStakingMode;
    bool public inPrivateClaimingMode;
    mapping(address => bool) public isHandler;

    event Claim(address receiver, uint256 amount);
    event AddRebateQuota(
        address account,
        address rebateAccount,
        uint256 claimedAmount,
        uint256 rebateQuota
    );

    function initialize(
        address _depositToken,
        address _rewardToken,
        uint256 _poolRewardPerInterval,
        address _pid
    ) external onlyOwner {
        depositToken = _depositToken;
        rewardToken = _rewardToken;
        poolTokenRewardPerInterval = _poolRewardPerInterval;
        pid = _pid;
        rankIntegral[0] = 100;
        rankIntegral[1] = 100;
        rankIntegral[2] = 120;
        rankIntegral[3] = 140;
        rankIntegral[4] = 160;
        rankIntegral[5] = 180;
        rankIntegral[6] = 200;
        rankIntegral[7] = 230;
        rankIntegral[8] = 260;
        rankIntegral[9] = 300;

        _updateRewards(address(0));
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }

    function setMaxPeriod(uint256 _maxPeriod) external onlyOwner {
        maxPeriod = _maxPeriod;
    }

    function setRankIntegral(
        uint256 _rank,
        uint256 _integral
    ) external onlyOwner {
        rankIntegral[_rank] = _integral;
    }

    function poolStakedAmount() external view returns (uint256) {
        return totalDepositSupply;
    }

    function updatePoolRewardRate(
        uint256 _poolRewardPerInterval
    ) external nonReentrant {
        _validateHandler();
        poolTokenRewardPerInterval = _poolRewardPerInterval;
        _updateRewards(address(0));
    }

    function setInPrivateStakingMode(
        bool _inPrivateStakingMode
    ) external onlyOwner {
        inPrivateStakingMode = _inPrivateStakingMode;
    }

    function setInPrivateClaimingMode(
        bool _inPrivateClaimingMode
    ) external onlyOwner {
        inPrivateClaimingMode = _inPrivateClaimingMode;
    }

    // // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function balanceOf(
        address _account
    ) external view override returns (uint256) {
        return stakedAmounts[_account];
    }

    function stake(
        address _depositToken,
        uint256 _amount
    ) external override nonReentrant {
        if (inPrivateStakingMode) {
            revert("RewardTracker: action not enabled");
        }
        require(_depositToken == depositToken, "Invalid deposit token");
        _stake(msg.sender, msg.sender, _depositToken, _amount);
    }

    function stakeForAccount(
        address _fundingAccount,
        address _account,
        address _depositToken,
        uint256 _amount
    ) external override nonReentrant {
        _validateHandler();
        require(_depositToken == depositToken, "Invalid deposit token");
        _stake(_fundingAccount, _account, _depositToken, _amount);
    }

    function unstake(
        address _depositToken,
        uint256 _amount
    ) external override nonReentrant {
        if (inPrivateStakingMode) {
            revert("RewardTracker: action not enabled");
        }
        require(_depositToken == depositToken, "Invalid deposit token");
        _claim(msg.sender, msg.sender);
        _unstake(msg.sender, _depositToken, _amount, msg.sender);
    }

    function unstakeForAccount(
        address _account,
        address _depositToken,
        uint256 _amount,
        address _receiver
    ) external override nonReentrant {
        _validateHandler();
        require(_depositToken == depositToken, "Invalid deposit token");
        _unstake(_account, _depositToken, _amount, _receiver);
    }

    function updateRewardsForUser(
        address _account
    ) external override nonReentrant {
        _updateRewards(_account);
        _updateUserInfo(_account);
    }

    function updateUserInfo(address _account) external nonReentrant {
        _updateUserInfo(_account);
    }

    function claim(
        address _receiver
    ) external override nonReentrant returns (uint256) {
        if (inPrivateClaimingMode) {
            revert("RewardTracker: action not enabled");
        }
        return _claim(msg.sender, _receiver);
    }

    function claimForAccount(
        address _account,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _claim(_account, _receiver);
    }

    function claimable(
        address _account
    ) external view override returns (uint256) {
        uint256 stakedAmount = stakedAmounts[_account];
        uint256 supply = totalShareSupply;
        if (supply < 1) {
            return 0;
        }
        uint256 pendingRewards = _pendingRewards().mul(REWARD_PRECISION);
        uint256 nextCumulativeRewardPerToken = cumulativeRewardPerToken.add(
            pendingRewards.div(supply)
        );
        uint256 accountReward = stakedAmount
            .mul(
                nextCumulativeRewardPerToken.sub(
                    previousCumulatedRewardPerToken[_account]
                )
            )
            .div(REWARD_PRECISION);
        // return claimableReward[_account].add(
        // stakedAmount.mul(nextCumulativeRewardPerToken.sub(previousCumulatedRewardPerToken[_account])).div(REWARD_PRECISION));
        return claimableReward[_account].add(accountReward);
    }

    function _claim(
        address _account,
        address _receiver
    ) private returns (uint256) {
        _updateRewards(_account);
        _updateUserInfo(_account);

        uint256 tokenAmount = claimableReward[_account];
        claimableReward[_account] = 0;

        (, uint256 _rebateQuota, address _rebateAccount) = IPID(pid).getFeeDet(
            _account,
            tokenAmount
        );
        if (_rebateAccount != address(0)) {
            rebatedQuota[_rebateAccount] = rebatedQuota[_rebateAccount].add(
                _rebateQuota
            );
            emit AddRebateQuota(
                _account,
                _rebateAccount,
                tokenAmount,
                _rebateQuota
            );
        }

        if (tokenAmount > 0) {
            IERC20(rewardToken).safeTransfer(_receiver, tokenAmount);
            emit Claim(_account, tokenAmount);
        }

        return tokenAmount;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "RewardTracker: forbidden");
    }

    function _stake(
        address _fundingAccount,
        address _account,
        address _depositToken,
        uint256 _amount
    ) private {
        require(_amount > 0, "RewardTracker: invalid _amount");
        require(_depositToken == depositToken, "Invalid deposit token");
        _updateRewards(_account);
        _updateUserInfo(_account);
        UserInfo storage user = userInfo[_account];
        uint256 intergral = rankIntegral[user.rank];
        user.totalAmount = user.totalAmount.add(
            _amount.mul(intergral).div(100)
        );
        user.amount = user.amount.add(_amount);

        IERC20(_depositToken).safeTransferFrom(
            _fundingAccount,
            address(this),
            _amount
        );

        if (user.stakeTime == 0) {
            user.stakeTime = block.timestamp;
        }

        stakedAmounts[_account] = stakedAmounts[_account].add(_amount);
        // depositBalances[_account][_depositToken] = depositBalances[_account][_depositToken].add(_amount);
        totalShareSupply = totalShareSupply.add(user.totalAmount);
        totalDepositSupply = totalDepositSupply.add(_amount);
    }

    function _unstake(
        address _account,
        address _depositToken,
        uint256 _amount,
        address _receiver
    ) private {
        require(_amount > 0, "RewardTracker: invalid _amount");
        require(_depositToken == depositToken, "Invalid deposit token");
        require(
            stakedAmounts[_account] >= _amount,
            "RewardTracker: _amount exceeds stakedAmount"
        );

        _updateRewards(_account);
        _updateUserInfo(_account);

        UserInfo storage user = userInfo[_account];
        uint256 intergral = rankIntegral[user.rank];

        uint256 stakedAmount = stakedAmounts[_account];
        stakedAmounts[_account] = stakedAmount.sub(_amount);

        user.amount = user.amount.sub(_amount);
        uint256 oldNumber = user.totalAmount;
        uint256 newNumber = user.amount.mul(intergral).div(100);
        user.totalAmount = newNumber;
        totalShareSupply = totalShareSupply.sub(oldNumber);
        totalShareSupply = totalShareSupply.add(newNumber);
        totalDepositSupply = totalDepositSupply.sub(_amount);
        IERC20(_depositToken).safeTransfer(_receiver, _amount);
    }

    function _pendingRewards() private view returns (uint256) {
        if (block.timestamp == lastDistributionTime) {
            return 0;
        }
        uint256 timeDiff = block.timestamp.sub(lastDistributionTime);
        return poolTokenRewardPerInterval.mul(timeDiff);
    }

    function _updateRewards(address _account) private {
        uint256 blockReward = _pendingRewards();
        lastDistributionTime = block.timestamp;
        uint256 supply = totalShareSupply;
        UserInfo storage user = userInfo[_account];

        if (supply < 1) {
            return;
        }
        uint256 _cumulativeRewardPerToken = cumulativeRewardPerToken;
        if (supply > 0 && blockReward > 0) {
            _cumulativeRewardPerToken = _cumulativeRewardPerToken.add(
                blockReward.mul(REWARD_PRECISION).div(supply)
            );
            cumulativeRewardPerToken = _cumulativeRewardPerToken;
        }

        // cumulativeRewardPerToken can only increase
        // so if cumulativeRewardPerToken is zero, it means there are no rewards yet
        if (_cumulativeRewardPerToken == 0) {
            return;
        }

        if (_account != address(0)) {
            uint256 stakedAmount = user.totalAmount;
            // uint256 stakedAmount = stakedAmounts[_account];
            uint256 accountReward = stakedAmount
                .mul(
                    _cumulativeRewardPerToken.sub(
                        previousCumulatedRewardPerToken[_account]
                    )
                )
                .div(REWARD_PRECISION);
            uint256 _claimableReward = claimableReward[_account].add(
                accountReward
            );

            claimableReward[_account] = _claimableReward;
            previousCumulatedRewardPerToken[
                _account
            ] = _cumulativeRewardPerToken;

            if (_claimableReward > 0 && stakedAmounts[_account] > 0) {
                uint256 nextCumulativeReward = cumulativeRewards[_account].add(
                    accountReward
                );

                averageStakedAmounts[_account] = averageStakedAmounts[_account]
                    .mul(cumulativeRewards[_account])
                    .div(nextCumulativeReward)
                    .add(
                        stakedAmount.mul(accountReward).div(
                            nextCumulativeReward
                        )
                    );

                cumulativeRewards[_account] = nextCumulativeReward;
            }
        }
    }

    function _updateUserInfo(address _account) private {
        UserInfo storage user = userInfo[_account];

        uint256 rank = IPID(pid).rank(_account);
        (address[] memory _par, ) = IPID(pid).getReferralForAccount(_account);
        uint256 refRank = IPID(pid).rank(_par[0]);

        if (block.timestamp < user.stakeTime.add(maxPeriod)) {
            user.rank = refRank > rank ? refRank : rank;
        } else {
            user.rank = rank;
        }
        uint256 oldTotal = user.totalAmount;
        uint256 intergral = rankIntegral[user.rank];
        if (intergral == 0) {
            intergral = 100;
        }
        user.boost = intergral;
        user.totalAmount = user.amount.mul(intergral).div(100);
        totalShareSupply = totalShareSupply.sub(oldTotal);
        totalShareSupply = totalShareSupply.add(user.totalAmount);
    }

    function emergencyExit() external nonReentrant {
        if (inPrivateStakingMode) {
            revert("RewardTracker: action not enabled");
        }
        address _account = msg.sender;
        uint256 stakedAmount = stakedAmounts[_account];
        if (stakedAmount > 0) {
            stakedAmounts[_account] = 0;
            IERC20(depositToken).safeTransfer(_account, stakedAmount);
            totalDepositSupply = totalDepositSupply.sub(stakedAmount);
        }
    }
}
