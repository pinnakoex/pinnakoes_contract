// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IRewardRouter.sol";
import "./interfaces/IgToken.sol";
import "./utils/Owned.sol";
import "./utils/TransferHelper.sol";


contract gTokenYieldDistributor is Owned, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    /* ========== STATE VARIABLES ========== */

    // Instances
    IgToken public gToken;
    IRewardRouter public rewardRouter;
    ERC20 public emittedToken;

    // Addresses
    address public emitted_token_address;

    // Admin addresses
    address public timelock_address;

    // Constant for price precision
    uint256 private constant PRICE_PRECISION = 1e6;

    // Yield and period related
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public yieldRate;
    uint256 public yieldDuration = 7 * 24 * 3600; // uint:seconds
    mapping(address => bool) public reward_notifiers;

    uint256 public scaleBalance;
    uint256 public denominator;
    uint256 public weekReward;
    uint256 public _rewardAmount;
    uint256 public yieldAmount;

    bool public isFixedReward = true;

    bool public isWithdrawRewardRouter = false;


    // Yield tracking
    uint256 public yieldPergTokenStored = 0;
    mapping(address => uint256) public userYieldPerTokenPaid;
    mapping(address => uint256) public yields;

    // gToken tracking
    uint256 public totalgTokenParticipating = 0;
    uint256 public totalgTokenSupplyStored = 0;
    mapping(address => bool) public userIsInitialized;
    mapping(address => uint256) public usergTokenCheckpointed;
    mapping(address => uint256) public usergTokenEndpointCheckpointed;
    mapping(address => uint256) private lastRewardClaimTime; // staker addr -> timestamp

    // Greylists
    mapping(address => bool) public greylist;

    // Admin booleans for emergencies
    bool public yieldCollectionPaused = false; // For emergencies

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyByOwnGov() {
        require(msg.sender == owner || msg.sender == timelock_address, "Not owner or timelock");
        _;
    }

    modifier notYieldCollectionPaused() {
        require(yieldCollectionPaused == false, "Yield collection is paused");
        _;
    }

    modifier checkpointUser(address account) {
        _checkpointUser(account);
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor (
        address _owner,
        address _emittedToken,
        address _timelock_address,
        address _gToken_address,
        uint256 _weekReward,
        address _rewardRouter,
        bool _isFixedReward,
        uint256 _scaleBalance,
        uint256 _denominator
    ) Owned(_owner) {
        emitted_token_address = _emittedToken;
        emittedToken = ERC20(_emittedToken);

        gToken = IgToken(_gToken_address);
        rewardRouter = IRewardRouter(_rewardRouter);
        lastUpdateTime = block.timestamp;
        timelock_address = _timelock_address;
        weekReward = _weekReward;
        isFixedReward = _isFixedReward;
        scaleBalance = _scaleBalance;
        denominator = _denominator;

        reward_notifiers[_owner] = true;
    }

    /* ========== VIEWS ========== */

    function setRewardRouter(address _rewardRouter) external onlyByOwnGov {
        rewardRouter = IRewardRouter(_rewardRouter);
    }

    function withdrawToEDEPool() external {
        if (isWithdrawRewardRouter) {
            rewardRouter.withdrawToEDEPool();
        }
    }


    function fractionParticipating() external view returns (uint256) {
        return totalgTokenParticipating.mul(PRICE_PRECISION).div(totalgTokenSupplyStored);
    }


    function eligibleCurrentgToken(address account) public view returns (uint256 eligible_gToken_bal, uint256 stored_ending_timestamp) {
        uint256 curr_gToken_bal = gToken.balanceOf(account);

        // Stored is used to prevent abuse
        stored_ending_timestamp = usergTokenEndpointCheckpointed[account];
        eligible_gToken_bal = curr_gToken_bal;

    }

    function lastTimeYieldApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function yieldPergToken() public view returns (uint256) {
        if (totalgTokenSupplyStored == 0) {
            return yieldPergTokenStored;
        } else {
            return (
                yieldPergTokenStored.add(
                lastTimeYieldApplicable()
                .sub(lastUpdateTime)
                .mul(yieldRate)
                .mul(1e9)
                .div(totalgTokenSupplyStored)
            )
            );
        }
    }

    function earned(address account) public view returns (uint256) {
        // Uninitialized users should not earn anything yet
        if (!userIsInitialized[account]) return 0;

        (uint256 eligible_current_gToken, uint256 ending_timestamp) = eligibleCurrentgToken(account);

        // If your gToken is unlocked
        uint256 eligible_time_fraction = PRICE_PRECISION;
        if (eligible_current_gToken == 0) {
            // And you already claimed after expiration
            if (lastRewardClaimTime[account] >= ending_timestamp) {
                // You get NOTHING. You LOSE. Good DAY ser!
                return 0;
            }
            // You haven't claimed yet
            else {
                uint256 eligible_time = (ending_timestamp).sub(lastRewardClaimTime[account]);
                uint256 total_time = (block.timestamp).sub(lastRewardClaimTime[account]);
                eligible_time_fraction = PRICE_PRECISION.mul(eligible_time).div(total_time);
            }
        }

        // If the amount of gToken increased, only pay off based on the old balance
        // Otherwise, take the midpoint
        uint256 gToken_balance_to_use;
        {
            uint256 old_gToken_balance = usergTokenCheckpointed[account];
            if (eligible_current_gToken > old_gToken_balance) {
                gToken_balance_to_use = old_gToken_balance;
            }
            else {
                gToken_balance_to_use = ((eligible_current_gToken).add(old_gToken_balance)).div(2);
            }
        }

        return (
            gToken_balance_to_use
            .mul(yieldPergToken().sub(userYieldPerTokenPaid[account]))
            .mul(eligible_time_fraction)
            .div(1e9 * PRICE_PRECISION)
            .add(yields[account])
        );
    }

    function getYieldForDuration() external view returns (uint256) {
        return (yieldRate.mul(yieldDuration));
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function _checkpointUser(address account) internal {
        // Need to retro-adjust some things if the period hasn't been renewed, then start a new one
        this.notifyRewardAmount();
        sync();

        // Calculate the earnings first
        _syncEarned(account);

        // Get the old and the new gToken balances
        uint256 old_gToken_balance = usergTokenCheckpointed[account];
        uint256 new_gToken_balance = gToken.balanceOf(account);

        // Update the user's stored gToken balance
        usergTokenCheckpointed[account] = new_gToken_balance;

        // Update the user's stored ending timestamp
        IgToken.LockedBalance memory curr_locked_bal_pack = gToken.locked(account);
        usergTokenEndpointCheckpointed[account] = curr_locked_bal_pack.end;

        // Update the total amount participating
        if (new_gToken_balance >= old_gToken_balance) {
            uint256 weight_diff = new_gToken_balance.sub(old_gToken_balance);
            totalgTokenParticipating = totalgTokenParticipating.add(weight_diff);
        } else {
            uint256 weight_diff = old_gToken_balance.sub(new_gToken_balance);
            totalgTokenParticipating = totalgTokenParticipating.sub(weight_diff);
        }

        // Mark the user as initialized
        if (!userIsInitialized[account]) {
            userIsInitialized[account] = true;
            lastRewardClaimTime[account] = block.timestamp;
        }
    }

    function _syncEarned(address account) internal {
        if (account != address(0)) {
            uint256 earned0 = earned(account);
            yields[account] = earned0;
            userYieldPerTokenPaid[account] = yieldPergTokenStored;
        }
    }

    // Anyone can checkpoint another user
    function checkpointOtherUser(address user_addr) external {
        _checkpointUser(user_addr);
    }

    // Checkpoints the user
    function checkpoint() external {
        _checkpointUser(msg.sender);
    }

    function getYield() external nonReentrant notYieldCollectionPaused checkpointUser(msg.sender) returns (uint256 yield0) {
        require(greylist[msg.sender] == false, "Address has been greylisted");
        yield0 = yields[msg.sender];
        if (yield0 > 0) {
            yields[msg.sender] = 0;
            yieldAmount = yieldAmount.add(yield0);
            TransferHelper.safeTransfer(
                emitted_token_address,
                msg.sender,
                yield0
            );
            emit YieldCollected(msg.sender, yield0, emitted_token_address);
        }

        lastRewardClaimTime[msg.sender] = block.timestamp;
    }

    function getYieldUser(address from) external nonReentrant notYieldCollectionPaused checkpointUser(from) returns (uint256 yield0) {
        require(greylist[msg.sender] == false, "Address has been greylisted");
        yield0 = yields[from];
        if (yield0 > 0) {
            yields[from] = 0;
            yieldAmount = yieldAmount.add(yield0);
            TransferHelper.safeTransfer(
                emitted_token_address,
                from,
                yield0
            );
            emit YieldCollected(from, yield0, emitted_token_address);
        }

        lastRewardClaimTime[from] = block.timestamp;
    }


    function estimateWeekYield(address account) public view returns (uint256) {


        uint256 currentProfit = earned(account);

        uint256 profitDuringWeek = 0;
        if (block.timestamp > lastRewardClaimTime[account] && currentProfit > 0) {
            profitDuringWeek = block.timestamp.sub(lastRewardClaimTime[account]).mul(currentProfit).div(1 weeks);

        }
        return profitDuringWeek;
    }


    function sync() public {
        // Update the total gToken supply
        yieldPergTokenStored = yieldPergToken();
        totalgTokenSupplyStored = gToken.totalSupplyAtNow();
        lastUpdateTime = lastTimeYieldApplicable();
    }

    function rewardAmount() external view returns (uint256) {
        return _rewardAmount.sub(yieldAmount);
    }


    function notifyRewardAmount() external {

        if (block.timestamp < periodFinish) return;
        if (isWithdrawRewardRouter) {
            rewardRouter.withdrawToEDEPool();
        }
        uint256 tokenAmount = emittedToken.balanceOf(address(this));

        uint256 amount;
        if (isFixedReward) {
            amount = weekReward;
        } else {
            amount = tokenAmount.sub(this.rewardAmount()).mul(scaleBalance).div(denominator);
        }


        // Update some values beforehand
        sync();

        // Update the new yieldRate
        if (block.timestamp >= periodFinish) {
            yieldRate = amount.div(yieldDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(yieldRate);
            yieldRate = amount.add(leftover).div(yieldDuration);
        }

        // Update duration-related info
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(yieldDuration);
        _rewardAmount = _rewardAmount.add(amount);
        emit RewardAdded(amount, yieldRate);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // Added to support recovering LP Yield and other mistaken tokens from other systems to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyByOwnGov {
        // Only the owner address can ever receive the recovery withdrawal
        TransferHelper.safeTransfer(tokenAddress, owner, tokenAmount);
        emit RecoveredERC20(tokenAddress, tokenAmount);
    }


    function setYieldDuration(uint256 _yieldDuration) external onlyByOwnGov {
        require(periodFinish == 0 || block.timestamp > periodFinish, "Previous yield period must be complete before changing the duration for the new period");
        yieldDuration = _yieldDuration;
        emit YieldDurationUpdated(yieldDuration);
    }

    function greylistAddress(address _address) external onlyByOwnGov {
        greylist[_address] = !(greylist[_address]);
    }

    function setScale(uint256 _scaleBalance, uint256 _denominator) external onlyByOwnGov {
        scaleBalance = _scaleBalance;
        denominator = _denominator;
    }

    //set weekReward
    function setWeekReward(uint256 _weekReward) external onlyByOwnGov {
        weekReward = _weekReward;
    }

    function toggleRewardNotifier(address notifier_addr) external onlyByOwnGov {
        reward_notifiers[notifier_addr] = !reward_notifiers[notifier_addr];
    }

    function setPauses(bool _yieldCollectionPaused) external onlyByOwnGov {
        yieldCollectionPaused = _yieldCollectionPaused;
    }

    function setYieldRate(uint256 _new_rate0, bool sync_too) external onlyByOwnGov {
        yieldRate = _new_rate0;

        if (sync_too) {
            sync();
        }
    }

    function setTimelock(address _new_timelock) external onlyByOwnGov {
        timelock_address = _new_timelock;
    }

    // set isWithdrawRewardRouter
    function setIsWithdrawRewardRouter(bool _isWithdrawRewardRouter) external onlyByOwnGov {
        isWithdrawRewardRouter = _isWithdrawRewardRouter;
    }

    //set isFixedReward
    function setIsFixedReward(bool _isFixedReward) external onlyByOwnGov {
        isFixedReward = _isFixedReward;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward, uint256 yieldRate);
    event OldYieldCollected(address indexed user, uint256 yield, address token_address);
    event YieldCollected(address indexed user, uint256 yield, address token_address);
    event YieldDurationUpdated(uint256 newDuration);
    event RecoveredERC20(address token, uint256 amount);
    event YieldPeriodRenewed(address token, uint256 yieldRate);
    event DefaultInitialization();

}