// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IOwnable {
    function owner() external view returns (address);

    function renounceOwnership() external;

    function transferOwnership(address newOwner_) external;
}

interface IIDO {
    function withdraw(
        address _erc20,
        address _to,
        uint256 _val
    ) external ;

    function withdrawETH(address payable recipient) external ;

    function transferOwnership(address _newOwner) external;
}

contract TimelockSp  {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public constant MAX_BUFFER = 2 days;

    address internal _owner;

    uint256 public buffer = 60;

    mapping (bytes32 => uint256) public pendingActions;

    event SignalPendingAction(bytes32 action);
    event SignalWithdrawToken(address target, address token, address receiver, uint256 amount, bytes32 action);
    event SignalSetGov(address target, address gov, bytes32 action);
    event SignalWithdrawETH(address target, address receiver);
    event ClearAction(bytes32 action);
    event ProceedAction(bytes32 action);


    mapping(address => bool) public accepted;

    modifier onlyOwner() {
        require(msg.sender == _owner, "Only owner");
        _;
    }


    constructor( ) {
        _owner = msg.sender;
    }
    function owner() public view returns (address) {
        return _owner;
    }
    function setBuffer(uint256 _buffer) external onlyOwner {
        require(_buffer <= MAX_BUFFER, "Timelock: invalid _buffer");
        require(_buffer > buffer, "Timelock: buffer can not be decreased");
        buffer = _buffer;
    }


    function signalWithdrawTargetToken(address _target, address _receiver, address _token, uint256 _amount) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("withdrawTargetToken", _target, _receiver, _token, _amount));
        _setPendingAction(action);
        emit SignalWithdrawToken(_target, _token, _receiver, _amount, action);
    }
    function withdrawTargetToken(address _target, address _receiver, address _token, uint256 _amount) external  onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("withdrawTargetToken",_target,  _receiver, _token, _amount));
        _validateAction(action);
        _clearAction(action);
        IIDO(_target).withdraw(_token, _receiver, _amount);
        emit ProceedAction(action);
    }


    function signalWithdrawThisToken(address _receiver, address _token, uint256 _amount) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("withdrawThisToken", _receiver, _token, _amount));
        _setPendingAction(action);
        emit SignalWithdrawToken(address(this), _token, _receiver, _amount, action);
    }
    function withdrawThisToken(address _receiver, address _token, uint256 _amount) external onlyOwner{
        bytes32 action = keccak256(abi.encodePacked("withdrawThisToken", _receiver, _token, _amount));
        _validateAction(action);
        _clearAction(action);
        IERC20(_token).safeTransfer(_receiver, _amount);
        emit ProceedAction(action);
    }
    
    function signalSendThisValue(address _receiver,uint256 _amount) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("withdrawThisValue", _receiver, _amount));
        _setPendingAction(action);
        emit SignalWithdrawETH(address(this), _receiver);
    }
    function sendThisValue(address payable _receiver, uint256 _amount) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("withdrawThisValue", _receiver, _amount));
        _receiver.sendValue(_amount);
        emit ProceedAction(action);
    }


    function signalWithdrawTargetETH(address _target, address _receiver) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("withdrawTargetETH", _target, _receiver));
        _setPendingAction(action);
        emit SignalWithdrawETH(_target, _receiver);
    }
    function withdrawTargetETH(address _target, address payable _receiver) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("withdrawTargetETH",_target,  _receiver));
        _validateAction(action);
        _clearAction(action);
        IIDO(_target).withdrawETH(_receiver);
        emit ProceedAction(action);
    }


    function signalTransTargetOwner(address _target, address _gov) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("transTargetOwner", _target, _gov));
        _setPendingAction(action);
        emit SignalSetGov(_target, _gov, action);
    }
    function transTargetOwner(address _target, address _gov) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("transTargetOwner", _target, _gov));
        _validateAction(action);
        _clearAction(action);
        IOwnable(_target).transferOwnership(_gov);
        emit ProceedAction(action);
    }




    function signalTransTimelockOwner(address _gov) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("transTimelockOwner", address(this), _gov));
        _setPendingAction(action);
        emit SignalSetGov(address(this), _gov, action);
    } 
    function transTimelockOwner(address _gov) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("transTimelockOwner", address(this), _gov));
        _validateAction(action);
        _clearAction(action);
        require(accepted[_gov], "Not accepted");
        require(_gov != address(0), "non-zero address required");
        _owner = _gov;
        emit ProceedAction(action);
    }
    function accept() external {
        accepted[msg.sender] = true;
    }
    function deny() external {
        accepted[msg.sender] = false;
    }



    function cancelAction(bytes32 _action) external onlyOwner {
        _clearAction(_action);
    }

    function _setPendingAction(bytes32 _action) private {
        require(pendingActions[_action] == 0, "Timelock: action already signalled");
        pendingActions[_action] = block.timestamp.add(buffer);
        emit SignalPendingAction(_action);
    }

    function _validateAction(bytes32 _action) private view {
        require(pendingActions[_action] != 0, "Timelock: action not signalled");
        require(pendingActions[_action] < block.timestamp, "Timelock: action time not yet passed");
    }

    function _clearAction(bytes32 _action) private {
        require(pendingActions[_action] != 0, "Timelock: invalid _action");
        delete pendingActions[_action];
        emit ClearAction(_action);
    }
}