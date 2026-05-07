// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";
import {IMERAWalletTransactionChecker} from "../interfaces/checkers/IMERAWalletTransactionChecker.sol";
import {IMERAWalletAssetWhiteList} from "../interfaces/checkers/IMERAWalletAssetWhiteList.sol";
import {IAggregatorV3} from "../interfaces/oracles/IAggregatorV3.sol";
import {IUniswapV2Router02} from "../interfaces/uniswap/IUniswapV2Router02.sol";
import {IMERAWalletUniswapV2SlippageErrors} from "./errors/IMERAWalletUniswapV2SlippageErrors.sol";
import {MERAWalletUniswapV2SlippageTypes} from "./types/MERAWalletUniswapV2SlippageTypes.sol";

/// @notice Validates Uniswap V2 Router02 swap calls against Chainlink spot prices using wallet balance deltas.
contract MERAWalletUniswapV2OracleSlippageChecker is
    Ownable,
    Pausable,
    IMERAWalletTransactionChecker,
    IMERAWalletUniswapV2SlippageErrors
{
    /// @dev Max allowed shortfall vs oracle-implied output (basis points). E.g. 100 = 1% worse than oracle is allowed.
    uint256 public immutable MAX_ORACLE_NEGATIVE_DEVIATION_BPS;

    uint256 public constant BPS = 10_000;

    /// @dev Reject Chainlink answers older than this many seconds.
    uint256 public immutable MAX_ORACLE_STALE_SECONDS;

    event AllowedRouterUpdated(address indexed router, bool allowed, address indexed caller);
    event TokenPriceFeedUpdated(address indexed token, address indexed feed, address indexed caller);
    event PauseAgentUpdated(address indexed agent, bool allowed, address indexed caller);
    /// @dev Emits `assetWhitelist` from stored config; additional struct fields may be reflected here later.
    event WalletSlippageCheckerConfigUpdated(
        address indexed wallet, address indexed assetWhitelist, address indexed caller
    );
    event DefaultAssetWhitelistUpdated(
        address indexed previous, address indexed assetWhitelist, address indexed caller
    );

    mapping(address agent => bool allowed) public isPauseAgent;

    mapping(address router => bool allowed) public allowedRouter;
    mapping(address token => address feed) public tokenPriceFeed;

    /// @dev Full per-wallet config from {applyConfig} (extensible struct); `assetWhitelist` may be zero to fall back to {defaultAssetWhitelist}.
    mapping(address wallet => MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig) public
        walletSlippageCheckerConfig;
    /// @dev Used when `walletSlippageCheckerConfig[wallet].assetWhitelist` is zero.
    address public defaultAssetWhitelist;

    // to do use tload tstore
    mapping(bytes32 key => MERAWalletUniswapV2SlippageTypes.Snapshot) private _snapshots;

    /// @param initialOwner Admin for router allowlist and token price feeds (see {Ownable}).
    /// @param maxOracleNegativeDeviationBps Max allowed oracle shortfall in BPS; must be `< BPS` so `BPS - value` does not underflow.
    /// @param maxOracleStaleSeconds Max age of Chainlink `updatedAt`; must be `> 0`.
    constructor(address initialOwner, uint256 maxOracleNegativeDeviationBps, uint256 maxOracleStaleSeconds)
        Ownable(initialOwner)
    {
        require(maxOracleNegativeDeviationBps < BPS, SlippageInvalidDeviationBps());
        require(maxOracleStaleSeconds != 0, SlippageInvalidStaleSeconds());
        MAX_ORACLE_NEGATIVE_DEVIATION_BPS = maxOracleNegativeDeviationBps;
        MAX_ORACLE_STALE_SECONDS = maxOracleStaleSeconds;
    }

    function hookModes() external pure override returns (bool enableBefore, bool enableAfter) {
        return (true, true);
    }

    /// @notice Batch-update router allowlist; `routers[i]` paired with `allowed[i]`.
    function setAllowedRouters(address[] calldata routers, bool[] calldata allowed) external onlyOwner {
        uint256 n = routers.length;
        require(n == allowed.length, SlippageArrayLengthMismatch());
        for (uint256 i = 0; i < n;) {
            allowedRouter[routers[i]] = allowed[i];
            emit AllowedRouterUpdated(routers[i], allowed[i], msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Batch-set Chainlink feeds; `tokens[i]` paired with `feeds[i]`.
    function setTokenPriceFeeds(address[] calldata tokens, address[] calldata feeds) external onlyOwner {
        uint256 n = tokens.length;
        require(n == feeds.length, SlippageArrayLengthMismatch());
        for (uint256 i = 0; i < n;) {
            address token = tokens[i];
            address feed = feeds[i];
            require(token != address(0) && feed != address(0), SlippageInvalidAddress());
            tokenPriceFeed[token] = feed;
            emit TokenPriceFeedUpdated(token, feed, msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Batch grant or revoke the right to call {pause}. Only the owner may configure agents.
    function setPauseAgents(address[] calldata agents, bool[] calldata allowed) external onlyOwner {
        uint256 n = agents.length;
        require(n == allowed.length, SlippageArrayLengthMismatch());
        for (uint256 i = 0; i < n;) {
            address agent = agents[i];
            require(agent != address(0), SlippageInvalidAddress());
            isPauseAgent[agent] = allowed[i];
            emit PauseAgentUpdated(agent, allowed[i], msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IMERAWalletTransactionChecker
    function applyConfig(bytes calldata config) external override {
        if (config.length == 0) {
            return;
        }
        MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig memory decoded =
            abi.decode(config, (MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig));
        walletSlippageCheckerConfig[msg.sender] = decoded;
        emit WalletSlippageCheckerConfigUpdated(msg.sender, decoded.assetWhitelist, msg.sender);
    }

    /// @notice Global fallback asset list when a wallet has not set its own via {applyConfig}.
    function setDefaultAssetWhitelist(address newWhitelist) external onlyOwner {
        address previous = defaultAssetWhitelist;
        defaultAssetWhitelist = newWhitelist;
        emit DefaultAssetWhitelistUpdated(previous, newWhitelist, msg.sender);
    }

    /// @dev Callable by the owner or any address marked as a pause agent via {setPauseAgents}. Uses {Pausable-_pause}.
    function pause() external {
        require(msg.sender == owner() || isPauseAgent[msg.sender], SlippageNotPauseAuthorized());
        _pause();
    }

    /// @dev Only the owner may resume checks after {pause}. Uses {Pausable-_unpause}.
    function unpause() external onlyOwner {
        _unpause();
    }

    function checkBefore(MERAWalletTypes.Call calldata call, bytes32 operationId, uint256 callId)
        external
        override
        whenNotPaused
    {
        address router = call.target;
        require(allowedRouter[router], RouterNotAllowed(router, callId));

        (address[] memory path, bool ethIn, bool ethOut) = _decodeSwap(call.data);
        require(path.length >= 2, PathTooShort());

        address weth = IUniswapV2Router02(router).WETH();
        require(!ethIn || path[0] == weth, UnsupportedRouterCall(bytes4(call.data[0:4])));
        require(!ethOut || path[path.length - 1] == weth, UnsupportedRouterCall(bytes4(call.data[0:4])));

        address wallet = msg.sender;
        address assetWhitelist = _effectiveAssetWhitelist(wallet);
        _requirePathAssetsAllowed(assetWhitelist, path, callId);

        _storeSwapSnapshot(wallet, operationId, callId, path, ethIn, ethOut, assetWhitelist);
    }

    /// @dev Split out to avoid stack-too-deep when compiling without IR (e.g. forge coverage).
    function _storeSwapSnapshot(
        address wallet,
        bytes32 operationId,
        uint256 callId,
        address[] memory path,
        bool ethIn,
        bool ethOut,
        address assetWhitelist
    ) private {
        address t0 = path[0];
        address t1 = path[path.length - 1];
        address feed0 = _effectivePriceFeed(assetWhitelist, t0);
        address feed1 = _effectivePriceFeed(assetWhitelist, t1);
        uint256 b0 = IERC20(t0).balanceOf(wallet);
        uint256 b1 = IERC20(t1).balanceOf(wallet);
        uint256 ethB = wallet.balance;

        bytes32 key = _snapshotKey(wallet, operationId, callId);
        _snapshots[key] = MERAWalletUniswapV2SlippageTypes.Snapshot({
            token0Path: t0,
            token1Path: t1,
            priceFeed0: feed0,
            priceFeed1: feed1,
            erc20Bal0: b0,
            erc20Bal1: b1,
            ethBal: ethB,
            ethIn: ethIn,
            ethOut: ethOut,
            active: true
        });
    }

    function checkAfter(MERAWalletTypes.Call calldata call, bytes32 operationId, uint256 callId)
        external
        override
        whenNotPaused
    {
        address wallet = msg.sender;
        bytes32 key = _snapshotKey(wallet, operationId, callId);
        MERAWalletUniswapV2SlippageTypes.Snapshot memory snap = _snapshots[key];
        if (!snap.active) {
            return;
        }

        delete _snapshots[key];

        require(allowedRouter[call.target], RouterNotAllowed(call.target, callId));

        uint256 amountIn;
        uint256 amountOut;

        if (snap.ethIn) {
            amountIn = snap.ethBal - wallet.balance;
        } else {
            uint256 b0After = IERC20(snap.token0Path).balanceOf(wallet);
            amountIn = snap.erc20Bal0 - b0After;
        }

        if (snap.ethOut) {
            amountOut = wallet.balance - snap.ethBal;
        } else {
            uint256 b1After = IERC20(snap.token1Path).balanceOf(wallet);
            amountOut = b1After - snap.erc20Bal1;
        }

        require(amountIn != 0 && amountOut != 0, InvalidMeasuredAmounts());

        (uint256 answerIn, uint8 fdIn) = _readFeed(snap.token0Path, snap.priceFeed0);
        (uint256 answerOut, uint8 fdOut) = _readFeed(snap.token1Path, snap.priceFeed1);

        uint8 tdIn = IERC20Metadata(snap.token0Path).decimals();
        uint8 tdOut = IERC20Metadata(snap.token1Path).decimals();

        uint256 denomIn = 10 ** (uint256(tdIn) + uint256(fdIn));
        uint256 denomOut = 10 ** (uint256(tdOut) + uint256(fdOut));
        uint256 minBps = BPS - MAX_ORACLE_NEGATIVE_DEVIATION_BPS;

        // Compare implied USD notionals without shrinking `amountOut * price` first (avoids floor-to-zero on uint256 paths).
        uint256 lhs = Math.mulDiv(amountOut, answerOut * BPS, denomOut);
        uint256 rhs = Math.mulDiv(amountIn, answerIn * minBps, denomIn);
        require(lhs >= rhs, SwapWorseThanOracle());
    }

    function _effectiveAssetWhitelist(address wallet) internal view returns (address) {
        address w = walletSlippageCheckerConfig[wallet].assetWhitelist;
        if (w != address(0)) {
            return w;
        }
        return defaultAssetWhitelist;
    }

    /// @dev No-op when no asset list is configured for `wallet`.
    function _requirePathAssetsAllowed(address assetWhitelist, address[] memory path, uint256 callId) internal view {
        if (assetWhitelist == address(0)) {
            return;
        }
        uint256 len = path.length;
        for (uint256 i = 0; i < len;) {
            require(
                IMERAWalletAssetWhiteList(assetWhitelist).isAssetAllowed(path[i]), AssetNotWhitelisted(path[i], callId)
            );
            unchecked {
                ++i;
            }
        }
    }

    function _decodeSwap(bytes calldata data) internal pure returns (address[] memory path, bool ethIn, bool ethOut) {
        require(data.length >= 4, UnsupportedRouterCall(bytes4(0)));
        bytes4 sel = bytes4(data[0:4]);
        bytes calldata body = data[4:];

        if (
            sel == IUniswapV2Router02.swapExactTokensForTokens.selector
                || sel == IUniswapV2Router02.swapTokensForExactTokens.selector
                || sel == IUniswapV2Router02.swapExactTokensForETH.selector
                || sel == IUniswapV2Router02.swapTokensForExactETH.selector
                || sel == IUniswapV2Router02.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector
                || sel == IUniswapV2Router02.swapExactTokensForETHSupportingFeeOnTransferTokens.selector
        ) {
            (,, path,,) = abi.decode(body, (uint256, uint256, address[], address, uint256));
            ethIn = false;
            ethOut =
                (sel == IUniswapV2Router02.swapExactTokensForETH.selector
                        || sel == IUniswapV2Router02.swapTokensForExactETH.selector)
                    || (sel == IUniswapV2Router02.swapExactTokensForETHSupportingFeeOnTransferTokens.selector);
        } else if (
            sel == IUniswapV2Router02.swapExactETHForTokens.selector
                || sel == IUniswapV2Router02.swapETHForExactTokens.selector
                || sel == IUniswapV2Router02.swapExactETHForTokensSupportingFeeOnTransferTokens.selector
        ) {
            (, path,,) = abi.decode(body, (uint256, address[], address, uint256));
            ethIn = true;
            ethOut = false;
        } else {
            revert UnsupportedRouterCall(sel);
        }
    }

    function _effectivePriceFeed(address assetWhitelist, address token) internal view returns (address) {
        if (assetWhitelist != address(0)) {
            address source = IMERAWalletAssetWhiteList(assetWhitelist).assetSource(token);
            if (source != address(0)) {
                return source;
            }
        }
        address feedAddr = tokenPriceFeed[token];
        require(feedAddr != address(0), PriceFeedNotSet(token));
        return feedAddr;
    }

    /// @dev Matches `keccak256(abi.encode(wallet, operationId, callId))` without `abi.encode` allocation.
    function _snapshotKey(address wallet, bytes32 operationId, uint256 callId) private pure returns (bytes32 key) {
        assembly ("memory-safe") {
            let p := mload(0x40)
            mstore(p, wallet)
            mstore(add(p, 0x20), operationId)
            mstore(add(p, 0x40), callId)
            key := keccak256(p, 0x60)
            mstore(0x40, add(p, 0x60))
        }
    }

    function _readFeed(address token, address feedAddr) internal view returns (uint256 answer, uint8 feedDecimals) {
        require(feedAddr != address(0), PriceFeedNotSet(token));
        IAggregatorV3 feed = IAggregatorV3(feedAddr);
        feedDecimals = feed.decimals();
        (, int256 ans,, uint256 updatedAt,) = feed.latestRoundData();
        require(ans > 0, OracleAnswerInvalid(token));
        require(block.timestamp - updatedAt <= MAX_ORACLE_STALE_SECONDS, StaleOraclePrice(token, updatedAt));
        answer = uint256(ans);
    }
}
