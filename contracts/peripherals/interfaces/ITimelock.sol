// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITimelock {
    function signalSetGov(address _target, address _gov) external;
    function signalTransOwner(address _target, address _gov) external;
    
}
