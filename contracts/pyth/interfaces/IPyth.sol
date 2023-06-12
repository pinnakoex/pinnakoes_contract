// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPyth {
    function updatePriceFeedsIfNecessary(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64[] calldata publishTimes
    ) external payable;
}

