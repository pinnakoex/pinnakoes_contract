// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../tokens/interfaces/IWETH.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../utils/EnumerableValues.sol";
import "../data/Handler.sol";
import "./interfaces/IUserFeeResv.sol";
contract UserFeeResv is  Ownable, Handler, IUserFeeResv{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address payable;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;

    mapping(address => mapping(address => uint256)) public userFeeAccum;
    // mapping(address => mapping(address => uint256)) public userFeeDiscount;
    // mapping(address => mapping(address => uint256)) public userFeeRebate;
    mapping(address => mapping(address => uint256)) public userFeeUncalimed;
    

    mapping(string => address) public addDef;
    mapping(address => uint256) public balance;

    EnumerableSet.AddressSet private tokenSet;
    address[] public tokenList;

    event UpdateFee(address source, address account, address token, uint256 amount);
    event Claim(address account, address token, uint256 claimAmount);
    event TransferIn(address token, uint256 amount);
    event TransferOut(address token, uint256 amount, address receiver);

    receive() external payable {
        // require(msg.sender == weth, "invalid sender");
        // Attention: only support erc20 token
    }
    
    function setAddress(string[] memory _name_list, address[] memory _contract_list) external onlyOwner{
        for(uint i = 0; i < _contract_list.length; i++){
            addDef[_name_list[i]] = _contract_list[i];
        }
    }
    
    function setTokens(address[] memory _tokenList, bool _status) external onlyOwner{
        for (uint8 i = 0; i < _tokenList.length; i++){
            if (_status && !tokenSet.contains(_tokenList[i]))
                tokenSet.add(_tokenList[i]);
            else if (!_status && tokenSet.contains(_tokenList[i]))
                tokenSet.remove(_tokenList[i]);     
        }
        tokenList = tokenSet.valuesAt(0, tokenSet.length());
    }
    

    function withdrawToken(address _token, uint256 _amount, address _dest) external onlyOwner {
        IERC20(_token).safeTransfer(_dest, _amount);
        balance[_token] = IERC20(_token).balanceOf(address(this));
        //todo: emit
    }

    function depositNative(uint256 _amount) external payable onlyOwner {
        uint256 _curBalance = address(this).balance;
        IWETH(addDef["nativeToken"]).deposit{value: _amount > _curBalance ? _curBalance : _amount}();
        //todo: emit
    }

    function getTokenList() external view returns (address[] memory) {
        return tokenList;
    }

    function updateAll(address _account) external payable override onlyHandler {
        for (uint8 i = 0; i < tokenList.length; i++){
            uint256 _addAmount = _transferIn(tokenList[i]);
            userFeeAccum[_account][tokenList[i]] = userFeeAccum[_account][tokenList[i]].add(_addAmount);
            userFeeUncalimed[_account][tokenList[i]] = userFeeUncalimed[_account][tokenList[i]].add(_addAmount);
        }
        //todo: emit
    }

    function update(address _account, address _token, uint256 _amount) external payable override onlyHandler {
        require(tokenSet.contains(_token), "[FeeResv] unsupport token");
        uint256 _addAmount = _transferIn(_token);
        require(_amount <= _addAmount, "[FeeResv] insufficient token in");
        if (_account != address(0)){
            userFeeAccum[_account][_token] = userFeeAccum[_account][_token].add(_addAmount);
            userFeeUncalimed[_account][_token] = userFeeUncalimed[_account][_token].add(_addAmount);
        }
        emit UpdateFee(msg.sender, _account, _token, _amount);
    }
    // --- public view functions
    function claim(address _account) external override{
        for (uint8 i = 0; i < tokenList.length; i++){
            uint256 claimAmount = userFeeUncalimed[_account][tokenList[i]];
            userFeeUncalimed[_account][tokenList[i]] = 0;
            _transferOut(tokenList[i], claimAmount, _account);
            emit Claim(_account, tokenList[i], claimAmount);
        }
    }    

    function claimable(address _account) external view override returns (address[] memory, uint256[] memory){
        uint256[] memory rewardList = new uint256[](tokenList.length);
        for (uint8 i = 0; i < tokenList.length; i++){
            rewardList[i] = userFeeUncalimed[_account][tokenList[i]];
        }  
        return (tokenList, rewardList);
    }

    //-- Private functions.
    function _transferIn(address _token) private returns (uint256) {
        uint256 prevBalance = balance[_token];
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        if (nextBalance <= prevBalance)
            return 0;
        balance[_token] = nextBalance;
        uint256 amountIn = nextBalance.sub(prevBalance);
        emit TransferIn(_token, amountIn);
        return amountIn;
    }
    
    function _transferOut( address _token, uint256 _amount, address _receiver ) private {
        if (_amount == 0)
            return;
        require(IERC20(_token).balanceOf(address(this)) >= _amount, "[FeeResv] Insufficient balance");
        IERC20(_token).safeTransfer(_receiver, _amount);
        balance[_token] = IERC20(_token).balanceOf(address(this));
        emit TransferOut(_token, _amount, _receiver);
    }
}