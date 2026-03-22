//SDPX-License-Identifier: MIT
pragma solidity ^0.8.30;


contract PoolInteractor {
    
    address public immutable poolInteractorAddress;

    struct SlotState {
        uint256 tokenId;
        int256 lowerTick;
        int256 upperTick;
        bool isActive;
    }

    mapping (uint256 slotIndex => SlotState) public slots;
    uint256 public slotCount;

    modifier onlyPoolInteractor() {
        if(msg.sender != poolInteractorAddress){
            revert NotPoolInteractor();
        }
        _;
    }
    // @dev define the slot state
    function setSlotState(uint256 slotIndex,uint256 _tokenId , int256 _lowerTick, int256 _upperTick, uint256 _liquidityAmount, bool _isActive) public onlyPoolInteractor {
        slots[slotIndex] = SlotState({
            tokenId: _tokenId,
            lowerTick: _lowerTick,
            upperTick: _upperTick,
            isActive: _isActive
        });
    }
    // @dev called when we make liquidity holding of a position inactive or active
    function setHasLiquidity(uint256 slotIndex, bool hasLiquidity) public onlyPoolInteractor {
        slots[slotIndex].isActive = hasLiquidity;
    }

    // @dev volatility index changes and we need to change the slot count accordingly
    function setSlotCount(uint256 newSlotCount) public onlyPoolInteractor {
        slotCount = newSlotCount;
    }

    function getSlotState(uint slotIndex) public view returns (SlotState memory) {
        return slots[slotIndex];
    }

    function hasLiquidity(uint slotIndex) public view returns (bool) {
        return slots[slotIndex].isActive;
    }

    function getTokenId(uint slotIndex) public view returns (uint256) {
        return slots[slotIndex].tokenId;
    }
}
