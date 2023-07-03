// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/Pausable.sol"; 

import "../DID/interfaces/IPID.sol";
import "../tokens/interfaces/IMintable.sol";



interface ITradeToEarn{
    function claimed(address _account) external view returns (uint256);
    function rebatedQuota(address _account) external view returns (uint256);
}


contract InviteToEarn is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    uint256 constant COM_RATE_PRECISION = 10**4;
    uint256 constant QUOTA_PRECISION = 10**18;

    uint256 public mintQuota = 2 * QUOTA_PRECISION;
    uint256 public socrePerQuota = 200 * PIDData.SCORE_PRECISION;

    address public pid;
    address public rewardToken;
 
    mapping(address => uint256) public consumedQuota;

    address[] public rebateActs;
    uint256[] public rebateActsWeights;
    uint256[] public rebateActsDecimals;

    event Claim(address _account, uint256 _quotaAmount, uint256 _rewardTokenAmount);

    function setAddress(address _pid, address _rewardToken) external onlyOwner{
        pid = _pid;
        rewardToken = _rewardToken;
    }

    function setQuota(uint256 _mintQuota, uint256 _socrePerQuota) external onlyOwner{
        mintQuota = _mintQuota;
        require(socrePerQuota >=  PIDData.SCORE_PRECISION.div(10), "invalid _socrePerQuota");
        socrePerQuota = _socrePerQuota;
    }

    function setActs(address[] memory _rebateActs,uint256[] memory _rebateActsDecimals, uint256[] memory _rebateActsWeights) external onlyOwner{
        rebateActs = _rebateActs;
        rebateActsDecimals = _rebateActsDecimals;
        rebateActsWeights = _rebateActsWeights;
    }

    function quota(address _account) public view returns (uint256, uint256){
        if (!IPID(pid).exist(_account))
            return (0, 0);
        uint256 _quota = mintQuota;
        for(uint64 i = 0; i < rebateActs.length; i++){
            uint256 _qI = ITradeToEarn(rebateActs[i]).rebatedQuota(_account);
            _qI = _qI.mul(QUOTA_PRECISION).div(10**rebateActsDecimals[i]);
            _quota = _quota.add(_qI.mul(rebateActsWeights[i]).div(COM_RATE_PRECISION));
        }

        PIDData.PIDDetailed memory _pidDet = IPID(pid).pidDetail(_account);
        _quota = _quota.add(_pidDet.score_acum.mul(QUOTA_PRECISION).div(socrePerQuota));
        return (_quota, consumedQuota[_account]);
    }

    function claim() public {
        address _account = msg.sender;
        if (!IPID(pid).exist(_account))
            return ;
        (uint256 _curQuota, ) = quota(_account);
        if (_curQuota <= consumedQuota[_account]){
            emit Claim(_account, 0, 0);
            return ; 
        }

        uint256 _rewardQuota= _curQuota.sub(consumedQuota[_account]);
        consumedQuota[_account] = _curQuota;

        uint256 _rewardToken = _rewardQuota.mul(10 ** IMintable(rewardToken).decimals()).div(QUOTA_PRECISION);
        require(_rewardToken >= IERC20(rewardToken).balanceOf(address(this)), "insufficient reward token in contract");
        IERC20(rewardToken).transfer(_account, _rewardToken);
        emit Claim(_account, _rewardQuota, _rewardToken);
    }
}

