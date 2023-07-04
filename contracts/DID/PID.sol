// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IPID.sol";
import "../data/DataStore.sol";
import "../utils/interfaces/INFTUtils.sol";
import "./PIDData.sol";


interface IAcitivity {
    function updateCompleteness(address _account) external returns (bool);
    function balanceOf(address _account) external view returns (uint256);
}

interface IPIDLogic {
    function toRank(address _account, uint256 _score) external view returns (uint256);
}

contract PID is ReentrancyGuard, Ownable, IERC721, IERC721Metadata, IPID, DataStore{
    using SafeMath for uint256;
    using Strings for uint256;
    using Address for address;

    string internal _baseImgURI;// Base token URI
    string internal _name = "PNK Soul Bound Token";// 

    address public nftUtils;
    address public pidLogic;

    uint256 public scoreDecreasePercentInterval = 5000; //5% per 7 days
    uint256 public scoreDecInterval = 7 days;
    uint256 public scoreDecMaxRound = 20;

    uint256[] public scoreToRank;
    uint256[] public rankToReb;
    uint256[] public rankToDis;
    PIDData.PIDStr[] private _tokens;// 

    mapping(address => uint256) private _balances;
    mapping(uint256 => uint256) public override scorePara;
    mapping(address => uint256) public override addressToTokenID;
    mapping(string => address) public refCodeOwner;
   

    mapping(address => mapping(uint256 => uint256)) public override tradeVol;
    mapping(address => mapping(uint256 => uint256)) public override swapVol;
    mapping(uint256 => uint256) public override totalTradeVol;
    mapping(uint256 => uint256) public override totalSwapVol;
    
    event UpdateTrade(address account, uint256 volUsd, uint256 day);
    event UpdateSwap(address account, uint256 volUsd, uint256 day);
    
    event ScoreUpdate(address _account, address _fromAccount, uint256 _addition, uint256 _reasonCode);
    event ScoreDecrease(address _account, uint256 _preScore, uint256 _latestScore, uint256 _timegap);
    event RankUpdate(address _account, uint256 _rankP, uint256 _rankA);
    event UpdateFee(address _account, uint256 _origFee, uint256 _discountedFee, address _parent, uint256 _rebateFee);

    constructor(address _NFTUtils) {
        require(_NFTUtils != address(0), "empty NFTUtils address");
        nftUtils = _NFTUtils;
        uint256 cur_time = block.timestamp;
        string memory defRC =  INFTUtils(nftUtils).genReferralCode(0);
        if (refCodeOwner[defRC]!= address(0))
            defRC = string(abi.encodePacked(defRC, cur_time));
        PIDData.PIDStr memory _PIDStr = PIDData.PIDStr(address(this), "PID OFFICIAL", defRC, cur_time, block.timestamp, 0, 0);
        _tokens.push(_PIDStr);
        addressToTokenID[address(this)] = 0;
        refCodeOwner[defRC] = address(this);
        _balances[address(this)] = 1;
        //set default:
        scorePara[1] = 10;  //score_trade increase own per 1000U
        scorePara[2] = 2;   //score_trade increase ref per 1000U
        scorePara[101] = 10;//score_trade decrease own per 1000U
        scorePara[102] = 2; //score_tradeOwn per 1000U

        scorePara[3] = 10;  //score swap Own per 1000U
        scorePara[4] = 2;   //score_swap ref per 1000U

        scorePara[5] = 10;  //score_addLiq Own per 1000U
        scorePara[6] = 2;   //score_addLiq ref per 1000U
        scorePara[105] = 10;//score_remove Liq Own per 1000U
        scorePara[106] = 2; //score_remove Liq ref per 1000U

        scorePara[8] = 5;   //invite create Account
    }

    modifier onlyScoreUpdater() {
        require(hasAddressSet(PIDData.VALID_SCORE_UPDATER, msg.sender), "unauthorized updater");
        _;
    }

    //--------------------- Owner setting
    function setScorePara(uint256 _id, uint256 _value) public onlyOwner {
        scorePara[_id] = _value;
    }
    function setAddress(address _nftUtils, address _pidLogic) public onlyOwner {
        nftUtils = _nftUtils;
        pidLogic = _pidLogic;
    }
    function setUintValue(bytes32 _bIdx, uint256 _value) public onlyOwner {
        setUint(_bIdx, _value);
    }
    function setUintValueByString(string memory _strIdx, uint256 _value) public onlyOwner {
        setUint(keccak256(abi.encodePacked(_strIdx)), _value);
    }
    function setAddVal(bytes32 _bIdx, address _add, uint256 _val) public onlyOwner {
        setAddUint(_add, _bIdx, _val);
    }
    function setScoreToRank(uint256[] memory _minValue) external onlyOwner{
        require(_minValue.length > 3 && _minValue[0] == 0, "invalid score-rank setting");
        scoreToRank = _minValue;
    }
    function setDisReb(uint256[] memory _dis, uint256[] memory _reb) external onlyOwner{
        require(scoreToRank.length +1 == _dis.length && _dis.length == _reb.length, "invalid dis-reb setting");
        rankToReb = _reb;
        rankToDis = _dis;
    }

    function setScorePlan(uint256 _decPerInterval, uint256 _decInterval, uint256 _scoreDecMaxRound) external onlyOwner {
        require(_decPerInterval <= PIDData.PERCENT_PRECISION, "invalid Decreasefactor");
        scoreDecreasePercentInterval = _decPerInterval;
        scoreDecInterval = _decInterval;
        scoreDecMaxRound = _scoreDecMaxRound;
    }
    function setScoreUpdater(address _updater, bool _status) external onlyOwner {
        if (_status){
            safeGrantAddressSet(PIDData.VALID_SCORE_UPDATER, _updater);
        }
        else{
            safeRevokeAddressSet(PIDData.VALID_SCORE_UPDATER, _updater);
        }
    }



    //================= PID creation =================
    function safeMint(string memory _refCode) external nonReentrant returns (string memory) {
        // require(tx.origin == msg.sender && !msg.sender.isContract(), "onlyEOA");
        return _mint(msg.sender, _refCode, "PID User");
    }

    function mintWithName(string memory _refCode, string memory _nickName) external nonReentrant returns (string memory) {
        return _mint(msg.sender, _refCode, _nickName);
    }

    function mintDefault( ) external nonReentrant returns (string memory) {
        return _mint(msg.sender, defaultRefCode(), "DefaultName");
    }

    function _mint(address _newAccount, string memory _refCode, string memory _nickName) internal returns (string memory) {
        require(balanceOf(_newAccount) == 0, "already minted.");
        //check mint requirements
        require(userSizeSum(_newAccount) >= getUint(PIDData.MIN_MINT_TRADING_VALUE), "Min. trading value not satisfied.");
        //check referal
        address _referalAccount = refCodeOwner[_refCode];
        require(_referalAccount != address(0) && balanceOf(_referalAccount) > 0, "Invalid referal Code");
        
        INFTUtils nftUtil = INFTUtils(nftUtils);
        uint256 _tId = _tokens.length;
        string memory refC = nftUtil.genReferralCode(_tId);
        uint256 cur_time = block.timestamp;

        _balances[_newAccount] += 1;
        PIDData.PIDStr memory _PIDStr = PIDData.PIDStr(_newAccount, _nickName, refC, cur_time, cur_time, 0, 0);
        _tokens.push(_PIDStr);
        addressToTokenID[_newAccount] = _tId;
        refCodeOwner[refC] = _newAccount;
        grantAddMpAddressSetForAccount(_newAccount, PIDData.REFERRAL_PARRENT, _referalAccount);
        updateReferralForAccount(_newAccount, _referalAccount);
        updateScore(_referalAccount, _newAccount, scorePara[8] * PIDData.SCORE_PRECISION, 0);
        return refC;        
    }

    function setNickName(string memory _setNN) external {
        address _account = msg.sender;
        require(balanceOf(_account) == 1, "invald holder");
        _tokens[addressToTokenID[_account]].nickName = _setNN;
    }

    function updateUserRS(address _account) external {
        updateScore(_account, _account, 0, 999);
    }

    function rankToDiscount(uint256 _rank) public override view returns (uint256, uint256){
        return (rankToDis[_rank], rankToReb[_rank]);
    }

    function accountToDisReb(address _account) public override view returns (uint256, uint256){
        if (balanceOf(_account)!= 1) return (0,0);
        return rankToDiscount(rank(_account));
    }

    function score(address _account) public override view returns (uint256) {
        if(balanceOf(_account) != 1)
            return 0;
        PIDData.PIDStr storage pidStr = _tokens[addressToTokenID[_account]];
        (uint256 latest_score, uint256 _updTime) = getLatestScore(pidStr.score, pidStr.latestUpdateTime);
        return latest_score;
    }
    function rank(address _account) public override view returns (uint256){
        if (balanceOf(_account)!= 1) return 0;
        return IPIDLogic(pidLogic).toRank(_account, score(_account));
    }

    function getFeeDet(address _account, uint256 _origFee) external view override returns (uint256, uint256, address){
        if (balanceOf(_account)!= 1) return (0,0, address(0));
        (address[] memory _par, ) = getReferralForAccount(_account);
        if (_par.length != 1) return (0,0, address(0));

        (uint256 dis_per,  ) = accountToDisReb(_account);
        ( , uint256 reb_per) = accountToDisReb(_par[0]);

        uint256 _discountedFee = _origFee.mul(dis_per).div(PIDData.PERCENT_PRECISION);
        uint256 _rebateFee = _origFee.mul(reb_per).div(PIDData.PERCENT_PRECISION);
        if (_rebateFee.add(_discountedFee) >= _origFee){
            _rebateFee = 0;
            _discountedFee = 0;
        }
        return (_discountedFee, _rebateFee, _par[0]);
    }

    function updateScoreForAccount(address _account, address /*_vault*/, uint256 _amount, uint256 _reasonCode) external onlyScoreUpdater override {
        (address[] memory _par, ) = getReferralForAccount(_account);
        updateScore(_account, _account, _amount.mul(scorePara[_reasonCode]).div(1000).div(PIDData.USD_TO_SCORE_PRECISION),_reasonCode);
        if (_par.length == 1)
            updateScore(_par[0], _account, _amount.mul(scorePara[1000 + _reasonCode]).div(1000).div(PIDData.USD_TO_SCORE_PRECISION), 1000 + _reasonCode);
    }

    function updateTradingScoreForAccount(address _account, address /*_vault*/, uint256 _amount, uint256 _refCode) external onlyScoreUpdater override {
        // require(_refCode == 0 || _refCode == 100, "invalid ref code");
        incrementAddUint(_account, PIDData.ACCUM_POSITIONSIZE, _amount);
        (address[] memory _par, ) = getReferralForAccount(_account);
        updateScore(_account, _account, _amount.mul(scorePara[1 + _refCode]).div(1000).div(PIDData.USD_TO_SCORE_PRECISION), 1 + _refCode);
        _updateTrade(_account, _amount);
        if (_par.length == 1)
            updateScore(_par[0], _account, _amount.mul(scorePara[2 + _refCode]).div(1000).div(PIDData.USD_TO_SCORE_PRECISION), 11 + _refCode);
    }

    function updateSwapScoreForAccount(address _account, address /*_vault*/, uint256 _amount) external onlyScoreUpdater override{
        (address[] memory _par,  ) = getReferralForAccount(_account);
        incrementAddUint(_account, PIDData.ACCUM_SWAP, _amount);
        updateScore(_account, _account, _amount.mul(scorePara[3]).div(1000).div(PIDData.USD_TO_SCORE_PRECISION), 2);
        _updateSwap(_account, _amount);
        if (_par.length == 1)
            updateScore(_par[0], _account, _amount.mul(scorePara[4]).div(1000).div(PIDData.USD_TO_SCORE_PRECISION), 12);
    }

    function updateAddLiqScoreForAccount(address _account, address /*_vault*/, uint256 _amount, uint256 _refCode) external onlyScoreUpdater override {
        (address[] memory _par,  ) = getReferralForAccount(_account);
        incrementAddUint(_account, PIDData.ACCUM_ADDLIQUIDITY, _amount);
        updateScore(_account,  _account, _amount.mul(scorePara[5 + _refCode]).div(1000).div(PIDData.USD_TO_SCORE_PRECISION), 3 + _refCode);
        if (_par.length == 1)
            updateScore(_par[0], _account, _amount.mul(scorePara[6 + _refCode]).div(1000).div(PIDData.USD_TO_SCORE_PRECISION), 13 + _refCode);
    }

    function _updateTrade(address _account, uint256 _volUsd) private {
        uint256 _day = block.timestamp.div(86400);
        tradeVol[_account][_day] = tradeVol[_account][_day].add(_volUsd);
        totalTradeVol[_day] = totalTradeVol[_day].add(_day);
        emit UpdateTrade(_account, _volUsd, _day);
    }

    function _updateSwap(address _account, uint256 _volUsd) private {
        uint256 _day = block.timestamp.div(86400);
        swapVol[_account][_day] = swapVol[_account][_day].add(_volUsd);
        totalSwapVol[_day] = totalSwapVol[_day].add(_day);
        emit UpdateSwap(_account, _volUsd, _day);
    }


    function getLatestScore(uint256 _score, uint256 _updTime) public view returns (uint256, uint256){
        uint256 cur_time = block.timestamp;
        uint256 upd_t = _updTime;
        if(cur_time < _updTime || cur_time.sub(_updTime) < scoreDecInterval){
            return (_score, upd_t);
        } 

        uint256 dec_interv = cur_time.sub(_updTime).div(scoreDecInterval);
        uint256 do_round = dec_interv > scoreDecMaxRound ? scoreDecMaxRound : dec_interv ;
        for(uint256 i = 0; i < do_round; i++){
            _score = _score.mul(PIDData.PERCENT_PRECISION.sub(scoreDecreasePercentInterval)).div(PIDData.PERCENT_PRECISION);
            upd_t = upd_t.add(scoreDecInterval);
        }
        return (_score, upd_t);
    }


    function updateScore(address _account, address _fromAccount, uint256 _amount, uint256 _reasonCode) private {
        if(balanceOf(_account) != 1)
            return;
        PIDData.PIDStr storage pidStr = _tokens[addressToTokenID[_account]];
        (uint256 latest_score, uint256 _updTime) = getLatestScore(pidStr.score, pidStr.latestUpdateTime);
        if (latest_score != pidStr.score){
            emit ScoreDecrease(_account, pidStr.score, latest_score, pidStr.latestUpdateTime);
            pidStr.score = latest_score;
            pidStr.latestUpdateTime = _updTime;
        }
        pidStr.score = pidStr.score.add(_amount);
        pidStr.score_acum = pidStr.score_acum.add(_amount);
        emit ScoreUpdate(_account, _fromAccount, _amount, _reasonCode);
    }

    //================= Internal Functions =================
    function updateReferralForAccount(address _account_child, address _account_parrent) internal {
        require(getAddMpBytes32SetCount(_account_child, PIDData.REFERRAL_PARRENT) == 0, "Parrent already been set");
        require(!hasAddMpAddressSet(_account_parrent, PIDData.REFERRAL_CHILD, _account_child), "Child already exist");
        grantAddMpAddressSetForAccount(_account_parrent,PIDData.REFERRAL_CHILD, _account_child);
        grantAddMpAddressSetForAccount(_account_child, PIDData.REFERRAL_PARRENT, _account_parrent);
    }

    //=================Public data reading =================
    function getReferralForAccount(address _account) public override view returns (address[] memory , address[] memory){
        uint256 childNum = getAddMpAddressSetCount(_account, PIDData.REFERRAL_CHILD);
        return (getAddMpAddressSetRoles(_account, PIDData.REFERRAL_PARRENT, 0, 1),
                getAddMpAddressSetRoles(_account, PIDData.REFERRAL_CHILD, 0, childNum));
    }

    function getPIDAddMpUintetRoles(address _mpaddress, bytes32 _key) public override view returns (uint256[] memory) {
        return getAddMpUintetRoles(_mpaddress, _key, 0, getAddMpUintSetCount(_mpaddress, _key));
    }
    
    function userSizeSum(address _account) public override view returns (uint256){
        return getAddUint(_account, PIDData.ACCUM_POSITIONSIZE).add(getAddUint(_account, PIDData.ACCUM_SWAP)).add(getAddUint(_account, PIDData.ACCUM_ADDLIQUIDITY));
    }

    function getRefCode(address _account) public override view returns (string memory) {
        if (_account == address(this)) return _tokens[0].refCode;
        if (balanceOf(_account) != 1) return "";
        return _tokens[addressToTokenID[_account]].refCode;
    }

    function defaultRefCode() public view returns (string memory){
        return _tokens[0].refCode;//
    }

    function createTime(address _account) public override view returns (uint256){
        if (balanceOf(_account) != 1) return 0;
        return _tokens[addressToTokenID[_account]].createTime;
    }
    
    function nickName(address _account) public override view returns (string memory){
        if (balanceOf(_account) != 1) return "";
        return _tokens[addressToTokenID[_account]].nickName;
    }

    function isScoreUpdater(address _contract) public view returns (bool){
        return hasAddressSet(PIDData.VALID_SCORE_UPDATER,_contract);
    }

    function exist(address _account) public view override returns (bool){
        return balanceOf(_account) == 1;
    }

    function pidDetail(address _account) public view override returns (PIDData.PIDDetailed memory){
        PIDData.PIDDetailed memory tPd;
        if (_account == address(0) || balanceOf(_account) != 1) return tPd;
        PIDData.PIDStr storage pidStr = _tokens[addressToTokenID[_account]];
        tPd.owner = pidStr.owner;
        tPd.nickName = pidStr.nickName;
        tPd.refCode = pidStr.refCode;
        tPd.createTime = pidStr.createTime;
        tPd.latestUpdateTime = pidStr.latestUpdateTime;
        tPd.score = score(_account);
        tPd.rank = rank(_account);
        tPd.score_acum = pidStr.score_acum;

        tPd.tradeVolume = getAddUint(_account, PIDData.ACCUM_POSITIONSIZE);
        tPd.swapVolume = getAddUint(_account, PIDData.ACCUM_SWAP);
        tPd.liqVolume = getAddUint(_account, PIDData.ACCUM_ADDLIQUIDITY);

        (address[] memory _par, address[] memory _chld) = getReferralForAccount(_account);
        tPd.ref = _par[0];
        tPd.child = _chld;

        return tPd;
    }


    //=================ERC 721 override=================
    function name() public view virtual override returns (string memory) {
        return "PNK SoulBoundToken";
    }

    function symbol() public view virtual override returns (string memory) {
        return "PID";
    }

    function approve(address /*to*/, uint256 /*tokenId*/) public pure override {
        require(false, "SBT: No approve method");
    }

    function getApproved(uint256 /*tokenId*/) public pure override returns (address) {
        return address(0);
    }

    function setApprovalForAll(address /*operator*/, bool /*approved*/) public pure override {
        require(false, "SBT: no approve all");
    }

    function isApprovedForAll(address /*owner*/, address /*operator*/) public pure override returns (bool) {
        return false;
    }

    function balanceOf(address owner) public view override returns (uint256) {
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        require(
            _exists(tokenId),
            "ERC721: owner query for nonexistent token"
        );
        return address(_tokens[tokenId].owner);
    }

    function isOwnerOf(address account, uint256 id) public view returns (bool) {
        address owner = ownerOf(id);
        return owner == account;
    }

    function transferFrom(address /*from*/, address /*to*/, uint256 /*tokenId*/) public pure override {
        require(false, "SoulBoundToken: transfer is not allowed");
    }

    function safeTransferFrom( address /*from*/, address /*to*/, uint256 /*tokenId*/) public  pure override {
        require( false, "SoulBoundToken: transfer is not allowed");
    }

    function safeTransferFrom(
        address /*from*/,
        address /*to*/,
        uint256 /*tokenId*/,
        bytes memory /*_data*/
    ) public pure override {
        require( false, "SoulBoundToken: transfer is not allowed");
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        if (tokenId >= _tokens.length) return false;
        if (_tokens[tokenId].createTime < 1) return false;
        return true;
    }

    /* ============ Util Functions ============ */
    function setURI(string calldata newURI) external onlyOwner {
        _baseImgURI = newURI;
    }

    function compileAttributes(uint256 tokenId) internal view returns (string memory) {
        address _account = ownerOf(tokenId);
        INFTUtils NFTUtils = INFTUtils(nftUtils);
        return  string(
                abi.encodePacked(
                    "[",
                    NFTUtils.attributeForTypeAndValue(
                        "Name",
                        nickName(_account)
                    ),
                    NFTUtils.attributeForTypeAndValue(
                        "Rank",
                        Strings.toString(rank(_account))
                    ),
                    ",",
                    NFTUtils.attributeForTypeAndValue(
                        "ReferalCode",
                        _tokens[tokenId].refCode
                    ),
                    "]"
                )
            );
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(_exists(tokenId), "FTeamNFT: FTeamNFT does not exist");
        INFTUtils NFTUtils = INFTUtils(nftUtils);
        string memory metadata = string(
            abi.encodePacked(
                '{"name": "',
                _name,
                ' #',
                tokenId.toString(),
                '", "description": "PNK Soul Bound Token", "image": "',
                _baseImgURI,
                tokenId.toString(),
                '.jpg", "attributes":',
                compileAttributes(tokenId),
                "}"
            )
        );
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    NFTUtils.base64(bytes(metadata))
                )
            );
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool){
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId;
    }
}


