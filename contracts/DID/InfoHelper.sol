// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import "../core/interfaces/IVault.sol";
import "./interfaces/IPID.sol";

interface ShaHld {
    function getReferalState(address _account) external view returns (uint256, uint256[] memory, address[] memory , uint256[] memory, bool[] memory);
}

interface IDataStore{
    function getAddressSetCount(bytes32 _key) external view returns (uint256);
    function getAddressSetRoles(bytes32 _key, uint256 _start, uint256 _end) external view returns (address[] memory);
    function getAddUint(address _account, bytes32 key) external view returns (uint256);
    function getUint(bytes32 key) external view returns (uint256);
}


contract InfoHelper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant ACCUM_REBATE = keccak256("ACCUM_REBATE");
    bytes32 public constant VALID_VAULTS = keccak256("VALID_VAULTS");
    bytes32 public constant ACCUM_SWAP = keccak256("ACCUM_SWAP");
    bytes32 public constant ACCUM_ADDLIQUIDITY = keccak256("ACCUM_ADDLIQUIDITY");
    bytes32 public constant ACCUM_POSITIONSIZE = keccak256("ACCUM_POSITIONSIZE");
    bytes32 public constant ACCUM_FEE_DISCOUNTED = keccak256("ACCUM_FEE_DISCOUNTED");
    bytes32 public constant ACCUM_FEE = keccak256("ACCUM_FEE");
    bytes32 public constant FEE_REBATE_PERCENT = keccak256("FEE_REBATE_PERCENT");
    bytes32 public constant ACCUM_SCORE = keccak256("ACCUM_SCORE");
    bytes32 public constant ACCUM_FEE_REBATED = keccak256("ACCUM_FEE_REBATED");

    bytes32 public constant INTERVAL_RANK_UPDATE = keccak256("INTERVAL_RANK_UPDATE");
    bytes32 public constant INTERVAL_SCORE_UPDATE = keccak256("INTERVAL_SCORE_UPDATE");
    bytes32 public constant TIME_RANK_UPD = keccak256("TIME_RANK_UPD");
    bytes32 public constant TIME_SOCRE_DEC= keccak256("TIME_SOCRE_DEC");


    uint256 constant private PRECISION_COMPLE = 10000;
    uint256 public constant SCORE_PRECISION = 10 ** 18;

    function getInvitedUser(address _PID, address _account) public view returns (address[] memory, uint256[] memory) {
        (, address[] memory childs) = IPID(_PID).getReferralForAccount(_account);

        uint256[] memory infos = new uint256[](childs.length*3);

        for (uint256 i =0; i < childs.length; i++){
            infos[i*3] = IPID(_PID).createTime(childs[i]);
            infos[i*3 + 1] = IPID(_PID).userSizeSum(childs[i]);
            infos[i*3 + 2] = IPID(_PID).score(childs[i]);
        }
        return (childs, infos);
    }

    function getBasicInfo(address _PID, address _account) public view returns (string[] memory, address[] memory, uint256[] memory) {
        (, address[] memory childs) = IPID(_PID).getReferralForAccount(_account);

        uint256[] memory infos = new uint256[](17);
        string[] memory infosStr = new string[](2);
        // address[] memory validVaults = IDataStore(_PID).getAddressSetRoles(VALID_VAULTS, 0, IDataStore(_PID).getAddressSetCount(VALID_VAULTS));
        (infos[0], infos[1]) = IPID(_PID).accountToDisReb(_account);
        infos[2] = IPID(_PID).userSizeSum(_account);
        infos[3] = IDataStore(_PID).getAddUint(_account,  ACCUM_SWAP);
        infos[4] = IDataStore(_PID).getAddUint(_account,  ACCUM_ADDLIQUIDITY);
        infos[5] = IDataStore(_PID).getAddUint(_account,  ACCUM_POSITIONSIZE);
        infos[6] = IDataStore(_PID).getAddUint(_account,  ACCUM_FEE_DISCOUNTED);
        infos[7] = IDataStore(_PID).getAddUint(_account,  ACCUM_FEE); 
        infos[8] = IDataStore(_PID).getAddUint(_account,  ACCUM_FEE_REBATED); 
        infos[9] = IPID(_PID).score(_account);
        infos[10] = IPID(_PID).rank(_account);
        infos[11] = IPID(_PID).createTime(_account);
        infos[12] = IPID(_PID).addressToTokenID(_account);

        infos[13] = IDataStore(_PID).getUint(INTERVAL_RANK_UPDATE);
        infos[14] = IDataStore(_PID).getUint(INTERVAL_SCORE_UPDATE);

        infos[15] = IDataStore(_PID).getAddUint(_account, TIME_RANK_UPD).add(infos[13]);
        infos[15] = infos[15] > infos[13] ? infos[15] : 0; 
        infos[16] = IDataStore(_PID).getAddUint(_account, TIME_SOCRE_DEC).add(infos[14]);
        infos[16] = infos[16] > infos[14] ? infos[16] : 0; 

        infosStr[0] = IPID(_PID).nickName(_account);
        infosStr[1] = IPID(_PID).getRefCode(_account);
        return (infosStr, childs, infos);
    }



}
