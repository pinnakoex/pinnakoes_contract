// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/ITimelockTarget.sol";
import "./interfaces/ITimelock.sol";
import "../core/interfaces/IVault.sol";
import "../core/interfaces/IVaultUtils.sol";
import "../core/interfaces/ILpManager.sol";


contract Timelock is ITimelock, Ownable {
    using SafeMath for uint256;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant MAX_BUFFER = 5 days;

    uint256 public buffer = 1 hours;

    mapping (bytes32 => uint256) public pendingActions;

    event SignalPendingAction(bytes32 action);
    event SignalApprove(address token, address spender, uint256 amount, bytes32 action);
    event SignalWithdrawToken(address target, address token, address receiver, uint256 amount, bytes32 action);
    event SignalMint(address token, address receiver, uint256 amount, bytes32 action);
    event SignalSetMinter(address token, address minter, bool status, bytes32 action);
    event SignalSetGov(address target, address gov, bytes32 action);
    event SignalSetHandler(address target, address handler, bool isActive, bytes32 action);
    event SignalSetPriceFeed(address vault, address priceFeed, bytes32 action);
    event SignalRedeemUsdx(address vault, address token, uint256 amount);
    event SignalVaultSetTokenConfig(
        address vault,
        address token,
        uint256 tokenDecimals,
        uint256 tokenWeight,
        uint256 minProfitBps,
        uint256 maxUsdxAmount,
        bool isStable,
        bool isShortable
    );
    event ClearAction(bytes32 action);

    event SignalSetTokenChainlinkConfig(address _target, address _token, address _chainlinkContract, bool _isStrictStable);

    function setBuffer(uint256 _buffer) external onlyOwner {
        require(_buffer <= MAX_BUFFER, "Timelock: invalid _buffer");
        require(_buffer > buffer, "Timelock: buffer can not be decreased");
        buffer = _buffer;
    }


    //for pricefeed
    function setSpreadBasisPf(address _contract, address _token, uint256 _spreadBasis, uint256 _maxSpreadBasisUSD, uint256 _minSpreadBasisUSD) external onlyOwner {
        ITimelockTarget(_contract).setSpreadBasis(_token, _spreadBasis, _maxSpreadBasisUSD, _minSpreadBasisUSD);
    }

    function setPriceMethod(address _contract,uint8 _setT) external onlyOwner{
        ITimelockTarget(_contract).setPriceMethod(_setT);
    }

    function setPriceVariance(address _contract,uint256 _priceVariance) external onlyOwner {
        ITimelockTarget(_contract).setPriceVariance(_priceVariance);
    }

    function setSafePriceTimeGap(address _contract, uint256 _gap) external onlyOwner {
        ITimelockTarget(_contract).setSafePriceTimeGap(_gap);
    }
    function setPositionRouter(address _contract, address[] memory _positionRouters) public onlyOwner {
        ITimelockTarget(_contract).setPositionRouter(_positionRouters);
    }


    //---------- for vault ----------
    function setRouter(address _vault, address _router, bool _status) external onlyOwner {
        IVault(_vault).setRouter(_router, _status);
    }

    function setVaultManager(address _vault, address _user, bool _status) external onlyOwner {
        IVault(_vault).setManager(_user, _status);
    }

    function setMaxLeverage(address _vault, uint256 _maxLeverage) external onlyOwner {
        IVaultUtils(ITimelockTarget(_vault).vaultUtils()).setMaxLeverage(_maxLeverage);
    }

    function setFundingRate(address _target, uint256 _fundingRateFactor, uint256 _stableFundingRateFactor) external onlyOwner {
        ITimelockTarget(_target).setFundingRate(_fundingRateFactor, _stableFundingRateFactor);
    }

    function setTaxRate(address _target, uint256 _taxMax, uint256 _taxTime) external onlyOwner {
        ITimelockTarget(_target).setTaxRate(_taxMax, _taxTime);
    }

    // assign _marginFeeBasisPoints to this.marginFeeBasisPoints
    // because enableLeverage would update Vault.marginFeeBasisPoints to this.marginFeeBasisPoints
    // and disableLeverage would reset the Vault.marginFeeBasisPoints to this.maxMarginFeeBasisPoints
    function setFees(
        address _vault,
        uint256 _taxBasisPoints,
        uint256 _stableTaxBasisPoints,
        uint256 _mintBurnFeeBasisPoints,
        uint256 _swapFeeBasisPoints,
        uint256 _stableSwapFeeBasisPoints,
        uint256 _marginFeeBasisPoints,
        uint256 _liquidationFeeUsd,
        bool _hasDynamicFees
    ) external onlyOwner {
        IVaultUtils vaultUtils = IVaultUtils(ITimelockTarget(_vault).vaultUtils());

        vaultUtils.setFees(
            _taxBasisPoints,
            _stableTaxBasisPoints,
            _mintBurnFeeBasisPoints,
            _swapFeeBasisPoints,
            _stableSwapFeeBasisPoints,
            _marginFeeBasisPoints,
            _liquidationFeeUsd,
            _hasDynamicFees
        );
    }

    function setTokenConfig(address _vault, address _token,
        uint256 _tokenDecimals,
        uint256 _tokenWeight,
        uint256 _maxUSDAmount,
        bool _isStable,
        bool _isFundingToken,
        bool _isTradingToken) external  onlyOwner {
        // require(_minProfitBps <= 500, "Timelock: invalid _minProfitBps");
        IVault(_vault).setTokenConfig(
            _token,
            _tokenWeight,
            _isStable,
            _isFundingToken,
            _isTradingToken
        );
    }
    function clearTokenConfig(address _vault, address _token, bool _del) external onlyOwner {
        IVault(_vault).clearTokenConfig(_token, _del);
    }

    function setAdd(address _vault, address[] memory _addList) external onlyOwner {
        IVault(_vault).setAdd(_addList);
    }
    function setInPrivateLiquidationMode(address _vaultUtils, bool _inPrivateLiquidationMode) external onlyOwner {
        IVaultUtils(_vaultUtils).setInPrivateLiquidationMode(_inPrivateLiquidationMode);
    }

    function setVaultLiquidator(address _vaultUtils, address _liquidator, bool _isActive) external onlyOwner {
        IVaultUtils(_vaultUtils).setLiquidator(_liquidator, _isActive);
    }

    function setSpreadBasis(address _vaultUtils, address _token, uint256 _spreadBasis, uint256 _maxSpreadBasis, uint256 _minSpreadCalUSD) external onlyOwner {
        ITimelockTarget(_vaultUtils).setSpreadBasis(_token, _spreadBasis, _maxSpreadBasis, _minSpreadCalUSD);
    }




    function transferIn(address _sender, address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).transferFrom(_sender, address(this), _amount);
    }

    function setMaxGlobalSize(address _target, address _token, uint256 _amountLong, uint256 _amountShort) external onlyOwner {
        ITimelockTarget(_target).setMaxGlobalSize(_token, _amountLong, _amountShort);
    }

    function setPositionKeeper(address _target, address _keeper, bool _status) external onlyOwner {
        ITimelockTarget(_target).setPositionKeeper(_keeper, _status);
    }
    function setMinExecutionFee(address _target, uint256 _minExecutionFee) external onlyOwner {
        ITimelockTarget(_target).setMinExecutionFee(_minExecutionFee);
    }
    function setCooldownDuration(address _target, uint256 _cooldownDuration) external onlyOwner{
        ITimelockTarget(_target).setCooldownDuration(_cooldownDuration);
    }
    function setOrderKeeper(address _target, address _account, bool _isActive) external onlyOwner {
        ITimelockTarget(_target).setOrderKeeper(_account, _isActive);
    }
    function setLiquidator(address _target, address _account, bool _isActive) external onlyOwner {
        ITimelockTarget(_target).setLiquidator(_account, _isActive);
    }
    function setPartner(address _target, address _account, bool _isActive) external onlyOwner {
        ITimelockTarget(_target).setPartner(_account, _isActive);
    }

    //For Router:
    function setESBT(address _target, address _esbt) external onlyOwner {
        ITimelockTarget(_target).setESBT(_esbt);
    }
    function setInfoCenter(address _target, address _infCenter) external onlyOwner {
        ITimelockTarget(_target).setInfoCenter(_infCenter);
    }
    function addPlugin(address _target, address _plugin) external onlyOwner {
        ITimelockTarget(_target).addPlugin(_plugin);
    }
    function removePlugin(address _target, address _plugin) external onlyOwner {
        ITimelockTarget(_target).removePlugin(_plugin);
    }

    //For ELP
    function setFeeToPoolRatio(address _target, uint256 _feeToPoolRatio) external onlyOwner {
        ITimelockTarget(_target).setFeeToPoolRatio(_feeToPoolRatio);
    }

    //For Pricefeed
    function setSpreadBasisPoints(address _target, address _token, uint256 _spreadBasisPoints) external onlyOwner {
        ITimelockTarget(_target).setSpreadBasisPoints( _token, _spreadBasisPoints);
    }

    function setUpdater(address _target,address _account, bool _isActive) external onlyOwner {
        ITimelockTarget(_target).setUpdater( _account, _isActive);
    }


    //----------------------------- Timelock functions
    function signalApprove(address _token, address _spender, uint256 _amount) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("approve", _token, _spender, _amount));
        _setPendingAction(action);
        emit SignalApprove(_token, _spender, _amount, action);
    }
    function approve(address _token, address _spender, uint256 _amount) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("approve", _token, _spender, _amount));
        _validateAction(action);
        _clearAction(action);
        IERC20(_token).approve(_spender, _amount);
    }


    function signalWithdrawToken(address _target, address _receiver, address _token, uint256 _amount) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("withdrawToken",_target, _receiver, _token, _amount));
        _setPendingAction(action);
        emit SignalWithdrawToken(_target, _token, _receiver, _amount, action);
    }
    function withdrawToken(
        address _target,
        address _receiver,
        address _token,
        uint256 _amount
    ) external  onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("withdrawToken",_target,  _receiver, _token, _amount));
        _validateAction(action);
        _clearAction(action);
        ITimelockTarget(_target).withdrawToken(_receiver, _token, _amount);
    }

    function signalSetMinter(address _token, address _minter, bool _status) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("mint", _token, _minter, _status));
        _setPendingAction(action);
        emit SignalSetMinter(_token, _minter, _status, action);
    }
    function setMinter(address _token, address _minter, bool _status) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("mint", _token, _minter, _status));
        _validateAction(action);
        _clearAction(action);
        ITimelockTarget(_token).setMinter(_minter, _status);
    }


    function signalMint(address _token, address _receiver, uint256 _amount) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("mint", _token, _receiver, _amount));
        _setPendingAction(action);
        emit SignalMint(_token, _receiver, _amount, action);
    }
    function mint(address _token, address _receiver, uint256 _amount) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("mint", _token, _receiver, _amount));
        _validateAction(action);
        _clearAction(action);
        ITimelockTarget(_token).mint(_receiver, _amount);
    }


    function signalSetGov(address _target, address _gov) external override onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("setGov", _target, _gov));
        _setPendingAction(action);
        emit SignalSetGov(_target, _gov, action);
    }
    function setGov(address _target, address _gov) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("setGov", _target, _gov));
        _validateAction(action);
        _clearAction(action);
        ITimelockTarget(_target).setGov(_gov);
    }


    function signalTransOwner(address _target, address _gov) external override onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("transOwner", _target, _gov));
        _setPendingAction(action);
        emit SignalSetGov(_target, _gov, action);
    }
    function transOwner(address _target, address _gov) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("transOwner", _target, _gov));
        _validateAction(action);
        _clearAction(action);
        ITimelockTarget(_target).transferOwnership(_gov);
    }

    function signalSetHandler(address _target, address _handler, bool _isActive) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("setHandler", _target, _handler, _isActive));
        _setPendingAction(action);
        emit SignalSetHandler(_target, _handler, _isActive, action);
    }
    function setHandler(address _target, address _handler, bool _isActive) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("setHandler", _target, _handler, _isActive));
        _validateAction(action);
        _clearAction(action);
        ITimelockTarget(_target).setHandler(_handler, _isActive);
        emit SignalSetHandler(_target, _handler, _isActive, action);
    }


    function signalSetTokenChainlinkConfig(address _target, address _token, address _chainlinkContract, bool _isStrictStable) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("setTokenChainlinkConfig",  _target, _token, _chainlinkContract, _isStrictStable));
        _setPendingAction(action);
        emit SignalSetTokenChainlinkConfig(_target, _token, _chainlinkContract, _isStrictStable);
    }
    function setTokenChainlinkConfig(address _target, address _token, address _chainlinkContract, bool _isStrictStable) external onlyOwner {
        bytes32 action = keccak256(abi.encodePacked("setTokenChainlinkConfig",  _target, _token, _chainlinkContract, _isStrictStable));
        _validateAction(action);
        _clearAction(action);
        ITimelockTarget(_target).setTokenChainlinkConfig(_token, _chainlinkContract, _isStrictStable);
    }


    function cancelAction(bytes32 _action) external onlyOwner {
        _clearAction(_action);
    }

    function _setPendingAction(bytes32 _action) private {
        require(pendingActions[_action] == 0, "Timelock: action already signalled");
        pendingActions[_action] = block.timestamp.add(buffer);
        emit SignalPendingAction(_action);
    }

    function _validateAction(bytes32 _action) private view {
        require(pendingActions[_action] != 0, "Timelock: action not signalled");
        require(pendingActions[_action] < block.timestamp, "Timelock: action time not yet passed");
    }

    function _clearAction(bytes32 _action) private {
        require(pendingActions[_action] != 0, "Timelock: invalid _action");
        delete pendingActions[_action];
        emit ClearAction(_action);
    }
}