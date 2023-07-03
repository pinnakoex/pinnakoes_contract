// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../utils/EnumerableValues.sol";
import "../data/Handler.sol";

library VData {
    struct VestingOrder {
        address account;
        address token;
        uint256 amount;
        uint256 entryTimestamp;
        uint256 lockDuration;
        uint256 claimed;
        uint256 index;
        bytes32 key;
    }

    uint256 constant PRICE_PRECISION = 1e30;
}

contract InstVesting is Ownable, Handler {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;
    
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableValues for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;

    mapping (address => uint256) public balance;
    mapping (address => uint256) public vestingOrdersIndex;
    mapping (bytes32 => VData.VestingOrder) internal vestingOrders;
    mapping (address => mapping(uint256 => bytes32)) public vestingOrderKeys;
    mapping (address => EnumerableSet.Bytes32Set) internal vestingOrderKeysAlive;

    EnumerableSet.AddressSet supportedTokens;

    event CreateVesingOrder(VData.VestingOrder);

    function sendValue(address payable _receiver, uint256 _amount) external onlyOwner {
        _receiver.sendValue(_amount);
    }
    function withdrawToken(address _account, address _token, uint256 _amount) external onlyOwner{
        IERC20(_token).safeTransfer(_account, _amount);
    }


    function addTokens(address[] memory _tokens) external onlyOwner{
        for(uint i = 0; i < _tokens.length; i++){
            if (!supportedTokens.contains(_tokens[i]))
                supportedTokens.add(_tokens[i]);
        }
    }

    function delTokens(address[] memory _tokens) external onlyOwner{
        for(uint i = 0; i < _tokens.length; i++){
            if (supportedTokens.contains(_tokens[i]))
                supportedTokens.remove(_tokens[i]);
        }    
    }

    function directVesting(address _account, address _token, uint256 _duration) external {
        require(_duration > 0, "lock duration must larger than 0");
        uint256 _tokenInAmount = _transferIn(_token);
        vestingOrdersIndex[_account] = vestingOrdersIndex[_account].add(1);

        bytes32 _key  = getRequestKey(_account, vestingOrdersIndex[_account], _token, _duration);
   
        VData.VestingOrder memory order = VData.VestingOrder(
            _account, _token,_tokenInAmount, block.timestamp, _duration, 0, vestingOrdersIndex[_account], _key);

        vestingOrderKeys[_account][vestingOrdersIndex[_account]] = _key;
        vestingOrderKeysAlive[_account].add(_key);
        vestingOrders[_key] = order;

        emit CreateVesingOrder(order);
    }

    function claimable(bytes32 _key) public view returns (uint256){
        VData.VestingOrder memory order = vestingOrders[_key];
        if (order.account == address(0) || order.lockDuration == 0 || order.amount == 0)
            return 0;
        uint256 _curTime = block.timestamp;
        uint256 _endtime = order.entryTimestamp.add(order.lockDuration);
        if (order.account == address(0) || _endtime < order.entryTimestamp)
            return 0;
        if (_curTime >= _endtime)
            return order.amount.sub(order.claimed);
        uint256 orderRemain = order.amount.mul(_endtime.sub(_curTime)).div(order.lockDuration);
        uint256 orderRelease = order.amount > orderRemain ? order.amount.sub(orderRemain) : 0;
        return orderRelease > order.claimed ? orderRelease.sub(order.claimed) : 0;
    }

    function userKeys(address _account) public view returns (bytes32[] memory){
        return vestingOrderKeysAlive[_account].valuesAt(0, vestingOrderKeysAlive[_account].length());
    }

    function userOrders(address _account) public view returns (VData.VestingOrder[] memory, uint256[] memory){
        bytes32[] memory keys = userKeys(_account);
        uint256[] memory claimableList = new uint256[](keys.length);
        VData.VestingOrder[] memory infs = new VData.VestingOrder[](keys.length);
        for(uint i = 0; i < keys.length; i++){
            infs[i] = vestingOrders[keys[i]];
            claimableList[i] = claimable(keys[i]);
        }
        return (infs, claimableList);
    }

    function claim(bytes32 _key) public returns (address, uint256){
        VData.VestingOrder storage order = vestingOrders[_key];
        require(isHandler(msg.sender) || msg.sender == order.account, "Invalid handler");
        uint256 _amount = claimable(_key);
        address _token = order.token;
        if (_amount > 0){
            order.claimed = order.claimed.add(_amount);
            _transferOut(_token, _amount, order.account);
        }
        if (block.timestamp >= order.entryTimestamp.add(order.lockDuration)){
            if (vestingOrderKeysAlive[order.account].contains(_key))
                vestingOrderKeysAlive[order.account].remove(_key);
            delete vestingOrders[_key];
        }
        return (_token, _amount);
    }

    function claimList(bytes32[] memory _keys) public {
        for(uint i = 0; i < _keys.length; i++)
            claim(_keys[i]);
    }

    function getVestingOrders(bytes32 _key) public view returns (VData.VestingOrder memory){
        VData.VestingOrder memory order = vestingOrders[_key];
        return order;
    }

    function _transferIn(address _token) private returns (uint256) {
        require(isSupportedToken(_token), "unsupported Token");
        uint256 prevBalance = balance[_token];
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        balance[_token] = nextBalance;
        return nextBalance.sub(prevBalance);
    }

    function _transferOut(address _token, uint256 _amount, address _receiver ) private {
        require(isSupportedToken(_token), "unsupported Token");
        require(balance[_token] >= _amount, "insufficient balance");
        if (_amount > 0)
            IERC20(_token).safeTransfer(_receiver, _amount);
        balance[_token] = IERC20(_token).balanceOf(address(this));
    }

    function isSupportedToken(address _token) public view returns (bool){
        return supportedTokens.contains(_token);
    }
    function getRequestKey(address _account, uint256 _index, address _token, uint256 _duration) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _index, _token, _duration));
    }
    function supportedTokenList()public view returns (address[] memory){
        return supportedTokens.valuesAt(0, supportedTokens.length());
    }
}