// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IgTokenDistributor.sol";
import "./interfaces/IRewardRouter.sol";
import "./interfaces/IgToken_call.sol";
import "./utils/SafeToken.sol";


contract veStakeHelper is Ownable {
    using SafeToken for address;
    using SafeMath for uint256;

    IgToken_call public gToken;
    IgTokenDistributor public distributor_Token;
    IgTokenDistributor public distributor_FEE;
    IRewardRouter public rewardRouter;

    bool public isWithdrawRewardRouter = false;

    constructor (IgToken_call _gToken, IgTokenDistributor _distributorToken, IgTokenDistributor _distributorFEE, IRewardRouter _rewardRouter) {
        gToken = _gToken;
        distributor_Token = _distributorToken;
        distributor_FEE = _distributorFEE;
        rewardRouter = _rewardRouter;
    }

    function create_lock_helper(uint256 _value, uint256 _unlock_time) external {
        gToken.create_lock(msg.sender, _value, _unlock_time);
        gToken.checkpoint();
        distributor_Token.checkpointOtherUser(msg.sender);
        distributor_FEE.checkpointOtherUser(msg.sender);
        withdrawToEDEPool();
    }

    function increase_amount_helper(uint256 _value) external {
        gToken.increase_amount(msg.sender, _value);
        gToken.checkpoint();
        distributor_Token.checkpointOtherUser(msg.sender);
        distributor_FEE.checkpointOtherUser(msg.sender);
        withdrawToEDEPool();
    }

    function increase_unlock_time_helper(uint256 _unlock_time) external {
        gToken.increase_unlock_time(msg.sender, _unlock_time);
        distributor_Token.checkpointOtherUser(msg.sender);
        distributor_FEE.checkpointOtherUser(msg.sender);
        withdrawToEDEPool();
    }

    function getYield_helper() external {
        distributor_Token.getYieldUser(msg.sender);
        distributor_FEE.getYieldUser(msg.sender);
        withdrawToEDEPool();
    }


    function withdrawToEDEPool() public {
        if (isWithdrawRewardRouter) {
            rewardRouter.withdrawToEDEPool();
        }
    }

    function setIsWithdrawRewardRouter(bool _isWithdrawRewardRouter) external onlyOwner {
        isWithdrawRewardRouter = _isWithdrawRewardRouter;
    }


    function setRewardRouter(address _rewardRouter) external onlyOwner {
        rewardRouter = IRewardRouter(_rewardRouter);
    }

}