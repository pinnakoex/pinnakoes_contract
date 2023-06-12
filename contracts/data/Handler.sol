// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../utils/EnumerableValues.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract Handler is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private handler;
    EnumerableSet.AddressSet private manager;
  
    modifier onlyHandler() {
        require(handler.contains(msg.sender), "forbidden hadler");
        _;
    }
    modifier onlyManager() {
        require(manager.contains(msg.sender), "forbidden hadler");
        _;
    }

    function isHandler(address _account) public view returns (bool){
        return handler.contains(_account);
    }
    function setHandler(address _handler, bool _state) external onlyOwner{
        if (_state){
            if (!handler.contains(_handler))
                handler.add(_handler);
        }
        else{
            if (handler.contains(_handler))
                handler.remove(_handler);
        }
    }
    function allHandlers() external view returns (address[] memory) {
        return handler.valuesAt(0, handler.length());
    }


    function isManager(address _account) public view returns (bool){
        return manager.contains(_account);
    }

    function setManager(address _manager, bool _state) external onlyOwner{
        if (_state){
            if (!manager.contains(_manager))
                manager.add(_manager);
        }
        else{
            if (manager.contains(_manager))
                manager.remove(_manager);
        }
    }

    function allManagers() external view returns (address[] memory) {
        return manager.valuesAt(0, manager.length());
    }
}
