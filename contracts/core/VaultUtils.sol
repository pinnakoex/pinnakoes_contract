// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../utils/EnumerableValues.sol";
import "../oracle/interfaces/IVaultPriceFeed.sol";
import "./VaultMSData.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";
import "./interfaces/IVaultStorage.sol";


contract VaultUtils is IVaultUtils, Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableValues for EnumerableSet.Bytes32Set;
    bool public override inPrivateLiquidationMode = false;

    mapping(address => bool) public override isLiquidator;
    bool public override hasDynamicFees = true; //not used

    //Fees related to swap
    uint256 public override taxBasisPoints = 0; // 0.5%
    uint256 public override stableTaxBasisPoints = 0; // 0.2%
    uint256 public override mintBurnFeeBasisPoints = 0; // 0.3%
    uint256 public override swapFeeBasisPoints = 0; // 0.3%
    uint256 public override stableSwapFeeBasisPoints = 0; // 0.04%
    uint256 public override marginFeeBasisPoints = 10; // 0.1%
    uint256 public override liquidationFeeUsd = 5 * VaultMSData.PRICE_PRECISION;
    uint256 public override maxLeverage = 100 * VaultMSData.COM_RATE_PRECISION; // 100x
    
    uint256 public constant MAX_FEE_BASIS_POINTS = 500; // 5%   50000
    uint256 public constant MAX_NON_PROFIT_TIME = 300; // 5min
    uint256 public constant MAX_LIQUIDATION_FEE_USD = 100 * VaultMSData.PRICE_PRECISION; // 100 USD


    //Fees related to funding
    uint256 public override fundingRateFactor;
    uint256 public override stableFundingRateFactor;


    //trading tax part
    uint256 public override taxDuration;
    uint256 public override taxMax;
    uint256 public override nonProfitTime;
    

    //trading profit limitation part
    uint256 public override maxProfitRatio = 20 * VaultMSData.COM_RATE_PRECISION;

    IVault public vault;
    mapping(uint256 => string) public override errors;


    mapping(address => uint256) public override sizeSpreadBasisMax;
    mapping(address => uint256) public override sizeSpreadGapStart;
    mapping(address => uint256) public override sizeSpreadGapMax;

    uint256 public override premiumBasisPointsPerHour;
    uint256 public override premiumBasisPointsPerSec;
    uint256 public override maxPremiumBasisErrorUSD;

    int256 public override posIndexMaxPointsPerHour;
    int256 public override posIndexMaxPointsPerSec;
    int256 public override negIndexMaxPointsPerHour;
    int256 public override negIndexMaxPointsPerSec;


    event SetPriceSpreadBasis(address _token, uint256 _spreadBasis, uint256 _maxSpreadBasis, uint256 gapMax);
    event SetSizeSpreadBasis(address _token, uint256 _spreadBasis, uint256 _maxSpreadBasis, uint256 _minSpreadCalUSD);
    event SetPremiumRate(uint256 _premiumBasisPoints, int256 _posIndexMaxPoints, int256 _negIndexMaxPoints, uint256 _maxPremiumBasisErrorUSD);
    event SetFundingRate(uint256 _fundingRateFactor, uint256 _stableFundingRateFactor);
    event SetMaxLeverage(uint256 _maxLeverage);
    event SetTaxRate(uint256 _taxMax, uint256 _taxTime, uint256 _nonProfitTime);
    event SetFees(uint256 _taxBasisPoints,uint256 _stableTaxBasisPoints, uint256 _mintBurnFeeBasisPoints, uint256 _swapFeeBasisPoints, uint256 _stableSwapFeeBasisPoints, uint256 _marginFeeBasisPoints, uint256 _liquidationFeeUsd, bool _hasDynamicFees);
    modifier onlyVault() {
        require(msg.sender == address(vault), "onlyVault");
        _;
    }

    constructor(IVault _vault) {
        vault = _vault;
    }

    function setMaxProfitRatio(uint256 _setRatio) external onlyOwner{
        require(_setRatio > VaultMSData.COM_RATE_PRECISION, "ratio small");
        maxProfitRatio = _setRatio;
    }

    function setSizeSpreadBasis(address _token, 
            uint256 _sizeSpreadBasisMax, uint256 _sizeSpreadGapStart, uint256 _sizeSpreadGapMax) external onlyOwner{
        require(_sizeSpreadBasisMax <= VaultMSData.COM_RATE_PRECISION.div(2), "max basis");
        sizeSpreadBasisMax[_token] = _sizeSpreadBasisMax;
        sizeSpreadGapStart[_token] = _sizeSpreadGapStart;
        sizeSpreadGapMax[_token] = _sizeSpreadGapMax;
        emit SetSizeSpreadBasis(_token, _sizeSpreadBasisMax, _sizeSpreadGapStart, _sizeSpreadGapMax);
    }

    function setLiquidator(address _liquidator, bool _isActive) external override onlyOwner {
        isLiquidator[_liquidator] = _isActive;
    }

    function setInPrivateLiquidationMode(bool _inPrivateLiquidationMode) external override onlyOwner {
        inPrivateLiquidationMode = _inPrivateLiquidationMode;
    }

    function setPremiumRate(uint256 _premiumBasisPoints, int256 _posIndexMaxPoints, int256 _negIndexMaxPoints, uint256 _maxPremiumBasisErrorUSD) external onlyOwner{
        require(negIndexMaxPointsPerSec <= 0, "_negIndexMaxPoints be negative");
        require(_posIndexMaxPoints >= 0, "_posIndexMaxPoints be positive");
        _validate(_premiumBasisPoints <= VaultMSData.COM_RATE_PRECISION, 12);
        premiumBasisPointsPerHour = _premiumBasisPoints;
        premiumBasisPointsPerSec = hRateToSecRate(premiumBasisPointsPerHour);

        negIndexMaxPointsPerHour = _negIndexMaxPoints;
        negIndexMaxPointsPerSec = hRateToSecRateInt(negIndexMaxPointsPerHour);

        posIndexMaxPointsPerHour = _posIndexMaxPoints;
        posIndexMaxPointsPerSec = hRateToSecRateInt(posIndexMaxPointsPerHour);

        maxPremiumBasisErrorUSD = _maxPremiumBasisErrorUSD;
        emit SetPremiumRate(_premiumBasisPoints, _posIndexMaxPoints, _negIndexMaxPoints, _maxPremiumBasisErrorUSD);
    }

    function setFundingRate(uint256 _fundingRateFactor, uint256 _stableFundingRateFactor) external onlyOwner{
        _validate(_fundingRateFactor <= VaultMSData.COM_RATE_PRECISION, 11);
        _validate(_stableFundingRateFactor <= VaultMSData.COM_RATE_PRECISION, 12);
        fundingRateFactor = _fundingRateFactor;
        stableFundingRateFactor = _stableFundingRateFactor;
        emit SetFundingRate(_fundingRateFactor, _stableFundingRateFactor);
    }

    function setMaxLeverage(uint256 _maxLeverage) public override onlyOwner{
        require(_maxLeverage > VaultMSData.COM_RATE_PRECISION, "ERROR2");
        require(_maxLeverage < 220 * VaultMSData.COM_RATE_PRECISION, "Max leverage reached");
        maxLeverage = _maxLeverage;
        emit SetMaxLeverage(_maxLeverage);
    }

    function setTaxRate(uint256 _taxMax, uint256 _taxTime, uint256 _nonProfitTime) external onlyOwner{
        require(_taxMax <= VaultMSData.PRC_RATE_PRECISION, "TAX MAX exceed");
        require(_nonProfitTime <= MAX_NON_PROFIT_TIME, "Max non-profit time exceed.");
        if (_taxTime > 0){
            taxMax = _taxMax;
            taxDuration = _taxTime;
        }else{
            taxMax = 0;
            taxDuration = 0;
        }
        nonProfitTime = _nonProfitTime;
        emit SetTaxRate(_taxMax, _taxTime, _nonProfitTime);
    }

    function setFees(
        uint256 _taxBasisPoints,
        uint256 _stableTaxBasisPoints,
        uint256 _mintBurnFeeBasisPoints,
        uint256 _swapFeeBasisPoints,
        uint256 _stableSwapFeeBasisPoints,
        uint256 _marginFeeBasisPoints,
        uint256 _liquidationFeeUsd,
        bool _hasDynamicFees
    ) external override onlyOwner {
        require(_taxBasisPoints <= MAX_FEE_BASIS_POINTS, "3");
        require(_stableTaxBasisPoints <= MAX_FEE_BASIS_POINTS, "ERROR4");
        require(_mintBurnFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "ERROR5");
        require(_swapFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "ERROR6");
        require(_stableSwapFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "ERROR7");
        require(_marginFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "ERROR8");
        require(_liquidationFeeUsd <= MAX_LIQUIDATION_FEE_USD, "ERROR9");
        taxBasisPoints = _taxBasisPoints;
        stableTaxBasisPoints = _stableTaxBasisPoints;
        mintBurnFeeBasisPoints = _mintBurnFeeBasisPoints;
        swapFeeBasisPoints = _swapFeeBasisPoints;
        stableSwapFeeBasisPoints = _stableSwapFeeBasisPoints;
        marginFeeBasisPoints = _marginFeeBasisPoints;
        liquidationFeeUsd = _liquidationFeeUsd;
        hasDynamicFees = _hasDynamicFees;
        emit SetFees(_taxBasisPoints,_stableTaxBasisPoints, _mintBurnFeeBasisPoints, _swapFeeBasisPoints, _stableSwapFeeBasisPoints, _marginFeeBasisPoints, _liquidationFeeUsd, _hasDynamicFees);

    }

    function getLatestFundingRatePerSec(address _token) public view override returns (uint256){
        VaultMSData.TokenBase memory tB = vault.getTokenBase(_token);
        if (tB.poolAmount == 0) return 0;
        // tradingFee.fundingRatePerHour
        uint256 _fundingUtil = tB.reservedAmount.mul(VaultMSData.PRC_RATE_PRECISION).div(tB.poolAmount);
        return hRateToSecRate(fundingRateFactor.mul(_fundingUtil)).div(VaultMSData.PRC_RATE_PRECISION);
    }

    function hRateToSecRate(uint256 _comRate) public pure  returns (uint256){
        return _comRate.mul(VaultMSData.PRC_RATE_PRECISION).div(VaultMSData.HOUR_RATE_PRECISION).div(3600);
    }
    function hRateToSecRateInt(int256 _comRate) public pure  returns (int256){
        return _comRate * int256(VaultMSData.PRC_RATE_PRECISION) / int256(VaultMSData.HOUR_RATE_PRECISION.mul(3600));
    }

    function getLatestLSRate(address _token) public view override returns (int256, int256){
        VaultMSData.TradingRec memory _traRec = vault.getTradingRec(_token);
        if (premiumBasisPointsPerSec == 0 || maxPremiumBasisErrorUSD == 0) return (0,0);
        // uint256 _maxSize = _traRec.longSize > _traRec.shortSize ? _traRec.longSize : _traRec.shortSize ;
        int256 _longRate = 0;//int256(premiumBasisPointsPerSec);
        int256 _shortRate = 0;// int256(premiumBasisPointsPerSec);
        uint256 totalSize = _traRec.shortSize.add(_traRec.longSize);
        if (totalSize == 0) return (0,0);
        
        uint256 errorSize = _traRec.shortSize > _traRec.longSize ? _traRec.shortSize.sub(_traRec.longSize) : _traRec.longSize.sub(_traRec.shortSize);
        errorSize = errorSize > maxPremiumBasisErrorUSD ? maxPremiumBasisErrorUSD : errorSize;
        int256 largeSizeRate = int256(errorSize.mul(premiumBasisPointsPerSec).div(maxPremiumBasisErrorUSD));
        if (_traRec.longSize > _traRec.shortSize){
            _longRate = largeSizeRate;
            _shortRate = _traRec.shortSize > 0 ? - largeSizeRate * int256(_traRec.longSize) / int256(_traRec.shortSize) : -int256(premiumBasisPointsPerSec);
            _shortRate = _shortRate < negIndexMaxPointsPerSec ? negIndexMaxPointsPerSec : _shortRate;
        }else{//short is larger
            _shortRate = largeSizeRate;
            _longRate = _traRec.longSize > 0 ? - largeSizeRate * int256(_traRec.shortSize) / int256(_traRec.longSize) : -int256(premiumBasisPointsPerSec);
            _longRate = _longRate < negIndexMaxPointsPerSec ? negIndexMaxPointsPerSec : _longRate;
        }

        return (_longRate, _shortRate);
    }

    function updateRate(address _token) public view override returns (VaultMSData.TradingFee memory) {
        VaultMSData.TradingFee memory _tradingFee = vault.getTradingFee(_token);
       
        uint256 timepastSec =_tradingFee.latestUpdateTime > 0 ? block.timestamp.sub(_tradingFee.latestUpdateTime) : 0;
        _tradingFee.latestUpdateTime = block.timestamp;

        if (timepastSec > 0){
            // accumulative funding rate
            _tradingFee.accumulativefundingRateSec = _tradingFee.accumulativefundingRateSec.add(_tradingFee.fundingRatePerSec.mul(timepastSec));
            //update accumulative lohg/short rate
            _tradingFee.accumulativeLongRateSec += _tradingFee.longRatePerSec * int256(timepastSec);
            _tradingFee.accumulativeShortRateSec += _tradingFee.shortRatePerSec * int256(timepastSec);  
        }
 
        //update funding rate
        _tradingFee.fundingRatePerSec = getLatestFundingRatePerSec(_token);
        // (_tradingFee.longRatePerSec, _tradingFee.shortRatePerSec) = getLatestLSRate(_token);//closed currently
        return _tradingFee;
    }

    function getNextIncreaseTime(uint256 _prev_time, uint256 _prev_size,uint256 _sizeDelta) public view override returns (uint256){
        return _prev_time.mul(_prev_size).add(_sizeDelta.mul(block.timestamp)).div(_sizeDelta.add(_prev_size));
    }         
    
    function validateIncreasePosition(address  _collateralToken, address _indexToken, uint256 _size, uint256 _sizeDelta, bool _isLong) external override view {
        _validate(_size.add(_sizeDelta) > 0, 7);
        //validate tokens.
        require(vault.isFundingToken(_collateralToken), "not funding token");
        require(vault.isTradingToken(_indexToken), "not trading token");
        uint256 baseMode = vault.baseMode();
        require(baseMode > 0 && baseMode < 3, "invalid vault mode");

        VaultMSData.TradingRec memory _tRec = vault.getTradingRec(_indexToken);
        VaultMSData.TokenBase memory tbCol = vault.getTokenBase(_collateralToken);
        VaultMSData.TokenBase memory tbIdx = vault.getTokenBase(_indexToken);
        VaultMSData.TradingLimit memory tLimit = IVaultStorage(vault.vaultStorage()).getTradingLimit(_indexToken);
        
        //validate trading size
        {
            uint256 _latestLong  = _isLong ? _tRec.longSize.add(_sizeDelta) : _tRec.longSize;
            uint256 _latestShort = _isLong ? _tRec.shortSize : _tRec.shortSize.add(_sizeDelta) ;
            uint256 _sumSize = _latestLong.add(_latestShort);
            if (tLimit.maxLongSize > 0) require(_latestLong < tLimit.maxLongSize, "max token long size reached");
            if (tLimit.maxShortSize > 0) require(_latestShort < tLimit.maxShortSize, "max token short size reached");
            if (tLimit.maxTradingSize > 0) require(_sumSize < tLimit.maxTradingSize, "max trading size reached");
            if (tLimit.countMinSize > 0 && tLimit.maxRatio > 0 && _sumSize > tLimit.countMinSize){
                require( (_latestLong > _latestShort ? _latestLong : _latestShort).mul(VaultMSData.COM_RATE_PRECISION).div(_sumSize) < tLimit.maxRatio, "max long/short ratio reached");
            }
        }


        //validate collateral token based on base mode
        _validate(!tbIdx.isStable, 47);
        if (baseMode == 1){
            if (_isLong) 
                _validate(_collateralToken == _indexToken, 46);
            else 
                _validate(tbCol.isStable, 46);
        }
        else if  (baseMode == 2){
            _validate(tbCol.isStable, 46);
        }
        else{
            _validate(_collateralToken == _indexToken, 42);  
        }

    }

    function validateDecreasePosition(VaultMSData.Position memory _position, uint256 _sizeDelta, uint256 _collateralDelta) external override view {
        // no additional validations
        _validate(_position.size > 0, 31);
        _validate(_position.size >= _sizeDelta, 32);
        _validate(_position.collateral >= _collateralDelta, 33);

        require( vault.isFundingToken(_position.collateralToken), "not funding token");
        require( vault.isTradingToken(_position.indexToken), "not trading token");

    }

    function validateRatioDelta(bytes32 /*_key*/, uint256 _lossRatio, uint256 _profitRatio) public view override returns (bool){
        //step.1 valid size
        //step.2 valid range
        //step.3 valid prev liquidation
        //step.4 valid new liquidation
        require(_profitRatio <= maxProfitRatio, "max taking profit ratio reached");
        require(_lossRatio <= VaultMSData.COM_RATE_PRECISION, "max loss ratio reached");
        return true;
    }
    

    function getReserveDelta(address _collateralToken, uint256 _sizeUSD, uint256 _colUSD, uint256 /*_takeProfitRatio*/) public view override returns (uint256){
        // uint256 reserveDelta = usdToTokenMax(_collateralToken, _sizeDelta);
        // uint256 reserveDelta = 
        if (vault.baseMode() == 1){
            return vault.usdToTokenMax(_collateralToken, _sizeUSD.add(_colUSD));
        }
        else if (vault.baseMode() == 2){
            // require(maxProfitRatio > 0 && _takeProfitRatio <= maxProfitRatio, "invalid max profit");
            // uint256 resvUSD = _colUSD.mul(_takeProfitRatio > 0 ? _takeProfitRatio : maxProfitRatio).div(VaultMSData.COM_RATE_PRECISION);         
            return vault.usdToTokenMax(_collateralToken, _sizeUSD.add(_colUSD));
        }
        else{
            revert("invalid baseMode");
        }
        // return 0;
    }

    function getPositionKey(address _account,address _collateralToken, address _indexToken, bool _isLong, uint256 _keyID) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _collateralToken, _indexToken, _isLong, _keyID) );
    }
    
    function getPositionInfo(address _account, address _collateralToken, address _indexToken, bool _isLong) public view returns (uint256[] memory, int256[] memory ){
        VaultMSData.Position memory _pos = vault.getPositionStructByKey(getPositionKey(_account, _collateralToken, _indexToken, _isLong, 0));
        uint256[] memory _uInfo = new uint256[](9);
        int256[] memory _iInfo = new int256[](2);
        _uInfo[0] = _pos.size;
        _uInfo[1] = _pos.collateral;
        _uInfo[2] = _pos.averagePrice;
        _uInfo[3] = _pos.reserveAmount;
        _uInfo[4] = _pos.lastUpdateTime;
        _uInfo[5] = _pos.aveIncreaseTime;
        _uInfo[6] = _pos.stopLossRatio;
        _uInfo[7] = _pos.takeProfitRatio;
        _uInfo[8] = _pos.entryFundingRateSec;

        _iInfo[0] = _pos.realisedPnl;
        _iInfo[1] = _pos.entryPremiumRateSec;
        return (_uInfo, _iInfo);
    }

    function getLiqPrice(bytes32 _key) public view override returns (int256){
        VaultMSData.Position memory position = vault.getPositionStructByKey(_key);
        if (position.size < 1) return 0;
        
        VaultMSData.TradingFee memory colTF = vault.getTradingFee(position.collateralToken);
        VaultMSData.TradingFee memory idxTF = vault.getTradingFee(position.indexToken);

        uint256 marginFees = getFundingFee(position, colTF).add(getPositionFee(position, 0, idxTF));
        int256 _premiumFee = getPremiumFee(position, idxTF);
    
        uint256 colRemain = position.collateral.sub(marginFees);
        colRemain = _premiumFee >= 0 ?position.collateral.sub(uint256(_premiumFee)) : position.collateral.add(uint256(-_premiumFee)) ;
        // (bool hasProfit, uint256 delta) = getDelta(position.indexToken, position.size, position.averagePrice, position.isLong, position.lastUpdateTime, position.collateral);
        // colRemain = hasProfit ? position.collateral.sub(delta) : position.collateral.add(delta);

        uint256 acceptPriceGap = colRemain.mul(position.averagePrice).div(position.size);
        return position.isLong ? int256(position.averagePrice) - int256(acceptPriceGap) : int256(position.averagePrice.add(acceptPriceGap));
    }

    function getNextAveragePrice(uint256 _size, uint256 _averagePrice,  uint256 _nextPrice, uint256 _sizeDelta, bool _isIncrease) public pure override returns (uint256) {
        if (_size == 0) return _nextPrice;
        if (_isIncrease){
            uint256 nextSize = _size.add(_sizeDelta) ;
            return nextSize > 0 ? (_averagePrice.mul(_size)).add(_sizeDelta.mul(_nextPrice)).div(nextSize) : 0;   
        }
        else{
            uint256 _latestSize = _size > _sizeDelta ? _size.sub(_sizeDelta) : 0;
            uint256 _preAum = _averagePrice.mul(_size);
            uint256 _deltaAum =_sizeDelta.mul(_nextPrice);
            return (_latestSize > 0 && _preAum > _deltaAum) ? (_preAum.sub(_deltaAum)).div(_latestSize) : 0;
        }
    }

    function getInitialPosition(address _account, address _collateralToken, address _indexToken, uint256 , bool _isLong, uint256 _price) public override view returns (VaultMSData.Position memory){
        VaultMSData.Position memory position;
        position.account = _account;
        position.averagePrice = _price;
        position.aveIncreaseTime = block.timestamp;
        position.collateralToken = _collateralToken;
        position.indexToken = _indexToken;
        position.isLong = _isLong;
        return position;
    }

    function getPositionNextAveragePrice(uint256 _size, uint256 _averagePrice, uint256 _nextPrice, uint256 _sizeDelta, bool _isIncrease) public override pure returns (uint256) {
        if (_isIncrease){
            uint256 _tps = _averagePrice.mul(_nextPrice).div(VaultMSData.PRICE_PRECISION).mul(_size.add(_sizeDelta));
            uint256 _tpp = (_averagePrice.mul(_sizeDelta).add(_nextPrice.mul(_size))).div(VaultMSData.PRICE_PRECISION);
            require(_tpp > 0, "empty size");
            return _tps.div(_tpp);
            // return (_size.mul(_averagePrice)).add(_sizeDelta.mul(_nextPrice)).div(_size.add(_sizeDelta));
        }
        else{
            require(_size >= _sizeDelta, "invalid size delta");
            return _averagePrice;
            // return (_size.mul(_averagePrice)).sub(_sizeDelta.mul(_nextPrice)).div(_size.sub(_sizeDelta));
        }
    }

    function calculateTax(uint256 _profit, uint256 _aveIncreaseTime) public view override returns(uint256){     
        if (taxMax == 0)
            return 0;
        uint256 _positionDuration = block.timestamp.sub(_aveIncreaseTime);
        if (_positionDuration >= taxDuration)
            return 0;
        
        uint256 taxPercent = (taxDuration.sub(_positionDuration)).mul(taxMax).div(taxDuration);
        // taxPercent = taxPercent > taxMax ? taxMax : taxPercent;
        taxPercent = taxPercent > VaultMSData.PRC_RATE_PRECISION ? VaultMSData.PRC_RATE_PRECISION : taxPercent;
        return _profit.mul(taxPercent).div(VaultMSData.PRC_RATE_PRECISION);
    }

    function validateLiquidation(bytes32 _key, bool _raise) public view override returns (uint256, uint256, int256){
        VaultMSData.Position memory position = vault.getPositionStructByKey(_key);
        return _validateLiquidation(position, _raise);
    }

    function validateLiquidationPar(address _account, address _collateralToken, address _indexToken, bool _isLong, bool _raise) public view returns (uint256, uint256, int256) {
        VaultMSData.Position memory position = vault.getPositionStructByKey(getPositionKey( _account, _collateralToken, _indexToken, _isLong, 0));
        return _validateLiquidation(position, _raise);
    }
    
    function _validateLiquidation(VaultMSData.Position memory position, bool _raise) public view returns (uint256, uint256, int256) {
        if (position.size == 0) return (0,1,0);

        VaultMSData.TradingFee memory colTF = vault.getTradingFee(position.collateralToken);
        VaultMSData.TradingFee memory idxTF = vault.getTradingFee(position.indexToken);
        uint256 _price = position.isLong ? vault.getMinPrice(position.indexToken) : vault.getMaxPrice(position.indexToken);
        (bool hasProfit, uint256 delta) = getDelta(position, _price);
        uint256 marginFees = getFundingFee(position, colTF).add( getPositionFee(position, 0, idxTF));

        int256 _premiumFee = getPremiumFee(position, idxTF);
    


        if (!hasProfit && position.collateral < delta) {
            if (_raise) { revert("Vault: losses exceed collateral"); }
            return (1, marginFees,_premiumFee);
        }

        uint256 remainingCollateral = position.collateral;
        if (_premiumFee < 0)
            remainingCollateral = remainingCollateral.add(uint256(-_premiumFee));
        else{
            if (remainingCollateral < uint256(_premiumFee)) {
                if (_raise) { revert("Vault: index fees exceed collateral"); }
                // cap the fees to the remainingCollateral
                return (1, remainingCollateral,_premiumFee);
            }
            remainingCollateral = remainingCollateral.sub(uint256(_premiumFee));
        }

        if (remainingCollateral < marginFees) {
            if (_raise) { revert("Vault: fees exceed collateral"); }
            // cap the fees to the remainingCollateral
            return (1, remainingCollateral,_premiumFee);
        }

        if (!hasProfit) {
            remainingCollateral = position.collateral.sub(delta);
        }

        if (remainingCollateral < marginFees) {
            if (_raise) { revert("Vault: fees exceed collateral"); }
            // cap the fees to the remainingCollateral
            return (1, remainingCollateral,_premiumFee);
        }

        if (remainingCollateral < marginFees.add(liquidationFeeUsd)) {
            if (_raise) { revert("Vault: liquidation fees exceed collateral"); }
            return (1, marginFees,_premiumFee);
        }

        if (remainingCollateral.mul(maxLeverage) < position.size.mul(VaultMSData.COM_RATE_PRECISION)) {
            if (_raise) { revert("Vault: maxLeverage exceeded"); }
            return (2, marginFees, _premiumFee);
        }

        if (vault.baseMode() > 1){
            if (hasProfit && maxProfitRatio > 0){
                if (delta >= remainingCollateral.mul(maxProfitRatio).div(VaultMSData.COM_RATE_PRECISION) ){
                    if (_raise) { revert("Vault: max profit exceeded"); }
                    return (3, marginFees,_premiumFee);
                }
            }

            if (hasProfit && position.takeProfitRatio > 0){
                if (delta >= remainingCollateral.mul(position.takeProfitRatio).div(VaultMSData.COM_RATE_PRECISION) ){
                    if (_raise) { revert("Vault: max profit exceeded"); }
                    return (3, marginFees,_premiumFee);
                }
            }
            // 
            if (!hasProfit && position.stopLossRatio > 0){
                if (delta >= remainingCollateral.mul(position.stopLossRatio).div(VaultMSData.COM_RATE_PRECISION) ){
                    if (_raise) { revert("Vault: stop loss ratio reached"); }
                    return (4, marginFees,_premiumFee);
                }
            }
        }

        return (0, marginFees, _premiumFee);
    }
    

    // function getDelta(address _indexToken, uint256 _size, uint256 _averagePrice, bool _isLong, uint256 _aveIncreasedTime, uint256 _colSize) public view override returns (bool, uint256) {
    function getDelta(VaultMSData.Position memory _position, uint256 _price) public view override returns (bool, uint256) {
        _validate(_position.averagePrice > 0, 38);
        // uint256 price = _isLong ? vault.getMinPrice(_indexToken) : vault.getMaxPrice(_indexToken);
        uint256 priceDelta = _position.averagePrice > _price ? _position.averagePrice.sub(_price) : _price.sub(_position.averagePrice);
        uint256 delta = _position.size.mul(priceDelta).div(_position.averagePrice);
        bool hasProfit;
        if (_position.isLong) {
            hasProfit = _price > _position.averagePrice;
        } else {
            hasProfit = _position.averagePrice > _price;
        }       
        //todo: add max profit here
        if (hasProfit && maxProfitRatio > 0){
            uint256 _maxProfit = _position.collateral.mul(maxProfitRatio).div(VaultMSData.COM_RATE_PRECISION);
            delta = delta > _maxProfit ? _maxProfit : delta;
        }
        if (hasProfit){
            uint256 resvProfit = _position.reserveAmount > _position.collateral ? _position.reserveAmount.sub(_position.collateral) : 0;
            delta = delta > resvProfit ? delta : resvProfit;
        }
        if (hasProfit && block.timestamp < _position.aveIncreaseTime.add(nonProfitTime)){
            hasProfit = false;
            delta = 0;
        }
        return (hasProfit, delta);
    }


    function getPositionFee(VaultMSData.Position memory _position, uint256 _sizeDelta, VaultMSData.TradingFee memory /*_tradingFee*/) public override view returns (uint256) {
        if (_sizeDelta == 0) { return 0; }
        uint256 spreadBasisPoints = marginFeeBasisPoints;
        address _token = _position.indexToken;
        if (sizeSpreadBasisMax[_token] > 0 
            && _sizeDelta > sizeSpreadGapStart[_token]
            && sizeSpreadGapMax[_token] > 0){
            uint256 _spread = _sizeDelta.sub(sizeSpreadGapStart[_token]);
            _spread = _spread < sizeSpreadGapMax[_token] ? _spread :sizeSpreadGapMax[_token];
            _spread = sizeSpreadBasisMax[_token].mul(_spread).div(sizeSpreadGapMax[_token]);
            spreadBasisPoints = spreadBasisPoints.add(_spread);
        }

        uint256 afterFeeUsd = _sizeDelta.mul(VaultMSData.COM_RATE_PRECISION.sub(spreadBasisPoints)).div(VaultMSData.COM_RATE_PRECISION);
        return _sizeDelta.sub(afterFeeUsd);
    }

    function getFundingFee(VaultMSData.Position memory _position, VaultMSData.TradingFee memory _tradingFee) public view override returns (uint256) {
        if (_position.size == 0) { return 0; }
        // VaultMSData.TradingFee memory _tradingFee = vault.getTradingFee(_position.collateralToken);

        uint256 latestAccumFundingRate = _tradingFee.accumulativefundingRateSec.add(_tradingFee.fundingRatePerSec.mul(block.timestamp.sub(_tradingFee.latestUpdateTime)));
        uint256 fundingRate = latestAccumFundingRate.sub(_position.entryFundingRateSec);
        if (fundingRate == 0) { return 0; }
        return _position.size.mul(fundingRate).div(VaultMSData.PRC_RATE_PRECISION);
    }

    // function getPremiumFee(address _indexToken, bool _isLong, uint256 _size, int256 _entryPremiumRate) public view override returns (int256) {
    function getPremiumFee(VaultMSData.Position memory _position, VaultMSData.TradingFee memory _tradingFee) public view override returns (int256) {
        return 0; 
        // if (_position.size == 0 || _position.lastUpdateTime == 0)
        //     return 0; 
        // // VaultMSData.TradingFee memory _tradingFee = vault.getTradingFee(_position.indexToken);
        // int256 _accumPremiumRate = _position.isLong ? _tradingFee.accumulativeLongRateSec : _tradingFee.accumulativeShortRateSec;
        // int256 _useFeePerSec  = _position.isLong ? _tradingFee.longRatePerSec : _tradingFee.shortRatePerSec;
        // _accumPremiumRate += _useFeePerSec * int256((block.timestamp.sub(_tradingFee.latestUpdateTime)));
        // _accumPremiumRate -= _position.entryPremiumRateSec;
        // return int256(_position.size) * _accumPremiumRate / int256(VaultMSData.PRC_RATE_PRECISION);
    }

    function getBuyLpFeeBasisPoints(address _token, uint256 _usdAmount) public override view returns (uint256) {
        return getFeeBasisPoints(_token, _usdAmount, mintBurnFeeBasisPoints, taxBasisPoints, true);
    }

    function getSellLpFeeBasisPoints(address _token, uint256 _usdAmount) public override view returns (uint256) {
        return getFeeBasisPoints(_token, _usdAmount, mintBurnFeeBasisPoints, taxBasisPoints, false);
    }

    function getSwapFeeBasisPoints(address _tokenIn, address _tokenOut, uint256 _usdAmount) public override view returns (uint256) {
        VaultMSData.TokenBase memory _tokenInBase = vault.getTokenBase(_tokenIn);
        VaultMSData.TokenBase memory _tokenOutBase = vault.getTokenBase(_tokenOut);
        bool isStableSwap = _tokenInBase.isStable && _tokenOutBase.isStable;
        uint256 baseBps = isStableSwap ? stableSwapFeeBasisPoints: swapFeeBasisPoints;
        uint256 taxBps = isStableSwap ? stableTaxBasisPoints : taxBasisPoints;
        uint256 feesBasisPoints0 = getFeeBasisPoints(_tokenIn, _usdAmount, baseBps, taxBps, true);
        uint256 feesBasisPoints1 = getFeeBasisPoints(_tokenOut, _usdAmount, baseBps, taxBps, false);
        // use the higher of the two fee basis points
        return feesBasisPoints0 > feesBasisPoints1 ? feesBasisPoints0 : feesBasisPoints1;
    }

    // cases to consider
    // 1. initialAmount is far from targetAmount, action increases balance slightly => high rebate
    // 2. initialAmount is far from targetAmount, action increases balance largely => high rebate
    // 3. initialAmount is close to targetAmount, action increases balance slightly => low rebate
    // 4. initialAmount is far from targetAmount, action reduces balance slightly => high tax
    // 5. initialAmount is far from targetAmount, action reduces balance largely => high tax
    // 6. initialAmount is close to targetAmount, action reduces balance largely => low tax
    // 7. initialAmount is above targetAmount, nextAmount is below targetAmount and vice versa
    // 8. a large swap should have similar fees as the same trade split into multiple smaller swaps
    function getFeeBasisPoints(address _token, uint256 _usdDelta, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) public override view returns (uint256) {
        if (!hasDynamicFees) { return _feeBasisPoints; }

        VaultMSData.TokenBase memory _tokenInBase = vault.getTokenBase(_token);

        uint256 initialAmount = vault.tokenToUsdMin(_token, _tokenInBase.poolAmount);
        uint256 nextAmount = initialAmount.add(_usdDelta);
        if (!_increment) {
            nextAmount = _usdDelta > initialAmount ? 0 : initialAmount.sub(_usdDelta);
        }

        uint256 targetAmount = getTargetUsdAmount(_token);
        if (targetAmount == 0) { return _feeBasisPoints; }

        uint256 initialDiff = initialAmount > targetAmount ? initialAmount.sub(targetAmount) : targetAmount.sub(initialAmount);
        uint256 nextDiff = nextAmount > targetAmount ? nextAmount.sub(targetAmount) : targetAmount.sub(nextAmount);

        // action improves relative asset balance
        if (nextDiff < initialDiff) {
            uint256 rebateBps = _taxBasisPoints.mul(initialDiff).div(targetAmount);
            return rebateBps > _feeBasisPoints ? 0 : _feeBasisPoints.sub(rebateBps);
        }

        uint256 averageDiff = initialDiff.add(nextDiff).div(2);
        if (averageDiff > targetAmount) {
            averageDiff = targetAmount;
        }
        uint256 taxBps = _taxBasisPoints.mul(averageDiff).div(targetAmount);
        return _feeBasisPoints.add(taxBps);
    }


    function setErrorContenct(uint256[] memory _idxR, string[] memory _errorInstru) external onlyOwner{
        for(uint16 i = 0; i < _errorInstru.length; i++)
            errors[_idxR[i]] = _errorInstru[i];
    }

    function _validate(bool _condition, uint256 _errorCode) private view {
        require(_condition, string.concat(Strings.toString(_errorCode), errors[_errorCode]));
    }

    function tokenUtilization(address _token) public view  override returns (uint256) {
        VaultMSData.TokenBase memory tokenBase = vault.getTokenBase(_token);
        return tokenBase.poolAmount > 0 ? tokenBase.reservedAmount.mul(1000000).div(tokenBase.poolAmount) : 0;
    }


    function getTargetUsdAmount(address _token) public view returns (uint256){
        uint256 totalPoolUSD = 0;
        address[] memory fundingTokenList = IVaultStorage(vault.vaultStorage()).fundingTokenList();
        for(uint8 i = 0; i < fundingTokenList.length; i++){
            VaultMSData.TokenBase memory _tbe = vault.getTokenBase(fundingTokenList[i]);
            totalPoolUSD = totalPoolUSD.add(vault.tokenToUsdMin(fundingTokenList[i], _tbe.poolAmount));
        }
        VaultMSData.TokenBase memory tokenBase = vault.getTokenBase(_token);
        uint256 weight = tokenBase.weight;
        return totalPoolUSD > 0 && vault.totalTokenWeights() > 0 ? weight.mul(totalPoolUSD).div(vault.totalTokenWeights()) : 0;
    }

    function validLiq(address _account) public view override {
        if (inPrivateLiquidationMode) {
            require(isLiquidator[_account], "not liquidator");
        }
    }


}
