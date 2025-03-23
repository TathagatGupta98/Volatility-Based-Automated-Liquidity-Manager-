// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract MockPositionTracker {
    uint256 public slotCount;

    function setSlotCount(uint256 newCount) external {
        slotCount = newCount;
    }
}
