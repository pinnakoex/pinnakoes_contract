// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IFeeRouter.sol";


contract FeeRouter is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    address[] public feeTokens;
    mapping(address => uint256) public totalFees;
    mapping(address => mapping(address => uint256)) public detailFees;
    address[] public destAddressBuffer;
    uint256[] public destWeightBuffer;
    uint256 public destWeightSum;
    uint256 public totalDestNum;
    
    event TransferIn(address token, uint256 amount);
    event TransferOut(address token, uint256 amount, address receiver);

    function withdrawToken(address _token, uint256 _amount, address _dest) external onlyOwner {
        IERC20(_token).safeTransfer(_dest, _amount);
    }

    function setAddress(address[] memory _feeTokens) external onlyOwner{
        feeTokens = _feeTokens;
    }

    function setDistribution(address[] memory _address, uint256[] memory _weights) external onlyOwner{
        destAddressBuffer = _address;
        destWeightBuffer = _weights;
        destWeightSum = 0;
        totalDestNum = destAddressBuffer.length;
        for (uint256 i = 0; i < totalDestNum; i++){
            destWeightSum = destWeightSum.add(destWeightBuffer[i]);
        }
    }

    function distribute() external {
        for (uint8 _tk = 0; _tk < feeTokens.length; _tk++){
            uint256 cur_balance = IERC20(feeTokens[_tk]).balanceOf(address(this));
            totalFees[feeTokens[_tk]] = totalFees[feeTokens[_tk]].add(cur_balance);
            for (uint8 i = 0; i < totalDestNum; i++){
                uint256 _amounts_dist = cur_balance.mul(destWeightBuffer[i]).div(destWeightSum);
                detailFees[destAddressBuffer[i]][feeTokens[_tk]] = detailFees[destAddressBuffer[i]][feeTokens[_tk]].add(cur_balance);
                IERC20(feeTokens[_tk]).transfer(destAddressBuffer[i],_amounts_dist);
                emit TransferOut(feeTokens[_tk], _amounts_dist, destAddressBuffer[i]);
            }
        }
    }

    function getDistribution() external view returns(address[] memory, uint256[]memory){
        return (destAddressBuffer, destWeightBuffer);
    }
    
    function getFeeTokens() external view returns(address[] memory, uint256[]memory){
        uint256[] memory feeRec = new uint256[](feeTokens.length);
        for(uint8 i = 0; i < feeTokens.length; i++){
            feeRec[i] = totalFees[feeTokens[i]];
        }
        return (feeTokens, feeRec);
    }
}