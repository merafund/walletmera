// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @dev Minimal ERC20 for tests: mint, transfer, approve, balanceOf, allowance.
contract ERC20Mock {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        require(a >= amount, "allowance");
        allowance[from][msg.sender] = a - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function name() external pure returns (string memory) {
        return "Mock";
    }

    function symbol() external pure returns (string memory) {
        return "MCK";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}
