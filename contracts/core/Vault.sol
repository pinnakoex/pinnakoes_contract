// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../tokens/interfaces/IMintable.sol";
import "../utils/EnumerableValues.sol";
import "./VaultMSData.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";
import "../oracle/interfaces/IVaultPriceFeed.sol";
import "./interfaces/IVaultStorage.sol";
import "../DID/interfaces/IPID.sol";
import "../fee/interfaces/IUserFeeResv.sol";

contract Vault is IVault, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableValues for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;

    uint8 public override baseMode;

    IPID public pid;
    IVaultUtils public vaultUtils;
    address public override vaultStorage;
    address public override priceFeed;
    address public feeRouter;
    address public userFeeResv;
    address public feeOutToken;

    mapping(address => bool) public override isManager;
    mapping(address => bool) public override approvedRouters;

    uint256 public override totalTokenWeights;
    EnumerableSet.AddressSet tradingTokens;
    EnumerableSet.AddressSet fundingTokens;
    EnumerableSet.AddressSet allTokens;
    mapping(address => VaultMSData.TokenBase) tokenBase;
    uint256 public override guaranteedUsd;

    mapping(address => VaultMSData.TradingFee) tradingFee;
    mapping(bytes32 => VaultMSData.Position) positions;
    mapping(address => VaultMSData.TradingRec) tradingRec;
    mapping(address => int256) override premiumFeeBalance;
    uint256 public override globalShortSize;
    uint256 public override globalLongSize;


    modifier onlyManager() {
        _validate(isManager[msg.sender], 4);
        _;
    }

    event Swap(address account, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, uint256 amountOutAfterFees, uint256 feeBasisPoints);
    event IncreasePosition(bytes32 key, address account, address collateralToken, address indexToken, uint256 collateralDelta, uint256 sizeDelta,bool isLong, uint256 price, uint256 fee);
    event DecreasePosition(bytes32 key, VaultMSData.Position position, uint256 collateralDelta, uint256 sizeDelta, uint256 price, int256 fee, uint256 usdOut, uint256 latestCollatral, uint256 prevCollateral);
    event DecreasePositionTransOut( bytes32 key,uint256 transOut);
    event LiquidatePosition(bytes32 key, address account, address collateralToken, address indexToken, bool isLong, uint256 size, uint256 collateral, uint256 reserveAmount, int256 realisedPnl, uint256 markPrice);
    event UpdatePosition(bytes32 key, address account, uint256 size,  uint256 collateral, uint256 averagePrice, uint256 entryFundingRate, uint256 reserveAmount, int256 realisedPnl, uint256 markPrice);
    event ClosePosition(bytes32 key, address account, uint256 size, uint256 collateral, uint256 averagePrice, uint256 entryFundingRate, uint256 reserveAmount, int256 realisedPnl);
    event UpdateFundingRate(address token, uint256 fundingRate);
    event UpdatePnl(bytes32 key, bool hasProfit, uint256 delta, uint256 currentSize, uint256 currentCollateral, uint256 usdOut, uint256 usdOutAfterFee);
    event CollectSwapFees(address token, uint256 feeUsd, uint256 feeTokens);
    event CollectMarginFees(address token, uint256 feeUsd, uint256 feeTokens, uint256 feeTokenDisc);
    event DirectPoolDeposit(address token, uint256 amount);
    event IncreasePoolAmount(address token, uint256 amount);
    event DecreasePoolAmount(address token, uint256 amount);
    event IncreaseReservedAmount(address token, uint256 amount);
    event DecreaseReservedAmount(address token, uint256 amount);
    event IncreaseGuaranteedUsd(address token, uint256 amount);
    event DecreaseGuaranteedUsd(address token, uint256 amount);
    // event PayTax(address _account, bytes32 _key, uint256 profit, uint256 usdTax);
    // event UpdateGlobalSize(address _indexToken, uint256 tokenSize, uint256 globalSize, uint256 averagePrice, bool _increase, bool _isLong );
    event CollectPremiumFee(address account,uint256 _size, int256 _entryPremiumRate, int256 _premiumFeeUSD);
    event SetManager(address account, bool state);
    event SetRouter(address account, bool state);
    event SetTokenConfig(address _token, uint256 _tokenWeight, bool _isStable, bool _isFundingToken, bool _isTradingToken);
    event ClearTokenConfig(address _token, bool del);

    constructor(uint8 _baseMode) {
        baseMode = _baseMode;
    }

    // ---------- owner setting part ----------
    function setAdd(address[] memory _addList) external override onlyOwner{
        vaultUtils = IVaultUtils(_addList[0]);
        vaultStorage = _addList[1];
        pid = IPID(_addList[2]);
        priceFeed = _addList[3];
        feeRouter = _addList[4];
        userFeeResv = _addList[5];
        feeOutToken = _addList[6];
    }

    function setManager(address _manager, bool _isManager) external override onlyOwner{
        isManager[_manager] = _isManager;
        emit SetManager(_manager, _isManager);
    }

    function setRouter(address _router, bool _status) external override onlyOwner{
        approvedRouters[_router] = _status;
        emit SetRouter(_router, _status);
    }

    function setTokenConfig(address _token, uint256 _tokenWeight, bool _isStable, bool _isFundingToken, bool _isTradingToken) external override onlyOwner{
        if (!allTokens.contains(_token)){
            allTokens.add(_token);
        }
        if (_isTradingToken && !tradingTokens.contains(_token)) {
            tradingTokens.add(_token);
        }
        if (_isFundingToken && !fundingTokens.contains(_token)) {
            fundingTokens.add(_token);
        }
        VaultMSData.TokenBase storage tBase = tokenBase[_token];
        
        if (_isFundingToken){
            totalTokenWeights = totalTokenWeights.add(_tokenWeight).sub(tBase.weight);
            tBase.weight = _tokenWeight;
        }
        else
            tBase.weight = 0;

        tBase.isStable = _isStable;
        tBase.isFundable = _isFundingToken;
        getMaxPrice(_token);// validate price feed
        emit SetTokenConfig(_token, _tokenWeight, _isStable, _isFundingToken, _isTradingToken);
    }

    function clearTokenConfig(address _token, bool _del) external onlyOwner{
        if (tradingTokens.contains(_token)) {
            tradingTokens.remove(_token);
        }
        if (fundingTokens.contains(_token)) {
            totalTokenWeights = totalTokenWeights.sub(tokenBase[_token].weight);
            fundingTokens.remove(_token);
        } 
        if (allTokens.contains(_token)){
            allTokens.remove(_token);
        } 
        if (_del)
            delete tokenBase[_token];
        emit ClearTokenConfig(_token, _del);
    }
    // the governance controlling this function should have a timelock
    function upgradeVault(address _newVault, address _token, uint256 _amount) external onlyOwner{
        IERC20(_token).safeTransfer(_newVault, _amount);
    }
    //---------- END OF owner setting part ----------



    //---------- FUNCTIONS FOR MANAGER ----------
    function buyUSD(address _token) external override onlyManager returns (uint256) {
        _validate(fundingTokens.contains(_token), 16);
        updateRate(_token);//update first to calculate fee
        uint256 tokenAmount = _transferIn(_token);
        _validate(tokenAmount > 0, 17);
        _increasePoolAmount(_token, tokenAmount);
        
        uint256 feeBasisPoints = vaultUtils.getBuyLpFeeBasisPoints(_token, tokenToUsdMin(_token, tokenAmount));
        uint256 amountAfterFees = _collectSwapFees(_token, tokenAmount, feeBasisPoints);
        updateRate(_token);//update first to calculate fee

        return tokenToUsdMin(_token, amountAfterFees);
    }

    function sellUSD(address _token, address _receiver,  uint256 _usdAmount) external override onlyManager returns (uint256) {
        _validate(fundingTokens.contains(_token), 19);
        _validate(_usdAmount > 0, 20);
        updateRate(_token);
        uint256 redemptionAmount = usdToTokenMin(_token, _usdAmount);
        _validate(redemptionAmount > 0, 21);
        uint256 feeBasisPoints = vaultUtils.getSellLpFeeBasisPoints(_token, _usdAmount);
        uint256 amountOut = _collectSwapFees(_token, redemptionAmount, feeBasisPoints);
        _validate(amountOut > 0, 22);
        _decreasePoolAmount(_token, amountOut);
        _transferOut(_token, amountOut, _receiver);
        updateRate(_token);//update first to calculate fee

        return amountOut;
    }


    //---------------------------------------- TRADING FUNCTIONS --------------------------------------------------
    function swap(address _tokenIn,  address _tokenOut, address _receiver ) external override returns (uint256) {
        _validate(approvedRouters[msg.sender], 41);
        return _swap(_tokenIn, _tokenOut, _receiver );
    }

    function increasePosition(address _account, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) external override {
        _validate(approvedRouters[msg.sender], 41);
        
        //update cumulative funding rate
        updateRate(_collateralToken);
        if (_indexToken!= _collateralToken) updateRate(_indexToken);

        bytes32 key = vaultUtils.getPositionKey( _account, _collateralToken, _indexToken, _isLong, 0);
        VaultMSData.Position storage position = positions[key];
        vaultUtils.validateIncreasePosition(_collateralToken, _indexToken, position.size, _sizeDelta ,_isLong);

        uint256 price = _isLong ? getMaxPrice(_indexToken) : getMinPrice(_indexToken);
        price = vaultUtils.getImpactedPrice(_indexToken, 
            _sizeDelta.add(_isLong ? tradingRec[_indexToken].longSize : tradingRec[_indexToken].shortSize), price, _isLong);
            
        if (position.size == 0) {
            position.account = _account;
            position.averagePrice = price;
            position.aveIncreaseTime = block.timestamp;
            position.collateralToken = _collateralToken;
            position.indexToken = _indexToken;
            position.isLong = _isLong;       
        }
        else if (position.size > 0 && _sizeDelta > 0) {
            position.aveIncreaseTime = vaultUtils.getNextIncreaseTime(position.aveIncreaseTime, position.size, _sizeDelta); 
            position.averagePrice = vaultUtils.getPositionNextAveragePrice(position.size, position.averagePrice, price, _sizeDelta, true);
        }
        uint256 collateralDelta = _transferIn(_collateralToken);
        uint256 collateralDeltaUsd = tokenToUsdMin(_collateralToken, collateralDelta);
        position.collateral = position.collateral.add(collateralDeltaUsd);
        position.accCollateral = position.accCollateral.add(collateralDeltaUsd);
        _increaseGuaranteedUsd(_collateralToken, collateralDeltaUsd);
        _increasePoolAmount(_collateralToken,  collateralDelta);//aum = pool + aveProfit - guaranteedUsd
        
        //call updateRate before collect Margin Fees
        uint256 fee = _collectMarginFees(key, _sizeDelta); //increase collateral before collectMarginFees
        position.lastUpdateTime = block.timestamp;//attention: after _collectMarginFees
        
        // run after collectMarginFees
        position.entryFundingRateSec = tradingFee[_collateralToken].accumulativefundingRateSec;
        position.entryPremiumRateSec = _isLong ? tradingFee[_indexToken].accumulativeLongRateSec : tradingFee[_indexToken].accumulativeShortRateSec;

        position.size = position.size.add(_sizeDelta);
        _validate(position.size > 0, 30);
        _validatePosition(position.size, position.collateral);

        vaultUtils.validateLiquidation(key, true);

        // reserve tokens to pay profits on the position
        {
            uint256 reserveDelta = vaultUtils.getReserveDelta(position.collateralToken, position.size, position.collateral, position.takeProfitRatio);
            if (position.reserveAmount > 0)
                _decreaseReservedAmount(_collateralToken, position.reserveAmount);
            _increaseReservedAmount(_collateralToken, reserveDelta);
            position.reserveAmount = reserveDelta;
        }
       
        _updateGlobalSize(_isLong, _indexToken, _sizeDelta, price, true);
    
        //update rates according to latest positions and token utilizations
        updateRate(_collateralToken);
        if (_indexToken!= _collateralToken) updateRate(_indexToken);            
        
        IVaultStorage(vaultStorage).addKey(_account,key);
        emit IncreasePosition(key, _account, _collateralToken, _indexToken, collateralDeltaUsd,
            _sizeDelta, _isLong, price, fee);
        emit UpdatePosition( key, _account, position.size, position.collateral, position.averagePrice,
            position.entryFundingRateSec.mul(3600).div(1000000), position.reserveAmount, position.realisedPnl, price );
    }

    function decreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver
        ) external override returns (uint256) {
        _validate(approvedRouters[msg.sender], 41);
        bytes32 key = vaultUtils.getPositionKey(_account, _collateralToken, _indexToken, _isLong, 0);
        return _decreasePosition(key, _collateralDelta, _sizeDelta, _receiver);
    }

    function _decreasePosition(bytes32 key, uint256 _collateralDelta, uint256 _sizeDelta, address _receiver) private returns (uint256) {
        // bytes32 key = vaultUtils.getPositionKey(_account, _collateralToken, _indexToken, _isLong, 0);
        VaultMSData.Position storage position = positions[key];
        vaultUtils.validateDecreasePosition(position,_sizeDelta, _collateralDelta);
        _updateGlobalSize(position.isLong, position.indexToken, _sizeDelta, position.averagePrice, false);
        uint256 collateral = position.collateral;
        updateRate(position.collateralToken);
        if (position.indexToken!= position.collateralToken) updateRate(position.indexToken); 
        uint256 price = position.isLong ? getMinPrice(position.indexToken) : getMaxPrice(position.indexToken);
        // _collectMarginFees runs inside _reduceCollateral
        (uint256 usdOut, uint256 usdOutAfterFee) = _reduceCollateral(key, _collateralDelta, _sizeDelta, price);
        // scrop variables to avoid stack too deep errors
        {
            uint256 reserveDelta = vaultUtils.getReserveDelta(position.collateralToken, position.size.sub(_sizeDelta), position.collateral.sub(_collateralDelta), position.takeProfitRatio);
            _decreaseReservedAmount(position.collateralToken, position.reserveAmount);
            if (reserveDelta > 0) _increaseReservedAmount(position.collateralToken, reserveDelta);
            position.reserveAmount = reserveDelta;//position.reserveAmount.sub(reserveDelta);
        }

        // update position entry rate
        position.lastUpdateTime = block.timestamp;  //attention: MUST run after _collectMarginFees (_reduceCollateral)
        position.entryFundingRateSec = tradingFee[position.collateralToken].accumulativefundingRateSec;
        position.entryPremiumRateSec = position.isLong ? tradingFee[position.indexToken].accumulativeLongRateSec : tradingFee[position.indexToken].accumulativeShortRateSec;
        bool _del = false;
        // scrop variables to avoid stack too deep errors
        {
            //do not add spread price impact in decrease position
            emit DecreasePosition( key, position, _collateralDelta, _sizeDelta, price, int256(usdOut) - int256(usdOutAfterFee), usdOut, position.collateral, collateral);
            if (position.size != _sizeDelta) {
                // position.entryFundingRateSec = tradingFee[_collateralToken].accumulativefundingRateSec;
                position.size = position.size.sub(_sizeDelta);
                _validatePosition(position.size, position.collateral);
                vaultUtils.validateLiquidation(key,true);
                emit UpdatePosition(key, position.account, position.size, position.collateral, position.averagePrice, position.entryFundingRateSec,
                    position.reserveAmount, position.realisedPnl, price);
            } else {
                emit ClosePosition(key, position.account,
                    position.size, position.collateral,position.averagePrice, position.entryFundingRateSec.mul(3600).div(1000000), position.reserveAmount, position.realisedPnl);
                _decreaseReservedAmount(position.collateralToken, position.reserveAmount);
                position.size = 0;
                _del = true;
            }
        }
        // update global trading size and average prie
        // _updateGlobalSize(position.isLong, position.indexToken, position.size, position.averagePrice, true);

        updateRate(position.collateralToken);
        if (position.indexToken!= position.collateralToken) updateRate(position.indexToken);

        if (usdOutAfterFee > 0) {
            uint256 tkOutAfterFee = 0;
            tkOutAfterFee = usdToTokenMin(position.collateralToken, usdOutAfterFee);
            emit DecreasePositionTransOut(key, tkOutAfterFee);
            _transferOut(position.collateralToken, tkOutAfterFee, _receiver);
            usdOutAfterFee = tkOutAfterFee;
        }
        if (_del) _delPosition(position.account, key);
        return usdOutAfterFee;
    }



    function liquidatePosition(address _account, address _collateralToken, address _indexToken, bool _isLong, address _feeReceiver) external override {
        vaultUtils.validLiq(msg.sender);
        updateRate(_collateralToken);
        if (_indexToken!= _collateralToken) updateRate(_indexToken);
        bytes32 key = vaultUtils.getPositionKey(_account, _collateralToken, _indexToken, _isLong, 0);

        VaultMSData.Position memory position = positions[key];
        _validate(position.size > 0, 35);

        (uint256 liquidationState, uint256 marginFees, int256 idxFee) = vaultUtils.validateLiquidation(key, false);
        _validate(liquidationState != 0, 36);
        if (liquidationState > 1) {
            // max leverage exceeded or max takingProfitLine reached
            _decreasePosition(key, 0, position.size, position.account);
            return;
        }

        {
            uint256 liqMarginFeeUsd = position.collateral;
            if (idxFee >= 0){
                liqMarginFeeUsd = liqMarginFeeUsd.add(uint256(idxFee));
            }else{
                liqMarginFeeUsd = liqMarginFeeUsd > uint256(-idxFee) ? liqMarginFeeUsd.sub(uint256(-idxFee)) : 0;
            }
            
            liqMarginFeeUsd = liqMarginFeeUsd > marginFees ? marginFees : 0;
            _collectFeeResv(_account, feeOutToken, liqMarginFeeUsd);
        }

        uint256 markPrice = _isLong ? getMinPrice(_indexToken)  : getMaxPrice(_indexToken);
        emit LiquidatePosition(key, _account,_collateralToken,_indexToken,_isLong,
            position.size, position.collateral, position.reserveAmount, position.realisedPnl, markPrice);

        // if (!_isLong && marginFees < position.collateral) {
        // if ( marginFees < position.collateral) {
        //     uint256 remainingCollateral = position.collateral.sub(marginFees);
        //     remainingCollateral = usdToTokenMin(_collateralToken, remainingCollateral);
        //     _increasePoolAmount(_collateralToken,  remainingCollateral);
        // }

        _decreaseReservedAmount(_collateralToken, position.reserveAmount);
        _updateGlobalSize(_isLong, _indexToken, position.size, position.averagePrice, false);
        _decreaseGuaranteedUsd(_collateralToken, position.collateral);
        _decreasePoolAmount(_collateralToken, usdToTokenMin(_collateralToken, vaultUtils.liquidationFeeUsd()));
        _transferOut(_collateralToken, usdToTokenMin(_collateralToken, vaultUtils.liquidationFeeUsd()), _feeReceiver);

        _delPosition(_account, key);

        updateRate(_collateralToken);
        if (_indexToken!= _collateralToken) updateRate(_indexToken);
        
    }
    
    //---------- PUBLIC FUNCTIONS ----------
    function directPoolDeposit(address _token) external override {
        _validate(fundingTokens.contains(_token), 14);
        uint256 tokenAmount = _transferIn(_token);
        _validate(tokenAmount > 0, 15);
        _increasePoolAmount(_token, tokenAmount);
        emit DirectPoolDeposit(_token, tokenAmount);
    }
    function tradingTokenList() external view override returns (address[] memory) {
        return tradingTokens.valuesAt(0, tradingTokens.length());
    }
    function fundingTokenList() external view override returns (address[] memory) {
        return fundingTokens.valuesAt(0, fundingTokens.length());
    }
    function getMaxPrice(address _token) public view override returns (uint256) {
        return IVaultPriceFeed(priceFeed).getPrice(_token, true, false, false);
    }
    function getMinPrice(address _token) public view override returns (uint256) {
        return IVaultPriceFeed(priceFeed).getPrice(_token, false, false, false);
    }
    function tokenToUsdMin(address _token, uint256 _tokenAmount) public view override returns (uint256) {
        uint256 price = getMinPrice(_token);
        return _tokenAmount.mul(price).div(10**IMintable(_token).decimals());
    }
    function usdToTokenMax(address _token, uint256 _usdAmount) public override view returns (uint256) {
        return _usdAmount > 0 ? usdToToken(_token, _usdAmount, getMinPrice(_token)) : 0;
    }
    function usdToTokenMin(address _token, uint256 _usdAmount) public override view returns (uint256) {
        return _usdAmount > 0 ? usdToToken(_token, _usdAmount, getMaxPrice(_token)) : 0;
    }
    function usdToToken( address _token, uint256 _usdAmount, uint256 _price ) public view returns (uint256) {
        // if (_usdAmount == 0)  return 0;
        uint256 decimals = IMintable(_token).decimals();
        require(decimals > 0, "invalid decimal");
        return _usdAmount.mul(10**decimals).div(_price);
    }

    function getPositionStructByKey(bytes32 _key) public override view returns (VaultMSData.Position memory){
        return positions[_key];
    }
    function getPositionStruct(address _account, address _collateralToken, address _indexToken, bool _isLong) public override view returns (VaultMSData.Position memory){
        return positions[vaultUtils.getPositionKey(_account, _collateralToken, _indexToken, _isLong, 0)];
    }
    function getTokenBase(address _token) public override view returns (VaultMSData.TokenBase memory){
        return tokenBase[_token];
    }
    function getTradingRec(address _token) public override view returns (VaultMSData.TradingRec memory){
        return tradingRec[_token];
    }
    function isFundingToken(address _token) public view override returns(bool){
        return fundingTokens.contains(_token);
    }
    function isTradingToken(address _token) public view override returns(bool){
        return tradingTokens.contains(_token);
    }
    function getTradingFee(address _token) public override view returns (VaultMSData.TradingFee memory){
        return tradingFee[_token];
    }
    function getUserKeys(address _account, uint256 _start, uint256 _end) external override view returns (bytes32[] memory){
        return IVaultStorage(vaultStorage).getUserKeys(_account, _start, _end);
    }
    function getKeys(uint256 _start, uint256 _end) external override view returns (bytes32[] memory){
        return IVaultStorage(vaultStorage).getKeys(_start, _end);
    }
    //---------- END OF PUBLIC VIEWS ----------




    //---------------------------------------- PRIVATE Functions --------------------------------------------------
    function updateRate(address _token) public override {
        _validate(tradingTokens.contains(_token) || fundingTokens.contains(_token), 7);
        tradingFee[_token] = vaultUtils.updateRate(_token);
    }

    function _swap(address _tokenIn,  address _tokenOut, address _receiver ) private returns (uint256) {
        _validate(fundingTokens.contains(_tokenIn), 24);
        _validate(fundingTokens.contains(_tokenOut), 25);
        _validate(_tokenIn != _tokenOut, 26);
        updateRate(_tokenIn);
        updateRate(_tokenOut);
        uint256 amountIn = _transferIn(_tokenIn);
        _validate(amountIn > 0, 27);
        _increasePoolAmount(_tokenIn, amountIn);
        uint256 _amountInUsd = tokenToUsdMin(_tokenIn, amountIn);
        uint256 _amountOut = usdToTokenMin(_tokenOut, _amountInUsd);
        uint256 feeBasisPoints = vaultUtils.getSwapFeeBasisPoints(_tokenIn, _tokenOut, _amountInUsd);
        uint256 _amountOutAfterFee = _collectSwapFees(_tokenOut, _amountOut, feeBasisPoints);
        _decreasePoolAmount(_tokenOut, _amountOutAfterFee);
        _validatePRA(_tokenOut);
        _transferOut(_tokenOut, _amountOutAfterFee, _receiver);
        emit Swap( _receiver, _tokenIn, _tokenOut, amountIn, _amountOut, _amountOutAfterFee, feeBasisPoints);
        return _amountOutAfterFee;
    }


    function _reduceCollateral(bytes32 _key, uint256 _collateralDelta, uint256 _sizeDelta, uint256 _price) private returns (uint256, uint256) {
        VaultMSData.Position storage position = positions[_key];

        uint256 fee = _collectMarginFees(_key, _sizeDelta);//collateral size updated in _collectMarginFees
        
        // scope variables to avoid stack too deep errors
        bool hasProfit;
        uint256 adjustedDelta;
        {
            // (bool _hasProfit, uint256 delta) = vaultUtils.getDelta(position.indexToken, position.size, position.averagePrice, position.isLong, position.aveIncreaseTime, position.collateral);
            (bool _hasProfit, uint256 delta) = vaultUtils.getDelta(position, _price);
            hasProfit = _hasProfit;
            adjustedDelta = _sizeDelta.mul(delta).div(position.size);// get the proportional change in pnl
        }

        //update Profit
        uint256 profitUsdOut = 0;
        // transfer profits out
        if (hasProfit && adjustedDelta > 0) {
            profitUsdOut = adjustedDelta;
            position.realisedPnl = position.realisedPnl + int256(adjustedDelta);
            
            uint256 usdTax = vaultUtils.calculateTax(profitUsdOut, position.aveIncreaseTime);
            // pay out realised profits from the pool amount for short positions
            // emit PayTax(position.account, _key, profitUsdOut, usdTax);
            profitUsdOut = profitUsdOut.sub(usdTax); 

            uint256 tokenAmount = usdToTokenMin(position.collateralToken, profitUsdOut);
            _decreasePoolAmount(position.collateralToken, tokenAmount);
        }
        else if (!hasProfit && adjustedDelta > 0) {
            position.collateral = position.collateral.sub(adjustedDelta);
            _decreaseGuaranteedUsd(position.collateralToken, adjustedDelta);//decreaseGU = taking position profit by pool
            position.realisedPnl = position.realisedPnl - int256(adjustedDelta);
        }

        uint256 usdOutAfterFee = profitUsdOut;
        // reduce the position's collateral by _collateralDelta
        // transfer _collateralDelta out
        if (_collateralDelta > 0) {
            usdOutAfterFee = usdOutAfterFee.add(_collateralDelta);
            _validate(position.collateral >= _collateralDelta, 33);
            position.collateral = position.collateral.sub(_collateralDelta);
            _decreasePoolAmount(position.collateralToken, usdToTokenMin(position.collateralToken, _collateralDelta));
            _decreaseGuaranteedUsd(position.collateralToken, _collateralDelta); 
        }

        // if the position will be closed, then transfer the remaining collateral out
        if (position.size == _sizeDelta) {
            usdOutAfterFee = usdOutAfterFee.add(position.collateral);
            _decreasePoolAmount(position.collateralToken, usdToTokenMin(position.collateralToken, position.collateral));
            _decreaseGuaranteedUsd(position.collateralToken, position.collateral); 
            position.collateral = 0;
        }

        // uint256 usdOut = fee > 0 ? usdOutAfterFee.add(uint256(fee)) :  usdOutAfterFee.sub(uint256(-fee));
        uint256 usdOut = usdOutAfterFee.add(fee);
        emit UpdatePnl(_key, hasProfit, adjustedDelta, position.size, position.collateral, usdOut, usdOutAfterFee);
        return (usdOut, usdOutAfterFee);
    }

    function _validatePosition(uint256 _size, uint256 _collateral) private view {
        if (_size == 0) {
            _validate(_collateral == 0, 39);
            return;
        }
        _validate(_size >= _collateral, 40);
    }
    
    function _collectSwapFees(address _token, uint256 _amount, uint256 _feeBasisPoints) private returns (uint256) {
        uint256 afterFeeAmount = _amount
            .mul(VaultMSData.COM_RATE_PRECISION.sub(_feeBasisPoints))
            .div(VaultMSData.COM_RATE_PRECISION);
        uint256 feeUSD = tokenToUsdMin(_token, _amount.sub(afterFeeAmount));
        uint256 _feeTokenAmount = usdToTokenMin(feeOutToken, feeUSD);
        _decreasePoolAmount(feeOutToken, _feeTokenAmount);
        _transferOut(feeOutToken, _feeTokenAmount, feeRouter); 
        emit CollectSwapFees(feeOutToken, feeUSD, _feeTokenAmount);
        return afterFeeAmount;
    }

    function _collectMarginFees(bytes32 _key, uint256 _sizeDelta) private returns (uint256) {
        VaultMSData.Position storage _position = positions[_key];
        int256 _premiumFee = vaultUtils.getPremiumFee(_position, tradingFee[_position.indexToken]);
        _position.accPremiumFee += _premiumFee;
        if (_premiumFee > 0){
            _validate(_position.collateral >= uint256(_premiumFee), 29);
            // _decreaseGuaranteedUsd(_position.collateralToken, uint256(_premiumFee));
            _position.collateral = _position.collateral.sub(uint256(_premiumFee));
        }else if (_premiumFee < 0) {
            // _increaseGuaranteedUsd(_position.collateralToken, uint256(-_premiumFee));
            _position.collateral = _position.collateral.add(uint256(-_premiumFee));
        }
        premiumFeeBalance[_position.indexToken] = premiumFeeBalance[_position.indexToken] + _premiumFee;
        emit CollectPremiumFee(_position.account, _position.size, _position.entryPremiumRateSec, _premiumFee);

        uint256 feeUsd = vaultUtils.getPositionFee(_position, _sizeDelta,tradingFee[_position.indexToken]);
        _position.accPositionFee = _position.accPositionFee.add(feeUsd);
        uint256 fuFee = vaultUtils.getFundingFee(_position, tradingFee[_position.collateralToken]);
        _position.accFundingFee = _position.accFundingFee.add(fuFee);
        feeUsd = feeUsd.add(fuFee);
        _validate(_position.collateral >= feeUsd, 29);
        //decrease 
        _position.collateral = _position.collateral.sub(feeUsd);
        _decreaseGuaranteedUsd(_position.collateralToken, feeUsd);

        //decrease pool into fee
        _collectFeeResv(_position.account, feeOutToken, feeUsd);

        return feeUsd;
    }

    function _collectFeeResv(address _account, address _token, uint256 _marginFeesUSD) private returns (uint256) {
        uint256 _feeInToken = usdToTokenMin(_token, _marginFeesUSD);
        _decreasePoolAmount(_token, _feeInToken);
        (uint256 _discFee, uint256 _rebateFee, address _rebateAccount) = pid.getFeeDet(_account, _feeInToken);
        uint256 _discFeeInToken = _discFee.add(_rebateFee);
        _transferOut(_token, _feeInToken.sub(_discFeeInToken), feeRouter);
        if (_discFeeInToken > 0){
            _transferOut(_token, _discFee, userFeeResv);
            IUserFeeResv(userFeeResv).update(_account, _token, _discFee);
            _transferOut(_token, _rebateFee, userFeeResv);
            IUserFeeResv(userFeeResv).update(_rebateAccount, _token, _rebateFee);
        }
        emit CollectMarginFees(_token, _marginFeesUSD, _feeInToken, _discFeeInToken);
        return _feeInToken;
    }


    function _transferIn(address _token) private returns (uint256) {
        uint256 prevBalance = tokenBase[_token].balance;
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        tokenBase[_token].balance = nextBalance;
        return nextBalance.sub(prevBalance);
    }

    function _transferOut( address _token, uint256 _amount, address _receiver ) private {
        if (_amount > 0)
            IERC20(_token).safeTransfer(_receiver, _amount);
        tokenBase[_token].balance = IERC20(_token).balanceOf(address(this));
    }

    function _increasePoolAmount(address _token, uint256 _amount) private {
        tokenBase[_token].poolAmount = tokenBase[_token].poolAmount.add(_amount);
        _validatePRA(_token);
        emit IncreasePoolAmount(_token, _amount);
    }

    function _decreasePoolAmount(address _token, uint256 _amount) private {
        tokenBase[_token].poolAmount = tokenBase[_token].poolAmount.sub(_amount, "PoolAmount exceeded");
        _validatePRA(_token);
        emit DecreasePoolAmount(_token, _amount);
    }

    function _validatePRA(address _token) private view {
        _validate(tokenBase[_token].poolAmount >= tokenBase[_token].reservedAmount, 50);
    }

    function _increaseReservedAmount(address _token, uint256 _amount) private {
        _validate(_amount > 0, 53);
        tokenBase[_token].reservedAmount = tokenBase[_token].reservedAmount.add(_amount);
        _validate(tokenBase[_token].reservedAmount <= tokenBase[_token].poolAmount, 52);
        emit IncreaseReservedAmount(_token, _amount);
    }

    function _decreaseReservedAmount(address _token, uint256 _amount) private {
        tokenBase[_token].reservedAmount = tokenBase[_token].reservedAmount.sub( _amount, "Vault: insufficient reserve" );
        emit DecreaseReservedAmount(_token, _amount);
    }

    function _validate(bool _condition, uint256 _errorCode) private view {
        require(_condition, vaultUtils.errors(_errorCode));
    }

    function _updateGlobalSize(bool _isLong, address _indexToken, uint256 _sizeDelta, uint256 _price, bool _increase) private {
        VaultMSData.TradingRec storage ttREC = tradingRec[_indexToken];
        if (_isLong) {
            ttREC.longAveragePrice = vaultUtils.getNextAveragePrice(ttREC.longSize,  ttREC.longAveragePrice, _price, _sizeDelta, _increase);
            if (_increase){
                ttREC.longSize = ttREC.longSize.add(_sizeDelta);
                globalLongSize = globalLongSize.add(_sizeDelta);
            }else{
                ttREC.longSize = ttREC.longSize.sub(_sizeDelta);
                globalLongSize = globalLongSize.sub(_sizeDelta);
            }
            // emit UpdateGlobalSize(_indexToken, ttREC.longSize, globalLongSize,ttREC.longAveragePrice, _increase, _isLong );
        } else {
            ttREC.shortAveragePrice = vaultUtils.getNextAveragePrice(ttREC.shortSize,  ttREC.shortAveragePrice, _price, _sizeDelta, _increase);  
            if (_increase){
                ttREC.shortSize = ttREC.shortSize.add(_sizeDelta);
                globalShortSize = globalShortSize.add(_sizeDelta);
            }else{
                ttREC.shortSize = ttREC.shortSize.sub(_sizeDelta);
                globalShortSize = globalShortSize.sub(_sizeDelta);    
            }
            // emit UpdateGlobalSize(_indexToken, ttREC.shortSize, globalShortSize,ttREC.shortAveragePrice, _increase, _isLong );
        }
        if (ttREC.longSize.add(ttREC.shortSize) == 0){
            premiumFeeBalance[_indexToken] = 0;
        }
    }

    function _delPosition(address _account, bytes32 _key) private {
        delete positions[_key];
        IVaultStorage(vaultStorage).delKey(_account, _key);
    }

    function _increaseGuaranteedUsd(address _token, uint256 _usdAmount) private {
        guaranteedUsd = guaranteedUsd.add(_usdAmount);
        emit IncreaseGuaranteedUsd(_token, _usdAmount);
    }

    function _decreaseGuaranteedUsd(address _token, uint256 _usdAmount)  private {
        guaranteedUsd = guaranteedUsd > _usdAmount ?guaranteedUsd.sub(_usdAmount) : 0;
        emit DecreaseGuaranteedUsd(_token, _usdAmount);
    }

    function tokenDecimals(address _token) public view  returns (uint8){
        return IMintable(_token).decimals();
    }

}
