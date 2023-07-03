// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./VaultMSData.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultStorage.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../DID/interfaces/IPID.sol";
import "./interfaces/IPlpManager.sol";
import "../oracle/interfaces/IVaultPriceFeed.sol";

pragma solidity ^0.8.0;

contract PlpManager is IPlpManager, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours;
    
    IVault public vault;
    address public override plp;
    address public override weth;
    address public override pid;
    address public priceFeed;


    uint256 public aumAddition;
    uint256 public aumDeduction;

    mapping(address => bool) public isHandler;

    event AddLiquidity(
        address account,
        address token,
        uint256 amount,
        uint256 aumInUsdx,
        uint256 elpSupply,
        uint256 usdxAmount,
        uint256 mintAmount
    );

    event RemoveLiquidity(
        address account,
        address token,
        uint256 elpAmount,
        uint256 aumInUsdx,
        uint256 elpSupply,
        uint256 usdxAmount,
        uint256 amountOut
    );

    constructor(address _vault, address _plp, address _weth) {
        vault = IVault(_vault);
        plp = _plp;
        weth = _weth;
    }
    

    receive() external payable {
        require(msg.sender == weth, "invalid sender");
    }

    function setAdd(address _pid, address _priceFeed) external onlyOwner{
        pid = _pid;
        priceFeed = _priceFeed;
    }
    function withdrawToken(address _account, address _token,uint256 _amount) external onlyOwner{
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }

    function setAumAdjustment(uint256 _aumAddition, uint256 _aumDeduction) external onlyOwner {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }

    function addLiquidity(address _token, uint256 _amount, uint256 _minPlp, bytes[] memory _priceUpdateData) external nonReentrant payable override returns (uint256) {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_priceUpdateData);
        return _addLiquidity( _token, _amount, _minPlp);
    }

    function addLiquidityETH(uint256 _minElp, bytes[] memory _priceUpdateData) external nonReentrant payable override returns (uint256) {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_priceUpdateData);
        return _addLiquidity(address(0), msg.value, _minElp);
    }

    function _addLiquidity(address _token, uint256 _amount, uint256 _minlp) private returns (uint256) {
        uint256 _fundAmount = _amount;
        address _fundToken = _token;
        
        if (_token == address(0)){
            _fundToken = weth;
            _fundAmount = _amount;
            IWETH(weth).deposit{value: _amount}();
        }else{
            IERC20(_fundToken).safeTransferFrom(msg.sender, address(this), _fundAmount);
        }
        
        require(vault.isFundingToken(_fundToken), "[PlpManager] not supported lp token");
        require(_fundAmount > 0, "[PlpManager] invalid amount");
        IERC20(_fundToken).safeTransfer(address(vault), _fundAmount);
    
        // calculate aum before buyUSD
        uint256 aumInUSD = getAumSafe(true);
        uint256 lpSupply = IERC20(plp).totalSupply();
        uint256 usdAmount = vault.buyUSD(_fundToken);
        uint256 mintAmount = aumInUSD == 0 ? usdAmount.mul(10 ** IMintable(plp).decimals()).div(PRICE_PRECISION) : usdAmount.mul(lpSupply).div(aumInUSD);
        require(mintAmount >= _minlp, "[PlpManager] min output not satisfied");
        IMintable(plp).mint(msg.sender, mintAmount);
        IPID(pid).updateAddLiqScoreForAccount(msg.sender, address(vault), usdAmount, 0);
        emit AddLiquidity(msg.sender, _fundToken, _fundAmount, aumInUSD, lpSupply, usdAmount, mintAmount); 
        return mintAmount;
    }

    function removeLiquidity(address _tokenOut, uint256 _plpAmount, uint256 _minOut, bytes[] memory _priceUpdateData) external nonReentrant payable override returns (uint256) {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_priceUpdateData);
        return _removeLiquidity(_plpAmount,_tokenOut, _minOut);
    }

    function _removeLiquidity(uint256 _lpAmount, address _tokenOutOri, uint256 _minOut) private returns (uint256) {
        require(_lpAmount > 0, "[LpManager]: invalid lp amount");
        address _tokenOut = _tokenOutOri==address(0) ? weth : _tokenOutOri;
        require(vault.isFundingToken(_tokenOut), "[LpManager] not supported lp token");
        address _account = msg.sender;
        IERC20(plp).safeTransferFrom(_account, address(this), _lpAmount );
        
        // calculate aum before sellUSD
        uint256 aumInUSD = getAumSafe(false);
        uint256 lpSupply = IERC20(plp).totalSupply();
        uint256 usdAmount = _lpAmount.mul(aumInUSD).div(lpSupply); //30b
        IMintable(plp).burn(_lpAmount);
        uint256 amountOut = vault.sellUSD(_tokenOut, address(this), usdAmount);
        require(amountOut >= _minOut, "LpManager: insufficient output");
        
        if (_tokenOutOri == address(0)){
            IWETH(weth).withdraw(amountOut);
            payable(_account).sendValue(amountOut);
        }else{
            IERC20(_tokenOut).safeTransfer(_account, amountOut);
        }

        IPID(pid).updateAddLiqScoreForAccount(_account, address(vault), usdAmount, 100);
        emit RemoveLiquidity(_account, _tokenOut, _lpAmount, aumInUSD, lpSupply, usdAmount, amountOut);
        return amountOut;
    }

    function removeLiquidityETH(uint256 _plpAmount, bytes[] memory _priceUpdateData) external nonReentrant payable override returns (uint256) {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_priceUpdateData);
        return _removeLiquidity(  _plpAmount,address(0), 0);
    }

    function getPoolInfo() public view returns (uint256[] memory) {
        uint256[] memory poolInfo = new uint256[](4);
        poolInfo[0] = getAum(true);
        poolInfo[1] = 0;
        poolInfo[2] = IERC20(plp).totalSupply();
        poolInfo[3] = 0;
        return poolInfo;
    }


    function getPoolTokenList() public view returns (address[] memory) {
        return IVaultStorage(vault.vaultStorage()).fundingTokenList();
    }


    function getPoolTokenInfo(address _token) public view returns (uint256[] memory, int256[] memory) {
        // require(vault.whitelistedTokens(_token), "invalid token");
        // require(vault.isFundingToken(_token) || vault.isTradingToken(_token), "not )
        uint256[] memory tokenInfo_U= new uint256[](8);       
        int256[] memory tokenInfo_I = new int256[](4);       
        VaultMSData.TokenBase memory tBae = vault.getTokenBase(_token);
        VaultMSData.TradingFee memory tFee = vault.getTradingFee(_token);

        tokenInfo_U[0] = vault.totalTokenWeights() > 0 ? tBae.weight.mul(1000000).div(vault.totalTokenWeights()) : 0;
        tokenInfo_U[1] = tBae.poolAmount > 0 ? tBae.reservedAmount.mul(1000000).div(tBae.poolAmount) : 0;
        tokenInfo_U[2] = tBae.poolAmount;//vault.getTokenBalance(_token).sub(vault.feeReserves(_token)).add(vault.feeSold(_token));
        tokenInfo_U[3] = IVaultPriceFeed(priceFeed).getPriceUnsafe(_token, true, false, false);
        tokenInfo_U[4] = IVaultPriceFeed(priceFeed).getPriceUnsafe(_token, false, false, false);
        tokenInfo_U[5] = tFee.fundingRatePerSec;
        tokenInfo_U[6] = tFee.accumulativefundingRateSec;
        tokenInfo_U[7] = tFee.latestUpdateTime;

        tokenInfo_I[0] = tFee.longRatePerSec;
        tokenInfo_I[1] = tFee.shortRatePerSec;
        tokenInfo_I[2] = tFee.accumulativeLongRateSec;
        tokenInfo_I[3] = tFee.accumulativeShortRateSec;

        return (tokenInfo_U, tokenInfo_I);
    }

    function getAums() public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = getAum(true);
        amounts[1] = getAum(false);
        return amounts;
    }

    function getAumInUSD(bool maximise) public view returns (uint256) {
        return getAum(maximise);
    }

    function getAumSafe(bool maximise) public view returns (uint256) {
        address[] memory fundingTokenList = IVaultStorage(vault.vaultStorage()).fundingTokenList();
        address[] memory tradingTokenList = IVaultStorage(vault.vaultStorage()).tradingTokenList();

        uint256 aum = aumAddition;
        uint256 userShortProfits = 0;
        uint256 userLongProfits = 0;

        for (uint256 i = 0; i < fundingTokenList.length; i++) {
            address token = fundingTokenList[i];
            uint256 price = IVaultPriceFeed(priceFeed).getPrice(token, maximise, false, false);
            VaultMSData.TokenBase memory tBae = vault.getTokenBase(token);
            uint256 poolAmount = tBae.poolAmount;
            uint256 decimals = vault.tokenDecimals(token);
            poolAmount = poolAmount.mul(price).div(10 ** decimals);
            aum = aum.add(poolAmount);
        }

        aum = aum > vault.guaranteedUsd() ? aum.sub(vault.guaranteedUsd()) : 0;

        for (uint256 i = 0; i < tradingTokenList.length; i++) {
            address token = tradingTokenList[i];
            VaultMSData.TradingRec memory tradingRec = vault.getTradingRec(token);

            uint256 price = IVaultPriceFeed(priceFeed).getPriceUnsafe(token, maximise, false, false);
            uint256 shortSize = tradingRec.shortSize;
            if (shortSize > 0){
                uint256 averagePrice = tradingRec.shortAveragePrice;
                uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                uint256 delta = shortSize.mul(priceDelta).div(averagePrice);
                if (price > averagePrice) {
                    aum = aum.add(delta);
                } else {
                    userShortProfits = userShortProfits.add(delta);
                }    
            }

            uint256 longSize = tradingRec.longSize;
            if (longSize > 0){
                uint256 averagePrice = tradingRec.longAveragePrice;
                uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                uint256 delta = longSize.mul(priceDelta).div(averagePrice);
                if (price < averagePrice) {
                    aum = aum.add(delta);
                } else {
                    userLongProfits = userLongProfits.add(delta);
                }    
            }
            
            int256 unPreFee = vault.premiumFeeBalance(token);
            if (unPreFee > 0){
                aum = aum.sub(uint256(unPreFee));
            }
            else if (unPreFee < 0){
                aum = aum.add(uint256(-unPreFee));
            }
        }

        uint256 _totalUserProfits = userLongProfits.add(userShortProfits);
        aum = _totalUserProfits > aum ? 0 : aum.sub(_totalUserProfits);
        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);  
    }


    function getAum(bool maximise) public view returns (uint256) {
        address[] memory fundingTokenList = IVaultStorage(vault.vaultStorage()).fundingTokenList();
        address[] memory tradingTokenList = IVaultStorage(vault.vaultStorage()).tradingTokenList();
        uint256 aum = aumAddition;
        uint256 userShortProfits = 0;
        uint256 userLongProfits = 0;

        for (uint256 i = 0; i < fundingTokenList.length; i++) {
            address token = fundingTokenList[i];
            uint256 price = IVaultPriceFeed(priceFeed).getPriceUnsafe(token, maximise, false, false);
            VaultMSData.TokenBase memory tBae = vault.getTokenBase(token);
            uint256 poolAmount = tBae.poolAmount;
            uint256 decimals = vault.tokenDecimals(token);
            poolAmount = poolAmount.mul(price).div(10 ** decimals);
            aum = aum.add(poolAmount);
        }
        aum = aum > vault.guaranteedUsd() ? aum.sub(vault.guaranteedUsd()) : 0;

        for (uint256 i = 0; i < tradingTokenList.length; i++) {
            address token = tradingTokenList[i];
            VaultMSData.TradingRec memory tradingRec = vault.getTradingRec(token);

            uint256 price = IVaultPriceFeed(priceFeed).getPriceUnsafe(token, maximise, false, false);
            uint256 shortSize = tradingRec.shortSize;
            if (shortSize > 0){
                uint256 averagePrice = tradingRec.shortAveragePrice;
                uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                uint256 delta = shortSize.mul(priceDelta).div(averagePrice);
                if (price > averagePrice) {
                    aum = aum.add(delta);
                } else {
                    userShortProfits = userShortProfits.add(delta);
                }    
            }

            uint256 longSize = tradingRec.longSize;
            if (longSize > 0){
                uint256 averagePrice = tradingRec.longAveragePrice;
                uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                uint256 delta = longSize.mul(priceDelta).div(averagePrice);
                if (price < averagePrice) {
                    aum = aum.add(delta);
                } else {
                    userLongProfits = userLongProfits.add(delta);
                }    
            }

            int256 unPreFee = vault.premiumFeeBalance(token);
            if (unPreFee > 0){
                aum = aum.sub(uint256(unPreFee));
            }
            else if (unPreFee < 0){
                aum = aum.add(uint256(-unPreFee));
            }
        }

        uint256 _totalUserProfits = userLongProfits.add(userShortProfits);
        aum = _totalUserProfits > aum ? 0 : aum.sub(_totalUserProfits);
        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);  
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "PlpManager: forbidden");
    }
}

