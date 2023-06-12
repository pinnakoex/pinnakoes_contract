// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../utils/EnumerableValues.sol";

import "./interfaces/IVault.sol";
import "./BasePositionManager.sol";

contract PositionRouter is BasePositionManager {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableValues for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;

    struct IncreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 amountIn;
        uint256 minOut;
        uint256 sizeDelta;
        bool isLong;
        uint256 acceptablePrice;
        uint256 blockNumber;
        uint256 blockTime;
        bool hasCollateralInETH;        
        uint256 executionFee;
    }

    struct DecreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        address receiver;
        uint256 acceptablePrice;
        uint256 minOut;
        uint256 blockNumber;
        uint256 blockTime;
        bool withdrawETH;
        uint256 executionFee;
    }

    uint256 public maxTimeDelay;

    EnumerableSet.Bytes32Set internal increasePositionRequestKeys;
    EnumerableSet.Bytes32Set internal decreasePositionRequestKeys;
    EnumerableSet.AddressSet internal positionKeeper;

    mapping (address => uint256) public increasePositionsIndex;
    mapping (bytes32 => IncreasePositionRequest) public increasePositionRequests;

    mapping (address => uint256) public decreasePositionsIndex;
    mapping (bytes32 => DecreasePositionRequest) public decreasePositionRequests;



    event CreateIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 index,
        uint256 blockNumber,
        uint256 blockTime,
        uint256 gasPrice,
        uint256 executionFee
    );

    event ExecuteIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 blockGap,
        uint256 timeGap
    );

    event CancelIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event CreateDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 index,
        uint256 blockNumber,
        uint256 blockTime,
        uint256 executionFee
    );

    event ExecuteDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event CancelDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 blockGap,
        uint256 timeGap
    );

    event SetPositionKeeper(address indexed account, bool isActive);
    event SetDelayValues(uint256 minBlockDelayKeeper, uint256 minTimeDelayPublic, uint256 maxTimeDelay);
    event ExecuteDecreaseError(bytes32 key, string errMsg);
    event ExecuteIncreaseError(bytes32 key, string errMsg);

    modifier onlyPositionKeeper() {
        require(msg.sender == address(this) || isPositionKeeper(msg.sender), "PositionRouter: forbidden executor");
        _;
    }
    
    function setPositionKeeper(address _account, bool _isActive) external onlyOwner {
        if (_isActive && !positionKeeper.contains(_account)){
            positionKeeper.add(_account);
        }
        else if (!_isActive && positionKeeper.contains(_account)){
            positionKeeper.remove(_account);
        }
        emit SetPositionKeeper(_account, _isActive);
    }

    function setMaxTimeDelay(uint256 _maxTimeDelay) external onlyHandler {
        maxTimeDelay = _maxTimeDelay;
    }
    


    //- Public Functions for user trading
    function createIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice
    ) external payable nonReentrant {
        _validFee();
        require(_path.length == 1 || _path.length == 2, "PositionRouter: invalid _path length");
        _transferInETH();
        _transfer(_path[0], msg.sender, address(this), _amountIn);
        _createIncreasePosition( msg.sender, _path, _indexToken, _amountIn, _minOut, _sizeDelta, _isLong, _acceptablePrice, false, msg.value);
    }

    function createIncreasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice
    ) external payable nonReentrant {
        _validFee();
        require(_path.length == 1 || _path.length == 2, "PositionRouter: invalid _path length");
        require(_path[0] == weth, "PositionRouter: invalid _path");
        _transferInETH();
        uint256 amountIn = msg.value.sub(minExecutionFee);
        require(amountIn > 0, "out of amount");
        _createIncreasePosition(
            msg.sender,
            _path,
            _indexToken,
            amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            true,
            minExecutionFee
        );
    }

    function createDecreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _minOut,
        bool _withdrawETH
    ) external payable nonReentrant {
        _validFee();
        require(_path.length == 1 || _path.length == 2, "PositionRouter: invalid _path length");
        if (_withdrawETH) {
            require(_path[_path.length - 1] == weth, "PositionRouter: invalid _path");
        }
        _transferInETH();
        _createDecreasePosition(
            msg.sender,
            _path,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _receiver,
            _acceptablePrice,
            _minOut,
            _withdrawETH,
            msg.value
        );
    }

    function cancelIncreasePosition(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        IncreasePositionRequest memory request = increasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeIncreasePositions loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        bool shouldCancel = _validateCancellation(request.blockNumber, request.blockTime, request.account);
        if (!shouldCancel) { return false; }

        delete increasePositionRequests[_key];

        if (request.hasCollateralInETH) {
            _transferOutETH(request.amountIn, payable(request.account));
        } else {
            IERC20(request.path[0]).safeTransfer(request.account, request.amountIn);
        }

       _transferOutETH(request.executionFee, _executionFeeReceiver);

        emit CancelIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountIn,
            request.minOut,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.executionFee,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );

        return true;
    }

    function cancelDecreasePosition(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeDecreasePositions loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        bool shouldCancel = _validateCancellation(request.blockNumber, request.blockTime, request.account);
        if (!shouldCancel) { return false; }

        delete decreasePositionRequests[_key];

       _transferOutETH(request.executionFee, _executionFeeReceiver);

        emit CancelDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.minOut,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );

        return true;
    }






    //- Functions for position keepers

    function executeIncreasePositions(uint256 _endIndex, address payable _executionFeeReceiver) external onlyPositionKeeper {
        bytes32[] memory keyList = getIncreasePositionRequestKeys();
        if (keyList.length < 1) { return; }
        uint256 endId = _endIndex < keyList.length ? _endIndex : keyList.length;
        for(uint256 key_idx = 0; key_idx < endId; key_idx++ ){
            bytes32 key = keyList[key_idx];
            try this.executeIncreasePosition(key, _executionFeeReceiver) returns (bool _wasExecuted) {
                if (!_wasExecuted) { continue; }
            } catch Error(string memory _errMsg){
                emit ExecuteIncreaseError(key, _errMsg);
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try this.cancelIncreasePosition(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) { continue; }
                } catch {}
            } catch {
                emit ExecuteIncreaseError(key, "no str Reason");
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try this.cancelIncreasePosition(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) { continue; }
                } catch {}
            }
            increasePositionRequestKeys.remove(key);
        }
    }


    function executeDecreasePositions(uint256 _endIndex, address payable _executionFeeReceiver) external onlyPositionKeeper {
        bytes32[] memory keyList = getDecreasePositionRequestKeys();
        if (keyList.length < 1) { return; }
        uint256 endId = _endIndex < keyList.length ? _endIndex : keyList.length;

        for(uint256 key_idx = 0; key_idx < endId; key_idx++ ){
            bytes32 key = keyList[key_idx];
            try this.executeDecreasePosition(key, _executionFeeReceiver) returns (bool _wasExecuted) {
                if (!_wasExecuted) { continue; }
            } catch Error(string memory _errMsg){
                emit ExecuteIncreaseError(key, _errMsg);
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try this.cancelDecreasePosition(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) { continue; }
                } catch {}
            } catch {
                emit ExecuteIncreaseError(key, "no str Reason");
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try this.cancelDecreasePosition(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) { continue; }
                } catch {}
            }
            increasePositionRequestKeys.remove(key);
        }
    }


    function executeIncreasePosition(bytes32 _key, address payable _executionFeeReceiver) public onlyPositionKeeper returns (bool) {
        IncreasePositionRequest memory request = increasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeIncreasePositions loop will continue executing the next request
        if (request.account == address(0)) { return true; }
        bool shouldExecute = _validateExecution(request.blockNumber, request.blockTime, request.account);
        if (!shouldExecute) { return false; }

        delete increasePositionRequests[_key];

        if (request.amountIn > 0) {
            uint256 amountIn = request.amountIn;

            if (request.path.length > 1) {
                IERC20(request.path[0]).safeTransfer(address(vault), request.amountIn);
                amountIn = _swap(request.path, request.minOut, address(this));
            }

            IERC20(request.path[request.path.length - 1]).safeTransfer(address(vault), amountIn);
        }

        _increasePosition(request.account, request.path[request.path.length - 1], request.indexToken, request.sizeDelta, request.isLong, request.acceptablePrice);
        _transferOutETH(request.executionFee, _executionFeeReceiver);

        emit ExecuteIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountIn,
            request.minOut,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );

        return true;
    }

    function executeDecreasePosition(bytes32 _key, address payable _executionFeeReceiver) public onlyPositionKeeper returns (bool) {
        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeDecreasePositions loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        bool shouldExecute = _validateExecution(request.blockNumber, request.blockTime, request.account);
        if (!shouldExecute) {return false; }

        delete decreasePositionRequests[_key];

        uint256 amountOut = _decreasePosition(request.account, request.path[0], request.indexToken, request.collateralDelta, request.sizeDelta, request.isLong, address(this), request.acceptablePrice);


        if (request.path.length > 1) {
            IERC20(request.path[0]).safeTransfer(address(vault), amountOut);
            amountOut = _swap(request.path, request.minOut, address(this));
        }

        if (request.withdrawETH) {
           _transferOutETH(amountOut, payable(request.receiver));
        } else {
            IERC20(request.path[request.path.length - 1]).safeTransfer(request.receiver, amountOut);
        }

       _transferOutETH(request.executionFee, _executionFeeReceiver);
        

        emit ExecuteDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.minOut,
            request.executionFee,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );

        return true;
    }



    //- Functions internal
    function _validateExecution(uint256 /*_positionBlockNumber*/, uint256 _positionBlockTime, address /*_account*/) internal view returns (bool) {
        if (_positionBlockTime.add(maxTimeDelay) <= block.timestamp) {
            revert("PositionRouter: request has expired");
        }
        return true;
    }

    function _validateCancellation(uint256 /*_positionBlockNumber*/, uint256 _positionBlockTime, address _account) internal view returns (bool) {
        // if (msg.sender == _account){
        //     require(_positionBlockTime.add(minTimeDelayPublic) <= block.timestamp, "PositionRouter: min delay not yet passed");
        // } 
        return  msg.sender == _account ||  msg.sender == address(this) || isPositionKeeper(msg.sender);
    }


    function _createIncreasePosition(
        address _account,
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        bool _hasCollateralInETH,
        uint256 _executionFee
    ) internal {
        uint256 index = increasePositionsIndex[_account].add(1);
        increasePositionsIndex[_account] = index;

        IncreasePositionRequest memory request = IncreasePositionRequest(
            _account,
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            block.number,
            block.timestamp,
            _hasCollateralInETH,
            _executionFee
        );

        bytes32 key = getRequestKey(_account, index);
        increasePositionRequests[key] = request;
        increasePositionRequestKeys.add(key);
        emit CreateIncreasePosition(
            _account,
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            index,
            block.number,
            block.timestamp,
            tx.gasprice,
            _executionFee
        );
    }

    function _createDecreasePosition(
        address _account,
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _minOut,
        bool _withdrawETH,
        uint256 _executionFee
    ) internal {
        uint256 index = decreasePositionsIndex[_account].add(1);
        decreasePositionsIndex[_account] = index;

        DecreasePositionRequest memory request = DecreasePositionRequest(
            _account,
            _path,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _receiver,
            _acceptablePrice,
            _minOut,
            block.number,
            block.timestamp,
            _withdrawETH,
            _executionFee
        );

        bytes32 key = getRequestKey(_account, index);
        decreasePositionRequests[key] = request;

        decreasePositionRequestKeys.add(key);

        emit CreateDecreasePosition(
            _account,
            _path,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _receiver,
            _acceptablePrice,
            _minOut,
            index,
            block.number,
            block.timestamp,
            _executionFee
        );
    }


    function _validFee( ) internal {
        require(msg.value == minExecutionFee, "PositionRouter: invalid msg.value");
    }








    //========================== public view functions
    function getRequestKey(address _account, uint256 _index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _index));
    }

    function getIncreasePositionRequest(bytes32 _key) public view returns (IncreasePositionRequest memory) {
        return increasePositionRequests[_key];
    }

    function getDecreasePositionRequest(bytes32 _key) public view returns (DecreasePositionRequest memory) {
        return decreasePositionRequests[_key];
    }

    function isPositionKeeper(address _account) public view returns (bool){
        return positionKeeper.contains(_account);
    }

    function getPositilnKeepList() public view returns (address[] memory){
        return positionKeeper.valuesAt(0, positionKeeper.length());
    }

    function getIncreasePositionRequestKeys() public view returns (bytes32[] memory){
        return increasePositionRequestKeys.valuesAt(0, increasePositionRequestKeys.length());
    }

    function getDecreasePositionRequestKeys() public view returns (bytes32[] memory){
        return decreasePositionRequestKeys.valuesAt(0, decreasePositionRequestKeys.length());
    }

    function pendingIncreasePositions( ) public view returns (uint256){
        return increasePositionRequestKeys.length();
    }

    function pendingDecreasePositions( ) public view returns (uint256){
        return decreasePositionRequestKeys.length();
    }

    function isIncreaseKeyAlive(bytes32 _key) public view returns (bool){
        return increasePositionRequestKeys.contains(_key);
    }
    function isDecreaseKeyAlive(bytes32 _key) public view returns (bool){
        return decreasePositionRequestKeys.contains(_key);
    }
}
