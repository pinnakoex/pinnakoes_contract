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

contract PIDLogic is IPIDLogic, Ownable{
    using SafeMath for uint256;
    using Strings for uint256;
    using Address for address;
    uint256[] public scoreToRank;
    uint256[] public rankToReb;
    uint256[] public rankToDis;
    
    function setScoreToRank(uint256[] memory _minValue) external onlyOwner{
        require(_minValue.length > 3 && _minValue[0] == 0, "invalid score-rank setting");
        scoreToRank = _minValue;
    }

    function setDisReb(uint256[] memory _dis, uint256[] memory _reb) external onlyOwner{
        require(scoreToRank.length +1 == _dis.length && _dis.length == _reb.length, "invalid dis-reb setting");
        rankToReb = _reb;
        rankToDis = _dis;
    }

    function toRank(address _account, uint256 _score) external view returns (uint256){
        uint256 reqScore = _score.div(PIDData.SCORE_PRECISION);
        uint256 _rankRes = scoreToRank.length;
        for(uint i = 1; i < scoreToRank.length; i++){
            if (reqScore >= scoreToRank[i-1] && reqScore < scoreToRank[i]){
                _rankRes = i;
                break;
            }
        }

        return _rankRes;  
    }

}


