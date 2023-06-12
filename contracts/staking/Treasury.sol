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



interface ILPYield {
    function stake(address _token, uint256 _amount) external;
    function unstake(uint256 _amount) external;
    function claim() external;
}


contract Treasury is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;
    using Address for address payable;


    mapping(string => address) public addDef;
    mapping(address => address) public plpToPlpManager;
    mapping(address => address) public plpToPlpTracker;

    //distribute setting
    EnumerableSet.AddressSet supportedToken;
    uint256 public weight_buy_plp;
    uint256 public weight_EDPlp;

    bool public openForPublic = true;
    mapping (address => bool) public isHandler;
    mapping (address => bool) public isManager;
    uint8 method;


    event SellESUD(address token, uint256 eusd_amount, uint256 token_out_amount);
    event Swap(address token_src, address token_dst, uint256 amount_src, uint256 amount_out);



    constructor(uint8 _method) {
        method = _method;
    }

    receive() external payable {
        // require(msg.sender == weth, "invalid sender");
    }
    
    modifier onlyHandler() {
        require(isHandler[msg.sender] || msg.sender == owner(), "forbidden");
        _;
    }
    function setManager(address _manager, bool _isActive) external onlyOwner {
        isManager[_manager] = _isActive;
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }
    function approve(address _token, address _spender, uint256 _amount) external onlyOwner {
        IERC20(_token).approve(_spender, _amount);
    }

    function setOpenstate(bool _state) external onlyOwner {
        openForPublic = _state;
    }
    function setWeights(uint256 _weight_buy_plp, uint256 _weight_EDPlp) external onlyOwner {
        weight_EDPlp = _weight_EDPlp;
        weight_buy_plp = _weight_buy_plp;
    }
    function setRelContract(address[] memory _plp_n, address[] memory _plp_manager, address[] memory _plp_tracker) external onlyOwner{
        for(uint i = 0; i < _plp_n.length; i++){
            if (!supportedToken.contains(_plp_n[i]))
                supportedToken.add(_plp_n[i]);    
            plpToPlpManager[_plp_n[i]] = _plp_manager[i];
            plpToPlpTracker[_plp_n[i]] = _plp_tracker[i];
        }
    }


    function setToken(address[] memory _tokens, bool _state) external onlyOwner{
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

    function redeem(address _token, uint256 _amount, address _dest) external {
        require(isManager[msg.sender], "Only manager");
        require(IERC20(_token).balanceOf(address(this)) >= _amount, "max amount exceed");
        IERC20(_token).safeTransfer(_dest, _amount);
    }

    function depositNative(uint256 _amount) external payable onlyOwner {
        uint256 _curBalance = address(this).balance;
        IWETH(addDef["nativeToken"]).deposit{value: _amount > _curBalance ? _curBalance : _amount}();
    }


    function treasureSwap(address _src, address _dst, uint256 _amount_in, uint256 _amount_out_min) external onlyHandler returns (uint256) {
        return _treasureSwap(_src, _dst, _amount_in, _amount_out_min);
    }

    function _treasureSwap(address _src, address _dst, uint256 _amount_in, uint256 _amount_out_min) internal returns (uint256) {
        return 0;
    }

    // ------ Funcs. processing plp
    function buyPLP(address _token, address _plp_n, uint256 _amount) external onlyHandler returns (uint256) {
        require(isSupportedToken(_token), "not supported src token");
        if (_amount == 0)
            _amount = IERC20(_plp_n).balanceOf(address(this));
        return _buyPLP(_token, _plp_n, _amount);
    }

    function _buyPLP(address _token, address _plp_n, uint256 _amount) internal returns (uint256) {
        return 0;
    }

    function sellPLP(address _token_out, address _plp_n, uint256 _amount_sell) external onlyHandler returns (uint256) {
        require(isSupportedToken(_token_out), "not supported out token");
        require(isSupportedToken(_plp_n), "not supported plp n");
        return _sellPLP(_token_out, _plp_n, _amount_sell);
    }

    function _sellPLP(address _token_out, address _plp_n, uint256 _amount_sell) internal returns (uint256) {
        return 0;
    }


    // Func. public view
    function isSupportedToken(address _token) public view returns(bool){
        return supportedToken.contains(_token);
    }
}