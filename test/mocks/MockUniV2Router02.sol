// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {ERC20Mock} from "./ERC20Mock.sol";

/// @dev Minimal Uniswap V2 Router02-style swap for slippage checker tests.
contract MockUniV2Router02 {
    address public immutable wethAddr;
    /// @dev If true, output is 985/10000 of input (1.5% worse than 1:1 oracle). If false, 995/10000 (0.5% worse).
    bool public badRate;

    constructor(address weth_) {
        wethAddr = weth_;
    }

    function setBadRate(bool v) external {
        badRate = v;
    }

    function WETH() external view returns (address) {
        return wethAddr;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "expired");
        ERC20Mock token0 = ERC20Mock(path[0]);
        ERC20Mock tokenL = ERC20Mock(path[path.length - 1]);
        require(token0.transferFrom(msg.sender, address(this), amountIn), "tf");
        uint256 bps = badRate ? 9850 : 9950;
        uint256 out = (amountIn * bps) / 10_000;
        require(out >= amountOutMin, "min");
        require(tokenL.transfer(to, out), "tr");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = out;
    }
}
