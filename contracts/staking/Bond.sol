// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../tokens/interfaces/IMintable.sol";

interface ITreasury {
    function aum() external view returns (uint256);
    function redeem(address _token, uint256 _amount, address _dest) external;
}

interface ITreasuryUtils {
    function aum() external view returns (uint256);
}

interface IPrice{
    function getTwap(address _token, uint256 _timestamp) external view returns (uint256);
    function getPriceLatest(address _token) external view returns (uint256);
    function usdToToken(address _token, uint256 _usd) external view returns (uint256);
    function tokenToUsd(address _token, uint256 _amount) external view returns (uint256);
    function usdToTokenWithPrice(address _token, uint256 _usd, uint256 _tokenPrice) external view returns (uint256);
    function tokenToUsdWithPrice(address _token, uint256 _amount, uint256 _tokenPrice) external view returns (uint256);
}
interface IInstVesting{
    function directVesting(address _account, address _token, uint256 _duration) external;
}

library RInfo {
    struct Round {
        uint256 priceBase;
        uint256 priceAsk;
        uint256 priceBid;
        uint256 entryTimestamp;
        uint256 bondIssued;
        uint256 roundDuration;
        uint256 roundIndex;
        uint256 discount;
    }

    uint256 constant PRICE_PRECISION = 1e30;
    uint256 constant COM_PRECISION = 1000;
}



contract Bond is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    address public treasury;
    address public treasuryUtil;
    address public twapPrice;
    address public instVesting;
    address public pnk;
    address public usdc;

    uint256 public roundDuration = 5 days;
    uint256 public releaseDuration = 5 days;
    uint256 public currentRoundIndex;
    uint256 public priceGap = 100;
    uint256 public treasuryGap = 100;
    uint256 public discount = 100;

    mapping(uint256 => RInfo.Round) public rounds;

    event CreateRound(RInfo.Round);


    function setTokens(address _pnk, address _usdc) external onlyOwner{
        pnk = _pnk;
        usdc = _usdc;
    }

    function setAddress(address _treasury, address _twapPrice, address _instVesting, address _treasuryUtil) external onlyOwner{
        treasury = _treasury;
        twapPrice = _twapPrice;
        instVesting = _instVesting;
        treasuryUtil = _treasuryUtil;
    }

    function setTime(uint256 _roundDuration, uint256 _releaseDuration) external onlyOwner{
        roundDuration = _roundDuration;
        releaseDuration = _releaseDuration;
    }

    function setValue(uint256 _priceGap, uint256 _treasuryGap, uint256 _discount) external onlyOwner{
        priceGap = _priceGap;
        treasuryGap = _treasuryGap;
        discount = _discount;
    }
    // function getRoundInfo()

    function bound(uint256 _amount) external {
        _initRound();
        RInfo.Round storage _round = rounds[currentRoundIndex];
        uint256 _curPrice = IPrice(twapPrice).getPriceLatest(pnk);
        
        uint256 _initPrice = rounds[currentRoundIndex].priceBase;
        if (_curPrice > _round.priceAsk){
            IERC20(usdc).safeTransferFrom(msg.sender, treasury, _amount);
            uint256 usdAmount = IPrice(twapPrice).tokenToUsd(usdc, _amount);
            require(_round.bondIssued.add(usdAmount) <= capacity(), "Treasury Bond capacity exceed.");
            _round.bondIssued = _round.bondIssued.add(usdAmount);
            uint256 pnkAmount = IPrice(twapPrice).usdToTokenWithPrice(pnk, usdAmount, _round.priceBase);
            ITreasury(treasury).redeem(pnk, pnkAmount, instVesting);
            IInstVesting(instVesting).directVesting(msg.sender, pnk, releaseDuration);
        }
        else if (_curPrice < _round.priceBid){
            IERC20(pnk).safeTransferFrom(msg.sender, treasury, _amount);
            uint256 usdAmount = IPrice(twapPrice).tokenToUsdWithPrice(pnk, _amount, _round.priceBase);
            require(_round.bondIssued.add(usdAmount) <= capacity(), "Treasury Bond capacity exceed.");
            _round.bondIssued = _round.bondIssued.add(usdAmount);
            uint256 usdcAmount =IPrice(twapPrice).usdToToken(usdc, usdAmount);
            ITreasury(treasury).redeem(usdc, usdcAmount, instVesting);
            IInstVesting(instVesting).directVesting(msg.sender, usdc, releaseDuration);
        }else{
            revert("invalid price");
        }
    }


    function capacity() public view returns (uint256){
        return ITreasuryUtils(treasuryUtil).aum().mul(treasuryGap).div(RInfo.COM_PRECISION);
    }

    function getRoundInfo() public view returns (RInfo.Round memory, uint256){
        uint256 r_id = curRoundId();
        uint256 _capacity = capacity();
        if (r_id == currentRoundIndex)
            return (rounds[currentRoundIndex], _capacity);
        else
            return (_getNewRound(getNextRoundTime()), _capacity);
    }

    function getNextRoundTime() public view returns (uint256){
        RInfo.Round memory _round = rounds[currentRoundIndex];
        if (_round.entryTimestamp == 0)
            return block.timestamp;
        uint256 nextRoundTime = block.timestamp;
        if (block.timestamp < _round.entryTimestamp.add(_round.roundDuration).add(roundDuration))
            nextRoundTime = _round.entryTimestamp.add(_round.roundDuration);
        return nextRoundTime;
    }

    function _getNewRound(uint256 _timestamp) private view returns (RInfo.Round memory){
        uint256 _basePrice =  IPrice(twapPrice).getTwap(pnk, _timestamp);

        return RInfo.Round(
            _basePrice,
            _basePrice.mul(RInfo.COM_PRECISION.add(priceGap)).div(RInfo.COM_PRECISION),
            _basePrice.mul(RInfo.COM_PRECISION.sub(priceGap)).div(RInfo.COM_PRECISION),
            _timestamp,
            0,
            roundDuration,
            currentRoundIndex,
            discount);
    }

    function curRoundId() public view returns (uint256){
        RInfo.Round memory _round = rounds[currentRoundIndex];
        if (_round.entryTimestamp > 0 
            && block.timestamp < _round.entryTimestamp.add(_round.roundDuration))
            return currentRoundIndex;
        return currentRoundIndex.add(1);
    }

    function initRound() public returns (uint256){
        return _initRound();
    }
    
    function _initRound() private returns (uint256){
        RInfo.Round memory _round = rounds[currentRoundIndex];
        if (_round.entryTimestamp > 0 
            && block.timestamp < _round.entryTimestamp.add(_round.roundDuration))
            return currentRoundIndex;
        uint256 nextRoundTime = block.timestamp;
        if (block.timestamp < _round.entryTimestamp.add(_round.roundDuration).add(roundDuration))
            nextRoundTime = _round.entryTimestamp.add(_round.roundDuration);
    
        currentRoundIndex = currentRoundIndex.add(1);
        rounds[currentRoundIndex] = _getNewRound(nextRoundTime);
        emit CreateRound(rounds[currentRoundIndex]);
        return currentRoundIndex;
    }





}

