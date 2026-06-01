// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";
import {IUniswapV2Router02} from "../interfaces/uniswap/IUniswapV2Router02.sol";
import {MERAWalletOracleSlippageCheckerBase} from "./MERAWalletOracleSlippageCheckerBase.sol";
import {MERAWalletUniswapV2SlippageTypes} from "./types/MERAWalletUniswapV2SlippageTypes.sol";

/// @notice Validates Uniswap V2 Router02 swap calls against Chainlink spot prices using wallet balance deltas.
/// @dev Swap endpoints are decoded from `call.data`; oracle stale/date checks are enforced.
contract MERAWalletUniswapV2OracleSlippageChecker is MERAWalletOracleSlippageCheckerBase {
    /// @notice Creates a Uniswap V2 oracle slippage checker.
    /// @param initialOwner Admin for router allowlist when `requireRouterAllowlist` is true (see {Ownable}).
    /// @param maxOracleNegativeDeviationBps Max allowed oracle shortfall in BPS; must be `< BPS`.
    /// @param maxOracleStaleSeconds Max age of Chainlink `updatedAt`; must be `> 0`.
    /// @param sequencerUptimeFeed Chainlink L2 sequencer uptime feed, or `address(0)` on L1/no-op deployments.
    /// @param sequencerGracePeriodSeconds Delay after sequencer recovery before oracle reads are accepted.
    /// @param requireRouterAllowlist Enforce {MERAWalletOracleSlippageCheckerBase-allowedRouter} when true.
    constructor(
        address initialOwner,
        uint256 maxOracleNegativeDeviationBps,
        uint256 maxOracleStaleSeconds,
        address sequencerUptimeFeed,
        uint256 sequencerGracePeriodSeconds,
        bool requireRouterAllowlist
    )
        MERAWalletOracleSlippageCheckerBase(
            initialOwner,
            maxOracleNegativeDeviationBps,
            maxOracleStaleSeconds,
            sequencerUptimeFeed,
            sequencerGracePeriodSeconds,
            requireRouterAllowlist
        )
    {}

    /// @inheritdoc MERAWalletOracleSlippageCheckerBase
    function _decodeSwapCheckData(MERAWalletTypes.Call calldata call)
        internal
        pure
        override
        returns (MERAWalletUniswapV2SlippageTypes.CheckerDataSlippageCheckData memory decoded)
    {
        (address[] memory path, bool ethIn, bool ethOut) = _decodeUniswapV2Swap(call.data);
        require(path.length >= 2, PathTooShort());

        if (ethIn || ethOut) {
            address weth = IUniswapV2Router02(call.target).WETH();
            require(!ethIn || path[0] == weth, UnsupportedRouterCall(bytes4(call.data[0:4])));
            require(!ethOut || path[path.length - 1] == weth, UnsupportedRouterCall(bytes4(call.data[0:4])));
        }

        decoded = MERAWalletUniswapV2SlippageTypes.CheckerDataSlippageCheckData({
            tokenIn: path[0], tokenOut: path[path.length - 1], ethIn: ethIn, ethOut: ethOut
        });
    }

    /// @notice Decodes supported Uniswap V2 Router02 swap calldata.
    /// @param data Router calldata.
    /// @return path Swap path.
    /// @return ethIn Whether the input side is native ETH.
    /// @return ethOut Whether the output side is native ETH.
    function _decodeUniswapV2Swap(bytes calldata data)
        private
        pure
        returns (address[] memory path, bool ethIn, bool ethOut)
    {
        require(data.length >= 4, UnsupportedRouterCall(bytes4(0)));
        bytes4 functionSelector = bytes4(data[0:4]);
        bytes calldata body = data[4:];

        if (
            functionSelector == IUniswapV2Router02.swapExactTokensForTokens.selector
                || functionSelector == IUniswapV2Router02.swapTokensForExactTokens.selector
                || functionSelector == IUniswapV2Router02.swapExactTokensForETH.selector
                || functionSelector == IUniswapV2Router02.swapTokensForExactETH.selector
                || functionSelector == IUniswapV2Router02.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector
                || functionSelector == IUniswapV2Router02.swapExactTokensForETHSupportingFeeOnTransferTokens.selector
        ) {
            (,, path,,) = abi.decode(body, (uint256, uint256, address[], address, uint256));
            ethIn = false;
            ethOut =
                (functionSelector == IUniswapV2Router02.swapExactTokensForETH.selector
                        || functionSelector == IUniswapV2Router02.swapTokensForExactETH.selector)
                    || (functionSelector
                            == IUniswapV2Router02.swapExactTokensForETHSupportingFeeOnTransferTokens.selector);
        } else if (
            functionSelector == IUniswapV2Router02.swapExactETHForTokens.selector
                || functionSelector == IUniswapV2Router02.swapETHForExactTokens.selector
                || functionSelector == IUniswapV2Router02.swapExactETHForTokensSupportingFeeOnTransferTokens.selector
        ) {
            (, path,,) = abi.decode(body, (uint256, address[], address, uint256));
            ethIn = true;
            ethOut = false;
        } else {
            revert UnsupportedRouterCall(functionSelector);
        }
    }
}
