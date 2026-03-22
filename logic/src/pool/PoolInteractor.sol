//SDPX-License-Identifier: MIT
pragma solidity ^0.8.30;


contract PoolInteractor {
    
    address public immutable poolInteractorAddress;

    struct SlotState {
        uint256 tokenId;
        int256 lowerTick;
        int256 upperTick;
        uint256 liquidityAmount;
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

    function setSlotState(uint slotIndex, SlotState memory state) public onlyPoolInteractor {
    }

    function setHasLiquidity(uint slotIndex, bool hasLiquidity) public onlyPoolInteractor {
    }

    function setSlotCount(uint256 newSlotCount) public onlyPoolInteractor {
    }

    function getSlotState(uint slotIndex) public view returns (SlotState memory) {
    }

    function hasLiquidity(uint slotIndex) public view returns (bool) {
    }

    function getTokenId(uint slotIndex) public view returns (uint256) {
    }
}
