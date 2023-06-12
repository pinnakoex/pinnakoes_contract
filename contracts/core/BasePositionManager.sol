// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./VaultMSData.sol";
import "./interfaces/IVault.sol";
import "../tokens/interfaces/IWETH.sol";
import "../data/Handler.sol";
import "../DID/interfaces/IPID.sol";


contract BasePositionManager is ReentrancyGuard, Ownable, Handler{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public minExecutionFee;

    IVault public vault;
    address public weth;
    IPID public pid;

    event SetMinExecutionFee(uint256 minExecutionFee);


    receive() external payable {
        require(msg.sender == weth, "BasePositionManager: invalid sender");
    }

    //- Functions for owner
    function initialize( address _vault, address _weth,address _pid) external onlyOwner {
        vault = IVault(_vault);
        weth = _weth;
        pid = IPID(_pid);
    }
    function withdrawToken( address _account, address _token, uint256 _amount ) external onlyOwner{
        IERC20(_token).safeTransfer(_account, _amount);
    }
    function sendValue(address payable _receiver, uint256 _amount) external onlyOwner {
        _receiver.sendValue(_amount);
    }
    function setMinExecutionFee(uint256 _minExecutionFee) external onlyOwner {
        minExecutionFee = _minExecutionFee;
        emit SetMinExecutionFee(_minExecutionFee);
    }

    function _transfer(address _token, address _account, address _receiver, uint256 _amount) internal {
        // require(vault.isFundingToken(_token), "invalid token");
        IERC20(_token).safeTransferFrom(_account, _receiver, _amount);
    }

    //- Functions internal
    function _increasePosition(address _account, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong, uint256 _price) internal {
        if (_isLong) {
            require(vault.getMaxPrice(_indexToken) <= _price, "BasePositionManager: mark price higher than limit");
        } else {
            require(vault.getMinPrice(_indexToken) >= _price, "BasePositionManager: mark price lower than limit");
        }
        vault.increasePosition(_account, _collateralToken, _indexToken, _sizeDelta, _isLong);
        pid.updateTradingScoreForAccount(_account, address(vault), _sizeDelta, 0);   
    }

    function _decreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver, uint256 _price) internal returns (uint256) {
        if (_isLong) {
            require(vault.getMinPrice(_indexToken) >= _price, "BasePositionManager: mark price lower than limit");
        } else {
            require(vault.getMaxPrice(_indexToken) <= _price, "BasePositionManager: mark price higher than limit");
        }
        
        pid.updateTradingScoreForAccount(_account, address(vault), _sizeDelta, 100);   
        return vault.decreasePosition(_account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver);
    }


    function _swap(address[] memory _path, uint256 _minOut, address _receiver) internal returns (uint256) {
        if (_path.length == 2) {
            return vaultSwap(_path[0], _path[1], _minOut, _receiver);
        }
        revert("BasePositionManager: invalid _path.length");
    }

    function vaultSwap(address _tokenIn, address _tokenOut, uint256 _minOut, address _receiver) internal returns (uint256) {
        uint256 amountOut = vault.swap(_tokenIn, _tokenOut, _receiver);
        require(amountOut >= _minOut, "BasePositionManager: insufficient amountOut");
        return amountOut;
    }

    function _transferInETH() internal {
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
        }
    }

    function _transferOutETH(uint256 _amountOut, address payable _receiver) internal {
        IWETH(weth).withdraw(_amountOut);
        _receiver.sendValue(_amountOut);
    }

    function _transferOutETHWithGasLimit(uint256 _amountOut, address payable _receiver) internal {
        IWETH(weth).withdraw(_amountOut);
        _receiver.transfer(_amountOut);
    }
}
