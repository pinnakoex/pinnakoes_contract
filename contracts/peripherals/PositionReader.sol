// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../core/interfaces/IVault.sol";
import "../core/interfaces/IVaultUtils.sol";
import "../core/interfaces/IVaultStorage.sol";
import "../core/VaultMSData.sol";
import "../core/interfaces/IPlpManager.sol";
import "../oracle/interfaces/IVaultPriceFeed.sol";
import "../tokens/interfaces/IMintable.sol";

interface IVaultTarget {
    function vaultUtils() external view returns (address);
    function vaultStorage() external view returns (address);
}

struct DispPosition {
    address account;
    address collateralToken;
    address indexToken;
    uint256 size;
    uint256 collateral;
    uint256 averagePrice;
    uint256 reserveAmount;
    uint256 lastUpdateTime;
    uint256 aveIncreaseTime;

    uint256 entryFundingRateSec;
    int256 entryPremiumRateSec;

    int256 realisedPnl;

    uint256 stopLossRatio;
    uint256 takeProfitRatio;

    bool isLong;

    bytes32 key;
    uint256 delta;
    bool hasProfit;

    int256 accPremiumFee;
    uint256 accFundingFee;
    uint256 accPositionFee;
    uint256 accCollateral;

    int256 pendingPremiumFee;
    uint256 pendingPositionFee;
    uint256 pendingFundingFee;

    uint256 indexTokenMinPrice;
    uint256 indexTokenMaxPrice;
}


struct DispToken {
    address token;

    //tokenBase part
    bool isFundable;
    bool isStable;
    uint256 decimal;
    uint256 targetWeight;   
    uint256 currentWeight;
    uint256 utilization;
    uint256 maxUSDAmounts;  
    uint256 balance;        // tokenBalances is used only to determine _transferIn values
    uint256 poolAmount;     // poolAmounts tracks the number of received tokens that can be used for leverage
    uint256 reservedAmount;    
    // uint256 guaranteedUsd;  
    uint256 poolInUsd;   
    uint256 availSize;

    //trec part
    uint256 shortSize;
    uint256 shortCollateral;
    uint256 shortAveragePrice;
    uint256 longSize;
    uint256 longCollateral;
    uint256 longAveragePrice;

    //fee part
    uint256 fundingRatePerHour; //borrow fee & token util

    int256 longRatePerHour;  //according to position
    int256 shortRatePerHour; //according to position

    //limit part
    uint256 maxShortSize;
    uint256 maxLongSize;
    uint256 maxTradingSize;
    uint256 maxRatio;
    uint256 countMinSize;

    //
    uint256 spreadBasis;
    uint256 maxSpreadBasis;// = 5000000 * PRICE_PRECISION;
    uint256 minSpreadCalUSD;// = 10000 * PRICE_PRECISION;

}

struct GlobalFeeSetting{
    uint256 taxBasisPoints; // 0.5%
    uint256 stableTaxBasisPoints; // 0.2%
    uint256 mintBurnFeeBasisPoints; // 0.3%
    uint256 swapFeeBasisPoints; // 0.3%
    uint256 stableSwapFeeBasisPoints; // 0.04%
    uint256 marginFeeBasisPoints; // 0.1%
    uint256 liquidationFeeUsd;
    uint256 maxLeverage; // 100x
    //Fees related to funding
    uint256 fundingRateFactor;
    uint256 stableFundingRateFactor;
    //trading tax part
    uint256 taxGradient;
    uint256 taxDuration;
    uint256 taxMax;
    //trading profit limitation part
    uint256 maxProfitRatio;
    uint256 premiumBasisPointsPerHour;
    int256 posIndexMaxPointsPerHour;
    int256 negIndexMaxPointsPerHour;
}

struct VaultBasicInfo{
    address vault;
    address plp;
    uint256 plpSupply;
    uint256 plpStaked;
    uint256 tokenAmount;
    uint256 aum;
    uint256 plpPrice;
    GlobalFeeSetting feeSetting;
    
}

contract PositionReader is Initializable {
    using SafeMath for uint256;

    address public nativeToken;
    IVaultPriceFeed public priceFeed;

    function initialize(address _nativeToken, address _priceFeed) public initializer {
        nativeToken = _nativeToken;
        priceFeed = IVaultPriceFeed(_priceFeed);
    }

    function getUserPositions(address _vault, address _account) public view returns (DispPosition[] memory){
        bytes32[] memory _keys = IVault(_vault).getUserKeys(_account, 0, 20);
        
        DispPosition[] memory _dps = new DispPosition[](_keys.length);

        IVaultUtils  vaultUtils = IVaultUtils(IVaultTarget(_vault).vaultUtils());
        for(uint256 i = 0; i < _keys.length; i++){
            VaultMSData.Position memory position = IVault(_vault).getPositionStructByKey(_keys[i]);
            VaultMSData.TradingFee memory tFee = IVault(_vault).getTradingFee(position.indexToken);
            VaultMSData.TradingFee memory tFundFee = IVault(_vault).getTradingFee(position.collateralToken);
            
            (bool _hasProfit, uint256 delta) = vaultUtils.getDelta(position, priceFeed.getPriceUnsafe(position.indexToken, !position.isLong, false, false));
            _dps[i].account = position.account;
            _dps[i].collateralToken = position.collateralToken;
            _dps[i].indexToken = position.indexToken;
            _dps[i].size = position.size;
            _dps[i].collateral = position.collateral;
            _dps[i].averagePrice = position.averagePrice;
            _dps[i].reserveAmount = position.reserveAmount;
            _dps[i].lastUpdateTime = position.lastUpdateTime;
            _dps[i].aveIncreaseTime = position.aveIncreaseTime;
            _dps[i].entryFundingRateSec = position.entryFundingRateSec;
            _dps[i].entryPremiumRateSec = position.entryPremiumRateSec;
            _dps[i].realisedPnl = position.realisedPnl;
            _dps[i].stopLossRatio = position.stopLossRatio;
            _dps[i].takeProfitRatio = position.takeProfitRatio;
            _dps[i].isLong = position.isLong;
            _dps[i].key = _keys[i];
            _dps[i].hasProfit = _hasProfit;
            _dps[i].delta = delta;

            _dps[i].accPremiumFee = position.accPremiumFee;
            _dps[i].accFundingFee = position.accFundingFee;
            _dps[i].accPositionFee = position.accPositionFee;
            _dps[i].accCollateral = position.accCollateral;

            _dps[i].pendingPremiumFee = vaultUtils.getPremiumFee(position, tFee);
            _dps[i].pendingPositionFee = vaultUtils.getPositionFee(position, position.size, tFee);
            _dps[i].pendingFundingFee = vaultUtils.getFundingFee(position, tFundFee);

            _dps[i].indexTokenMinPrice = IVault(_vault).getMinPrice(position.indexToken);
            _dps[i].indexTokenMaxPrice = IVault(_vault).getMaxPrice(position.indexToken);
        }
        return _dps;
    }


    function getTokenInfo(address _vault, address[] memory _fundTokens) public view returns (DispToken[] memory) {
        IVaultUtils  vaultUtils = IVaultUtils(IVaultTarget(_vault).vaultUtils());
        IVaultStorage  vaultStorage = IVaultStorage(IVaultTarget(_vault).vaultStorage());
        DispToken[] memory _dispT = new DispToken[](_fundTokens.length);
        IVault vault = IVault(_vault);
        uint256 accumPU = 0;
        for(uint256 i = 0; i < _dispT.length; i++){
            if (_fundTokens[i] == address(0))
                _fundTokens[i] = nativeToken;

            if (!vault.isFundingToken(_fundTokens[i]) && !vault.isTradingToken(_fundTokens[i]))
                continue;
                
            VaultMSData.TokenBase memory _tBase = vault.getTokenBase(_fundTokens[i]);
            VaultMSData.TradingRec memory _tRec = vault.getTradingRec(_fundTokens[i]);
            VaultMSData.TradingFee memory _tFee = vault.getTradingFee(_fundTokens[i]);


            _dispT[i].token = _fundTokens[i];
            _dispT[i].isFundable = _tBase.isFundable;
            _dispT[i].isStable = _tBase.isStable;
            _dispT[i].decimal = IMintable(_fundTokens[i]).decimals();
            _dispT[i].targetWeight = _tBase.weight;  
            _dispT[i].maxUSDAmounts = _tBase.maxUSDAmounts;  
            _dispT[i].balance = _tBase.balance;        
            _dispT[i].poolAmount = _tBase.poolAmount;
            _dispT[i].reservedAmount = _tBase.reservedAmount; 
            // _dispT[i].guaranteedUsd = IVault(_vault).guaranteedUsd(_fundTokens[i]);  
            _dispT[i].utilization = _tBase.poolAmount > 0 ? _tBase.reservedAmount.mul(1000000).div(_tBase.poolAmount) : 0;  
            _dispT[i].poolInUsd = priceFeed.tokenToUsdUnsafe(_fundTokens[i], _tBase.poolAmount, false);
            _dispT[i].currentWeight = 0;
            if (_tBase.isFundable)
                accumPU = accumPU.add(_dispT[i].poolInUsd);

            _dispT[i].availSize = priceFeed.tokenToUsdUnsafe(_fundTokens[i], _tBase.poolAmount.sub(_tBase.reservedAmount), false);

            //trading rec
            _dispT[i].shortSize = _tRec.shortSize;  
            _dispT[i].shortCollateral = _tRec.shortCollateral;  
            _dispT[i].shortAveragePrice = _tRec.shortAveragePrice;  
            _dispT[i].longSize = _tRec.longSize;  
            _dispT[i].longCollateral = _tRec.longCollateral;  
            _dispT[i].longAveragePrice = _tRec.longAveragePrice;

            //fee part
            // _dispT[i].fundingRatePerSec = _tFee.fundingRatePerSec;  
            _dispT[i].fundingRatePerHour = _tFee.fundingRatePerSec.mul(3600).div(10000);  
             
            // _dispT[i].longRatePerSec = _tFee.longRatePerSec;  
            _dispT[i].longRatePerHour = _tFee.longRatePerSec * 3600 / 10000;  

            // _dispT[i].shortRatePerSec = _tFee.shortRatePe4rSec;  
            _dispT[i].shortRatePerHour = _tFee.shortRatePerSec * 3600 / 10000;  

            // VaultMSData.TradingTax memory _tTax = vaultUtils.getTradingTax(_fundTokens[i]);
            VaultMSData.TradingLimit memory _tLim = vaultStorage.getTradingLimit(_fundTokens[i]);
            _dispT[i].maxShortSize = _tLim.maxShortSize;  
            _dispT[i].maxLongSize = _tLim.maxLongSize;  
            _dispT[i].maxTradingSize = _tLim.maxTradingSize;  
            _dispT[i].maxRatio = _tLim.maxRatio;  
            _dispT[i].countMinSize = _tLim.countMinSize;

            _dispT[i].spreadBasis = vaultUtils.spreadBasis(_fundTokens[i]);
            _dispT[i].maxSpreadBasis = vaultUtils.maxSpreadBasis(_fundTokens[i]);
            _dispT[i].minSpreadCalUSD = vaultUtils.minSpreadCalUSD(_fundTokens[i]);
        }

        for(uint256 i = 0; i < _dispT.length; i++){
            if (_dispT[i].isFundable)
                _dispT[i].currentWeight = accumPU > 0 ? _dispT[i].currentWeight.mul(1000000).div(accumPU) : 0;
        }
        
        return _dispT;
    }


    function getGlobalFeeInfo(address _vault) public view returns (GlobalFeeSetting memory){//Fees related to swap
        GlobalFeeSetting memory gFS;
        IVaultUtils  vaultUtils = IVaultUtils(IVaultTarget(_vault).vaultUtils());
        gFS.taxBasisPoints = vaultUtils.taxBasisPoints();

        gFS.stableTaxBasisPoints = vaultUtils.stableTaxBasisPoints();
        gFS.mintBurnFeeBasisPoints = vaultUtils.mintBurnFeeBasisPoints();
        gFS.swapFeeBasisPoints = vaultUtils.swapFeeBasisPoints();
        gFS.stableSwapFeeBasisPoints = vaultUtils.stableSwapFeeBasisPoints();

        gFS.marginFeeBasisPoints = vaultUtils.marginFeeBasisPoints();
        gFS.liquidationFeeUsd = vaultUtils.liquidationFeeUsd();
        gFS.maxLeverage = vaultUtils.maxLeverage();
        gFS.fundingRateFactor = vaultUtils.fundingRateFactor();
        gFS.stableFundingRateFactor = vaultUtils.stableFundingRateFactor();
        gFS.taxDuration = vaultUtils.taxDuration();
        gFS.taxMax = vaultUtils.taxMax();
        gFS.taxGradient = gFS.taxDuration > 0 ? gFS.taxMax.div(gFS.taxDuration) : 0;


        gFS.maxProfitRatio = vaultUtils.maxProfitRatio();
        gFS.premiumBasisPointsPerHour = vaultUtils.premiumBasisPointsPerHour();
        gFS.posIndexMaxPointsPerHour = vaultUtils.posIndexMaxPointsPerHour();
        gFS.negIndexMaxPointsPerHour = vaultUtils.negIndexMaxPointsPerHour();
        return gFS;
    }


    // function getVaultInfo(address _vault)external view returns (VaultBasicInfo memory, DispToken[] memory, DispToken[] memory){
    //     VaultBasicInfo memory vbi;
        
    //     vbi.vault = _vault;
    //     vbi.plp = ILpManager(lpManager).plpToken(_vault);
    //     vbi.plpSupply = IERC20(vbi.plp).totalSupply();
    //     vbi.plpStaked = 0;
    //     vbi.tokenAmount = 0;
    //     vbi.aum = IPlpManager(ILpManager(lpManager).plpManager(_vault)).getAum(false);
    //     vbi.plpPrice = vbi.plpSupply > 0 ? vbi.aum.div(vbi.plpSupply).mul(10**IMintable(vbi.plp).decimals()) : 10**30;
    //     vbi.feeSetting = getGlobalFeeInfo(_vault);
    
    //     DispToken[] memory funding_list = getTokenInfo(_vault, IVault(_vault).fundingTokenList());
    //     DispToken[] memory trading_list = getTokenInfo(_vault, IVault(_vault).tradingTokenList());

    //     return (vbi, funding_list, trading_list);
    // }




}