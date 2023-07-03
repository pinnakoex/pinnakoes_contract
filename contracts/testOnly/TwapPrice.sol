// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../tokens/interfaces/IMintable.sol";
import "../oracle/interfaces/IVaultPriceFeed.sol";

interface ITreasury {
    function aum() external;
    function redeem(address _token, uint256 _amount, address _dest) external;
}

interface IPrice{
    function getTwap(address _token, uint256 _timestamp) external view returns (uint256);
    function getPriceLatest(address _token) external view returns (uint256);
    function usdToToken(address _token, uint256 _usd) external view returns (uint256);
    function tokenToUsd(address _token, uint256 _amount) external view returns (uint256);
    function usdToTokenWithPrice(address _token, uint256 _usd, uint256 _tokenPrice) external view returns (uint256);
    function tokenToUsdWithPrice(address _token, uint256 _amount, uint256 _tokenPrice) external view returns (uint256);
}
interface IInstVesting{
    function directVesting(address _account, address _token, uint256 _duration) external;
}

library RInfo {
    struct Round {
        address startPrice;
        uint256 entryTimestamp;
        uint256 bondIssued;
        uint256 roundDuration;
        uint256 roundIndex;
    }

    uint256 constant PRICE_PRECISION = 1e30;
    uint256 constant COM_PRECISION = 1000;
}



contract TwapPrice is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    address public priceFeed;

    address public pnk;
    address public pnklp;


    uint256[] public priceGraph;
    uint256[] public timePoint;

    function setAddress(address _priceFeed) external onlyOwner{
        priceFeed = _priceFeed;
    }

    function setTokens(address _pnk, address _pnklp) external onlyOwner{
        pnk = _pnk;
        pnklp = _pnklp;
    }

    function getTimeList()external view returns (uint256[] memory){
        return timePoint;
    }
    
    function setPriceGraph(uint256[] memory _price, uint256[] memory _time) external onlyOwner{
        priceGraph = _price;
        timePoint = _time;
    }


    function getPrice(uint256 _time) public view returns (uint256){
        if (_time > timePoint[0]){
            return priceGraph[0];
        }
        uint256 price = priceGraph[priceGraph.length-1];
        for(uint i = 0; i < timePoint.length-1; i++){
            if (_time <= timePoint[i] && _time >= timePoint[i+1]){
                uint256 _weight_w = timePoint[i].sub(timePoint[i+1]);
                uint256 _weight_r = _time.sub(timePoint[i+1]);

                price = priceGraph[i+1].mul(_weight_r).div(_weight_w).add(priceGraph[i].mul(_weight_w.sub(_weight_r)).div(_weight_w));
                break;
            }
        }
        return price;
    }

    function getTwap(address _token, uint256 _timestamp) public view returns (uint256){
        uint256 price = getPrice(_timestamp);
        if (_token == pnklp)
            price = price.mul(2);
        return price;
    }

    function getPriceLatest(address _token) public view returns (uint256){
        if (_token == pnk)
            return getPrice(block.timestamp);
        if (_token == pnklp)
            return getPrice(block.timestamp).mul(2);
        return IVaultPriceFeed(priceFeed).getPriceUnsafe(_token, true, true, true);
    }


    function tokenToUsd(address _token, uint256 _amount) public view returns (uint256){
        if (_token == pnk || _token == pnklp){
            return getPriceLatest(_token).mul(_amount).div(10**18);
        }
        else{
            return IVaultPriceFeed(priceFeed).tokenToUsdUnsafe(_token,_amount, false );
        }
    }

    function usdToToken(address _token, uint256 _usd) public view returns (uint256){
        if (_token == pnk || _token == pnklp){
            return _usd.mul(10**18).div(getPriceLatest(_token));
        }
        else{
            return IVaultPriceFeed(priceFeed).usdToTokenUnsafe(_token, _usd, false );
        }
    }


    function usdToTokenWithPrice(address _token, uint256 _amount, uint256 _tokenPrice) public view returns (uint256){
        if (_token == pnk || _token == pnklp){
            return _tokenPrice.mul(_amount).div(10**18);
        }
        else{
            return IVaultPriceFeed(priceFeed).tokenToUsdUnsafe(_token,_amount, false );
        }
    }

    function tokenToUsdWithPrice(address _token, uint256 _usd, uint256 _tokenPrice) public view returns (uint256){
        if (_token == pnk || _token == pnklp){
            return _usd.mul(10**18).div(_tokenPrice);
        }
        else{
            return IVaultPriceFeed(priceFeed).usdToTokenUnsafe(_token, _usd, false );
        }
    }
}

