// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletUniswapV2OracleSlippageChecker} from "../src/checkers/MERAWalletUniswapV2OracleSlippageChecker.sol";
import {MERAWalletAssetWhiteList} from "../src/checkers/whitelists/MERAWalletAssetWhiteList.sol";
import {IMERAWalletUniswapV2SlippageErrors} from "../src/checkers/errors/IMERAWalletUniswapV2SlippageErrors.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {MockUniV2Router02} from "./mocks/MockUniV2Router02.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";
import {MERAWalletTestBase} from "./helpers/MERAWalletTestBase.sol";

contract IsolatedSlippageWallet {
    function approveToken(ERC20Mock token, address spender) external {
        token.approve(spender, type(uint256).max);
    }

    function executeSwapWithHooks(
        MERAWalletUniswapV2OracleSlippageChecker checker,
        MockUniV2Router02 router,
        MERAWalletTypes.Call calldata swapCall,
        bytes32 operationId,
        uint256 callId,
        uint256 amountIn,
        address[] calldata path,
        uint256 deadline
    ) external {
        checker.checkBefore(swapCall, operationId, callId);
        router.swapExactTokensForTokens(amountIn, 0, path, address(this), deadline);
        checker.checkAfter(swapCall, operationId, callId);
    }
}

contract MERAWalletUniswapV2OracleSlippageCheckerIsolatedGasTest is MERAWalletTestBase {
    address private constant OWNER = address(uint160(PRIMARY_PK));
    bytes32 private constant OPERATION_ID = keccak256("isolated-swap");
    uint256 private constant CALL_ID = 7;
    uint256 private constant AMOUNT_IN = 1 ether;

    IsolatedSlippageWallet private wallet;
    MERAWalletUniswapV2OracleSlippageChecker private checker;
    ERC20Mock private tokenA;
    ERC20Mock private tokenB;
    ERC20Mock private weth;
    MockUniV2Router02 private router;

    MERAWalletTypes.Call private swapCall;

    function setUp() public {
        vm.warp(DEFAULT_TEST_TIMESTAMP);

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        weth = new ERC20Mock();
        router = new MockUniV2Router02(address(weth));
        wallet = new IsolatedSlippageWallet();
        checker = new MERAWalletUniswapV2OracleSlippageChecker(
            OWNER,
            DEFAULT_MAX_ORACLE_NEGATIVE_DEVIATION_BPS,
            DEFAULT_MAX_ORACLE_STALE_SECONDS,
            DEFAULT_REQUIRE_ROUTER_ALLOWLIST
        );

        MockAggregatorV3 feedA = new MockAggregatorV3(1e8, 8);
        MockAggregatorV3 feedB = new MockAggregatorV3(1e8, 8);
        MERAWalletAssetWhiteList assetWhitelist = new MERAWalletAssetWhiteList(OWNER);

        vm.startPrank(OWNER);
        checker.setAllowedRouters(_oneAddress(address(router)), _oneBool(true));
        assetWhitelist.setAllowedAssets(_twoAddresses(address(tokenA), address(tokenB)), _twoBools(true, true));
        assetWhitelist.setAssetSources(
            _twoAddresses(address(tokenA), address(tokenB)), _twoAddresses(address(feedA), address(feedB))
        );
        checker.setDefaultAssetWhitelist(address(assetWhitelist));
        vm.stopPrank();

        tokenA.mint(address(wallet), 10 ether);
        tokenB.mint(address(router), 1000 ether);

        wallet.approveToken(tokenA, address(router));

        swapCall = MERAWalletTypes.Call({
            target: address(router),
            value: 0,
            data: _swapCallData(AMOUNT_IN, 0),
            checker: address(checker),
            checkerData: ""
        });
    }

    function test_IsolatedSwapWithinOracleTolerance_CheckerHooksGas() public {
        router.setBadRate(false);

        wallet.executeSwapWithHooks(
            checker, router, swapCall, OPERATION_ID, CALL_ID, AMOUNT_IN, _path(), block.timestamp + 1
        );
    }

    function test_IsolatedSwapWorseThanOracle_Reverts() public {
        router.setBadRate(true);

        vm.expectRevert(IMERAWalletUniswapV2SlippageErrors.SwapWorseThanOracle.selector);
        wallet.executeSwapWithHooks(
            checker, router, swapCall, OPERATION_ID, CALL_ID, AMOUNT_IN, _path(), block.timestamp + 1
        );
    }

    function _swapCallData(uint256 amountIn, uint256 amountOutMin) private view returns (bytes memory) {
        return abi.encodeWithSelector(
            MockUniV2Router02.swapExactTokensForTokens.selector,
            amountIn,
            amountOutMin,
            _path(),
            address(wallet),
            block.timestamp + 1
        );
    }

    function _path() private view returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
    }
}
