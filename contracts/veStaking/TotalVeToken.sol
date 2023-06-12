// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


import "./interfaces/IgToken.sol";

contract TotalVeToken is Ownable, IgToken {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet internal gTokenStakeSet;

    constructor (address[] memory _gTokenStakeSet) {
        for (uint i = 0; i < _gTokenStakeSet.length; i++) {
            gTokenStakeSet.add(_gTokenStakeSet[i]);
        }
    }

    function resetAllgTokenStakeSet(address[] memory _gTokenStakeSet) public onlyOwner {
        //remove all gTokenStakeSet
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            gTokenStakeSet.remove(gTokenStakeSet.at(i));
        }
        //add new gTokenStakeSet
        for (uint i = 0; i < _gTokenStakeSet.length; i++) {
            gTokenStakeSet.add(_gTokenStakeSet[i]);
        }
    }

    function getAllgTokenStakeSet() public view returns (address[] memory) {
        address[] memory gTokenStakeSetTemp = new address[](gTokenStakeSet.length());
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            gTokenStakeSetTemp[i] = gTokenStakeSet.at(i);
        }
        return gTokenStakeSetTemp;
    }

    function version() public view virtual override returns (string memory) {
        return IgToken(gTokenStakeSet.at(0)).version();
    }

    function decimals() public view virtual override returns (uint256) {
        return IgToken(gTokenStakeSet.at(0)).decimals();
    }

    function admin() public view virtual override returns (address) {
        return IgToken(gTokenStakeSet.at(0)).admin();
    }

    function symbol() public view virtual override returns (string memory) {
        return IgToken(gTokenStakeSet.at(0)).symbol();
    }

    function name() public view virtual override returns (string memory) {
        return IgToken(gTokenStakeSet.at(0)).name();
    }

    function locked(address addr) public view virtual override returns (LockedBalance memory) {
        //acc all gTokenStakeSet
        LockedBalance memory lockedBalance;
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            LockedBalance memory lockedBalanceTemp = IgToken(gTokenStakeSet.at(i)).locked(addr);
            lockedBalance.amount = lockedBalance.amount + lockedBalanceTemp.amount;
            if (lockedBalanceTemp.end > lockedBalance.end) {
                lockedBalance.end = lockedBalanceTemp.end;
            }
        }
        return lockedBalance;
    }

    function supply() public view virtual override returns (uint256) {
        uint256 supplyTemp = 0;
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            supplyTemp = supplyTemp + IgToken(gTokenStakeSet.at(i)).supply();
        }
        return supplyTemp;
    }

    function token() public view virtual override returns (address) {
        return gTokenStakeSet.at(0);
    }
    

    function totalTokenSupply() public view virtual override returns (uint256) {
        uint256 supplyTemp = 0;
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            supplyTemp = supplyTemp + IgToken(gTokenStakeSet.at(i)).totalTokenSupply();
        }
        return supplyTemp;
    }

    function totalSupplyAtNow() public view virtual override returns (uint256) {
        uint256 supplyTemp = 0;
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            supplyTemp = supplyTemp + IgToken(gTokenStakeSet.at(i)).totalSupplyAtNow();
        }
        return supplyTemp;
    }

    function totalSupplyAt(uint256 _block) public view virtual override returns (uint256) {
        uint256 supplyTemp = 0;
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            supplyTemp = supplyTemp + IgToken(gTokenStakeSet.at(i)).totalSupplyAt(_block);
        }
        return supplyTemp;
    }

    function totalSupply(uint256 t) public view virtual override returns (uint256) {
        uint256 supplyTemp = 0;
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            supplyTemp = supplyTemp + IgToken(gTokenStakeSet.at(i)).totalSupply(t);
        }
        return supplyTemp;
    }

    function totalSupply() public view virtual override returns (uint256) {
        uint256 supplyTemp = 0;
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            supplyTemp = supplyTemp + IgToken(gTokenStakeSet.at(i)).totalSupply();
        }
        return supplyTemp;
    }

    function balanceOfAt(address addr, uint256 _block) public view virtual override returns (uint256) {
        uint256 balanceTemp = 0;
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            balanceTemp = balanceTemp + IgToken(gTokenStakeSet.at(i)).balanceOfAt(addr, _block);
        }
        return balanceTemp;
    }

    function balanceOf(address addr, uint256 _t) public view virtual override returns (uint256) {
        uint256 balanceTemp = 0;
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            balanceTemp = balanceTemp + IgToken(gTokenStakeSet.at(i)).balanceOf(addr, _t);
        }
        return balanceTemp;
    }

    function balanceOf(address addr) public view virtual override returns (uint256) {
        uint256 balanceTemp = 0;
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            balanceTemp = balanceTemp + IgToken(gTokenStakeSet.at(i)).balanceOf(addr);
        }
        return balanceTemp;
    }

    function checkpoint() public virtual override {
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            IgToken(gTokenStakeSet.at(i)).checkpoint();
        }
    }

    function locked__end(address _addr) public view virtual override returns (uint256) {
        uint256 locked__endTemp = 0;
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            uint256 locked__endTempTemp = IgToken(gTokenStakeSet.at(i)).locked__end(_addr);
            if (locked__endTempTemp > locked__endTemp) {
                locked__endTemp = locked__endTempTemp;
            }
        }
        return locked__endTemp;
    }

    function user_point_history__ts(address _addr, uint256 _idx) public view virtual override returns (uint256) {
        uint256 user_point_history__tsTemp = 0;
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            user_point_history__tsTemp = user_point_history__tsTemp + IgToken(gTokenStakeSet.at(i)).user_point_history__ts(_addr, _idx);
        }
        return user_point_history__tsTemp;
    }

    function get_last_user_slope(address addr) public view virtual override returns (int128) {
        int128 get_last_user_slopeTemp = 0;
        for (uint i = 0; i < gTokenStakeSet.length(); i++) {
            get_last_user_slopeTemp = get_last_user_slopeTemp + IgToken(gTokenStakeSet.at(i)).get_last_user_slope(addr);
        }
        return get_last_user_slopeTemp;
    }

}