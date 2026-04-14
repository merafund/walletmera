// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @dev Payable helper for tests: stores a uint256 set via setValue.
contract ReceiverMock {
    uint256 public value;

    receive() external payable {}

    function setValue(uint256 newValue) external {
        value = newValue;
    }
}
