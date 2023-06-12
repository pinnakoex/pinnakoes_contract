// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";


interface IPNKStaking {
    function totalReward() external view returns (uint256);
}

interface ITreasury {
    function redeem(address _token, uint256 _amount, address _dest) external;
}

contract RedeemTreasury is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    address public treasury;
    address public treasuryResv;
    address public treasuryToken;
    address public pnkStakingPool;
    address[] public rewardTokenList;

    uint256 public baseTimestamp;
    uint256 public roundDuration = 16 days;
    uint256 public openRedeemDuration = 2 days;

    uint256 public resvRatio = 100;
    uint256 public constant RESV_PRECISION = 1000;
    event Redeem(address account, uint256 tAmount, address tokenout, uint256 tokenOutAmount, uint256 toUserAmount);
 
    function set(address _treasuryToken, address _treasury, address _pnkStakingPool, address _treasuryResv) external onlyOwner{
        treasuryToken = _treasuryToken;
        treasury = _treasury;
        treasuryResv = _treasuryResv;
        pnkStakingPool = _pnkStakingPool;
    }

    function setTime(uint256 _roundDuration, uint256 _openDuration) external onlyOwner{
        roundDuration = _roundDuration;
        openRedeemDuration = _openDuration;
    }

    function setResvRatio(uint256 _resvRatio) external onlyOwner{
        resvRatio = _resvRatio;
    }

    function resetBaseTime(uint256 _time) external onlyOwner{
        baseTimestamp = _time > 0 ? _time : block.timestamp;
    }

    function setRewardTokenList(address[] memory _list) external onlyOwner{
        rewardTokenList = _list;
    }

    function roundStart(uint256 _shift) public view returns (uint256){
        uint256 curRoundId = (block.timestamp.sub(baseTimestamp)).div(roundDuration);
        uint256 destRoundId = curRoundId.add(uint256(_shift));
        return baseTimestamp.add(roundDuration.mul(destRoundId));
    }

    function nextOpenRedeemTime() public view returns (uint256) {
        uint256 shift = isOpenRedeemNow() ? 1 : 0;
        return roundStart(shift).add(roundDuration.sub(openRedeemDuration));
    }

    function isOpenRedeemNow() public view returns (bool){
        uint256 curRoundStart = roundStart(0);
        return block.timestamp >  curRoundStart.add(roundDuration).sub(openRedeemDuration);
    }


    function redeemTreasuryReward(uint256 _amount) external {
        require(isOpenRedeemNow(), "redeem token is closed.");
        require(_amount > 0);
        require(_amount > 0);
        address _account = _msgSender();
        uint256 _edeCur = tTokenCirculation();
        require(_edeCur > 0, "empty tTokenCirculation");
        IERC20(treasuryToken).safeTransferFrom(_account, treasury, _amount);
        for (uint8 i = 0; i < rewardTokenList.length; i++){
            uint256 _rdm_amount = IERC20(rewardTokenList[i]).balanceOf(treasury).mul(_amount).div(_edeCur);
            uint256 _rdm_amount_toResv = _rdm_amount.mul(resvRatio).div(RESV_PRECISION);
            uint256 _rdm_amount_toUser = _rdm_amount.sub(_rdm_amount_toResv);

            ITreasury(treasury).redeem(rewardTokenList[i], _rdm_amount_toUser, _account);
            if (treasuryResv != address(0))
                ITreasury(treasury).redeem(rewardTokenList[i], _rdm_amount_toResv, treasuryResv);

            emit Redeem(_account, _amount, rewardTokenList[i], _rdm_amount, _rdm_amount_toUser);
        }
    }

    function estimatedReward(uint256 _amount) public view returns (uint256[] memory) {
        uint256[] memory _desvV = new uint256[](rewardTokenList.length);

        uint256 _edeCur = tTokenCirculation();
        for (uint8 i = 0; i < rewardTokenList.length; i++){
            uint256 _rdm_token_amount = IERC20(rewardTokenList[i]).balanceOf(treasury).mul(_amount).div(_edeCur);
            _desvV[i] = _rdm_token_amount.mul(RESV_PRECISION-resvRatio).div(RESV_PRECISION);
        }
        return _desvV;
    }



    function tTokenCirculation() public view returns (uint256) {
        return IPNKStaking(pnkStakingPool).totalReward().sub(IERC20(treasuryToken).balanceOf(treasury));
    }   
}

