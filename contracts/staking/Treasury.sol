// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../utils/EnumerableValues.sol";
import "../core/interfaces/ILpManager.sol";
import "../tokens/interfaces/IWETH.sol";
import "./interfaces/IRewardRouter.sol";
import "./interfaces/IRewardTracker.sol";
import "../core/interfaces/IPlpManager.sol";
import "../data/Handler.sol";


interface ILPYield {
    function stake(address _token, uint256 _amount) external;
    function unstake(uint256 _amount) external;
    function claim() external;
}


contract Treasury is Ownable, Handler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;
    using Address for address payable;

    mapping(string => address) public addDef;
    mapping(address => address) public plpToPlpManager;
    mapping(address => address) public plpToPlpTracker;

    address public weth;

    EnumerableSet.AddressSet supportedToken;
    
    event Receive(address _sender, uint256 _amount);

    constructor(address _weth) {
        weth = _weth;
    }

    receive() external payable {
        emit Receive(msg.sender, msg.value);
    }
    
    function approve(address _token, address _spender, uint256 _amount) external onlyOwner {
        IERC20(_token).approve(_spender, _amount);
    }

    function setRelContract(address[] memory _plp_n, address[] memory _plp_manager, address[] memory _plp_tracker) external onlyOwner{
        for(uint i = 0; i < _plp_n.length; i++){
            if (!supportedToken.contains(_plp_n[i]))
                supportedToken.add(_plp_n[i]);    
            plpToPlpManager[_plp_n[i]] = _plp_manager[i];
            plpToPlpTracker[_plp_n[i]] = _plp_tracker[i];
        }
    }

    function setToken(address[] memory _tokens, bool _state) external onlyOwner {
        if (_state){
            for(uint i = 0; i < _tokens.length; i++){
                if (!supportedToken.contains(_tokens[i]))
                    supportedToken.add(_tokens[i]);
            }
        }
        else{
            for(uint i = 0; i < _tokens.length; i++){
                if (supportedToken.contains(_tokens[i]))
                    supportedToken.remove(_tokens[i]);
            }
        }
    }

    function setAddress(string[] memory _name_list, address[] memory _contract_list) external onlyOwner{
        for(uint i = 0; i < _contract_list.length; i++){
            addDef[_name_list[i]] = _contract_list[i];
        }
    }

    function withdrawToken(address _token, uint256 _amount, address _dest) external onlyOwner {
        IERC20(_token).safeTransfer(_dest, _amount);
    }
    function DepositETH(uint256 _value) external onlyOwner {
        IWETH(weth).deposit{value: _value}();
    }
    function sendValue(address payable _receiver, uint256 _amount) external onlyOwner {
        _receiver.sendValue(_amount);
    }
    

    function redeem(address _token, uint256 _amount, address _dest) external onlyManager{
        require(IERC20(_token).balanceOf(address(this)) >= _amount, "max amount exceed");
        IERC20(_token).safeTransfer(_dest, _amount);
    }

    function depositNative(uint256 _amount) external payable onlyOwner {
        uint256 _curBalance = address(this).balance;
        IWETH(addDef["nativeToken"]).deposit{value: _amount > _curBalance ? _curBalance : _amount}();
    }

    // ------ Funcs. processing plp
    function buyPLP(address _plp_n, address _token, uint256 _amount, bytes[] memory _priceUpdateData) external onlyHandler returns (uint256) {
        require(isSupportedToken(_token), "not supported src token");
        if (_amount == 0)
            _amount = IERC20(_plp_n).balanceOf(address(this));
        return _buyPLP(_token, _plp_n, _amount, _priceUpdateData);
    }

    function _buyPLP(address _plp_n, address _token, uint256 _amount, bytes[] memory _priceUpdateData) internal returns (uint256) {
        require(plpToPlpManager[_plp_n]!= address(0), "PlpManager not set");
        uint256 plp_ret = 0;
        if (_token != address(0)){
            IERC20(_token).approve(plpToPlpManager[_plp_n], _amount);
            require(IERC20(_token).balanceOf(address(this)) >= _amount, "insufficient token to buy plp");
            plp_ret = IPlpManager(plpToPlpManager[_plp_n]).addLiquidity(_token, _amount, 0, _priceUpdateData);
        }

        else{
            require(address(this).balance >= _amount, "insufficient native token ");
            plp_ret = IPlpManager(plpToPlpManager[_plp_n]).addLiquidityETH{value: _amount}(0,_priceUpdateData);
        }
        return plp_ret;
    }

    function sellPLP(address _token_out, address _plp_n, uint256 _amount_sell, bytes[] memory _priceUpdateData) external onlyHandler returns (uint256) {
        require(isSupportedToken(_token_out), "not supported out token");
        require(isSupportedToken(_plp_n), "not supported plp n");
        return _sellPLP(_token_out, _plp_n, _amount_sell, _priceUpdateData);
    }

    function _sellPLP(address _token_out, address _plp_n, uint256 _amount_sell, bytes[] memory _priceUpdateData) internal returns (uint256) {
        require(isSupportedToken(_token_out), "not supported src token");
        require(plpToPlpManager[_plp_n]!= address(0), "PLP manager not set");
        IERC20(_plp_n).approve(plpToPlpManager[_plp_n], _amount_sell);
        require(IERC20(_plp_n).balanceOf(address(this)) >= _amount_sell, "insufficient plp to sell");
        
        uint256 token_ret = 0;
        if (_token_out != address(0)){
            token_ret = IPlpManager(plpToPlpManager[_plp_n]).removeLiquidity(_token_out, _amount_sell, 0, _priceUpdateData);
        }
        else{
            token_ret = IPlpManager(plpToPlpManager[_plp_n]).removeLiquidityETH(_amount_sell, _priceUpdateData);
        }
        return token_ret;
    }

    // Func. public view
    function isSupportedToken(address _token) public view returns(bool){
        return supportedToken.contains(_token);
    }
}