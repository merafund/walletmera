// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice Uniswap V2 Router02 ABI subset used by MERA oracle slippage checker (selectors + WETH path checks).
/// @dev Matches Uniswap V2 periphery `IUniswapV2Router01` swap methods plus `SupportingFeeOnTransferTokens` from `IUniswapV2Router02`.
interface IUniswapV2Router02 {
    /// @notice Wrapped native token used by the router.
    function WETH() external pure returns (address);

    /// @notice Swaps an exact ERC20 input amount for as many output tokens as possible.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps up to a maximum ERC20 input amount for an exact output amount.
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps exact native ETH for as many output tokens as possible.
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);

    /// @notice Swaps up to a maximum ERC20 input amount for exact native ETH output.
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps an exact ERC20 input amount for as much native ETH as possible.
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps native ETH for an exact output token amount.
    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);

    /// @notice Fee-on-transfer variant of {swapExactTokensForTokens}.
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    /// @notice Fee-on-transfer variant of {swapExactETHForTokens}.
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    /// @notice Fee-on-transfer variant of {swapExactTokensForETH}.
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}
