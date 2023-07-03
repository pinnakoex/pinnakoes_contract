// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVaultPriceFeed {   
    function getPrimaryPrice(address _token) external view  returns (uint256, bool, uint256);
    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints,uint256 _priceSpreadBasisMax, uint256 _priceSpreadTimeStart, uint256 _priceSpreadTimeMax) external;
    function getPrice(address _token, bool _maximise,bool,bool) external view returns (uint256);
    function getPriceWithTime(address _token, bool _maximise) external view returns (uint256, uint256);

    function getPriceUnsafe(address _token, bool _maximise, bool, bool _adjust) external view returns (uint256);
    function priceTime(address _token) external view returns (uint256);
    function priceVariancePer1Million(address _token) external view returns (uint256); //100 for 1%
    function getPriceSpreadImpactFactor(address _token) external view returns (uint256, uint256); 
    function tokenToUsdUnsafe(address _token, uint256 _tokenAmount, bool _max) external view returns (uint256);
    function usdToTokenUnsafe( address _token, uint256 _usdAmount, bool _max ) external view returns (uint256);

    function updatePriceFeedsIfNecessary(bytes[] memory updateData, bytes32[] memory priceIds, uint64[] memory publishTimes) payable external;
    function updatePriceFeedsIfNecessaryTokens(bytes[] memory updateData, address[] memory _tokens, uint64[] memory publishTimes) payable external;
    function updatePriceFeeds(bytes[] memory updateData) payable external;
    function updatePriceFeedsIfNecessaryTokensSt(bytes[] memory updateData, address[] memory _tokens) payable external;
    function getUpdateFee(bytes[] memory _data) external view returns(uint256);
}
