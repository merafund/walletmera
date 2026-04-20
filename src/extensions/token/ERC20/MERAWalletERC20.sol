// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MERAWalletTypes} from "../../../types/MERAWalletTypes.sol";
import {BaseMERAWallet} from "../../../BaseMERAWallet.sol";

abstract contract MERAWalletERC20 is BaseMERAWallet {
    function transferERC20(address token, address to, uint256 amount, uint256 salt) external {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
        _executeSingleCall(token, 0, data, address(0), "", salt);
    }

    function transferERC20(
        address token,
        address to,
        uint256 amount,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
        bytes memory checkerMem = checkerData;
        _executeSingleCall(token, 0, data, checker, checkerMem, salt);
    }

    function approveERC20(address token, address spender, uint256 amount, uint256 salt) external {
        bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, spender, amount);
        _executeSingleCall(token, 0, data, address(0), "", salt);
    }

    function approveERC20(
        address token,
        address spender,
        uint256 amount,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external {
        bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, spender, amount);
        bytes memory checkerMem = checkerData;
        _executeSingleCall(token, 0, data, checker, checkerMem, salt);
    }

    /// @notice Proposes a single ERC-20 transfer (uses wallet timelock policy).
    function proposeTransferERC20(address token, address to, uint256 amount, uint256 salt)
        external
        returns (bytes32 operationId)
    {
        operationId = _proposeSingleERC20Call(
            token, abi.encodeWithSelector(IERC20.transfer.selector, to, amount), address(0), "", salt
        );
    }

    /// @notice Proposes a single ERC-20 approve (uses wallet timelock policy).
    function proposeApproveERC20(address token, address spender, uint256 amount, uint256 salt)
        external
        returns (bytes32 operationId)
    {
        operationId = _proposeSingleERC20Call(
            token, abi.encodeWithSelector(IERC20.approve.selector, spender, amount), address(0), "", salt
        );
    }

    function proposeTransferERC20WithChecker(
        address token,
        address to,
        uint256 amount,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external returns (bytes32 operationId) {
        bytes memory checkerMem = checkerData;
        operationId = _proposeSingleERC20Call(
            token, abi.encodeWithSelector(IERC20.transfer.selector, to, amount), checker, checkerMem, salt
        );
    }

    function proposeApproveERC20WithChecker(
        address token,
        address spender,
        uint256 amount,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external returns (bytes32 operationId) {
        bytes memory checkerMem = checkerData;
        operationId = _proposeSingleERC20Call(
            token, abi.encodeWithSelector(IERC20.approve.selector, spender, amount), checker, checkerMem, salt
        );
    }

    function _proposeSingleERC20Call(
        address token,
        bytes memory data,
        address checker,
        bytes memory checkerDataMem,
        uint256 salt
    ) internal returns (bytes32 operationId) {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] =
            MERAWalletTypes.Call({target: token, value: 0, data: data, checker: checker, checkerData: checkerDataMem});
        (operationId,,,) = _proposeTransactionFromMemory(calls, salt);
    }

    function executePendingTransferERC20(address token, address to, uint256 amount, uint256 salt) external payable {
        _executePendingSingleERC20(
            token, abi.encodeWithSelector(IERC20.transfer.selector, to, amount), address(0), "", salt
        );
    }

    function executePendingApproveERC20(address token, address spender, uint256 amount, uint256 salt) external payable {
        _executePendingSingleERC20(
            token, abi.encodeWithSelector(IERC20.approve.selector, spender, amount), address(0), "", salt
        );
    }

    function executePendingTransferERC20WithChecker(
        address token,
        address to,
        uint256 amount,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external payable {
        bytes memory checkerMem = checkerData;
        _executePendingSingleERC20(
            token, abi.encodeWithSelector(IERC20.transfer.selector, to, amount), checker, checkerMem, salt
        );
    }

    function executePendingApproveERC20WithChecker(
        address token,
        address spender,
        uint256 amount,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external payable {
        bytes memory checkerMem = checkerData;
        _executePendingSingleERC20(
            token, abi.encodeWithSelector(IERC20.approve.selector, spender, amount), checker, checkerMem, salt
        );
    }

    function _executePendingSingleERC20(
        address token,
        bytes memory data,
        address checker,
        bytes memory checkerDataMem,
        uint256 salt
    ) internal {
        MERAWalletTypes.Call[] memory calls = new MERAWalletTypes.Call[](1);
        calls[0] =
            MERAWalletTypes.Call({target: token, value: 0, data: data, checker: checker, checkerData: checkerDataMem});
        address[] memory empty = new address[](0);
        _executePendingFromMemory(calls, salt, empty);
    }
}
