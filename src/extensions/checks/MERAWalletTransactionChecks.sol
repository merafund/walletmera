// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {BaseMERAWallet} from "../../BaseMERAWallet.sol";
import {MERAWalletTypes} from "../../types/MERAWalletTypes.sol";
import {IMERAWalletTransactionChecker} from "../../interfaces/extensions/IMERAWalletTransactionChecker.sol";

abstract contract MERAWalletTransactionChecks is BaseMERAWallet {
    error InvalidCheckerAddress();

    event TransactionCheckerUpdated(
        address indexed checker, bool beforeEnabled, bool afterEnabled, address indexed caller
    );

    mapping(address checker => bool enabled) public beforeCheckerEnabled;
    mapping(address checker => bool enabled) public afterCheckerEnabled;

    address[] internal _beforeCheckerList;
    address[] internal _afterCheckerList;

    mapping(address checker => uint256 indexPlusOne) internal _beforeCheckerIndexPlusOne;
    mapping(address checker => uint256 indexPlusOne) internal _afterCheckerIndexPlusOne;

    function setTransactionChecker(address checker, bool enableBefore, bool enableAfter) external {
        _onlyEmergency();
        require(checker != address(0), InvalidCheckerAddress());

        _setBeforeChecker(checker, enableBefore);
        _setAfterChecker(checker, enableAfter);

        emit TransactionCheckerUpdated(checker, enableBefore, enableAfter, msg.sender);
    }

    function getBeforeCheckers() external view returns (address[] memory) {
        return _beforeCheckerList;
    }

    function getAfterCheckers() external view returns (address[] memory) {
        return _afterCheckerList;
    }

    function _beforeExecute(MERAWalletTypes.Call[] memory calls, bytes32 operationId) internal virtual override {
        super._beforeExecute(calls, operationId);

        uint256 checkersLength = _beforeCheckerList.length;
        for (uint256 i = 0; i < checkersLength;) {
            IMERAWalletTransactionChecker(_beforeCheckerList[i]).checkBefore(calls, operationId);
            unchecked {
                ++i;
            }
        }
    }

    function _afterExecute(MERAWalletTypes.Call[] memory calls, bytes32 operationId) internal virtual override {
        super._afterExecute(calls, operationId);

        uint256 checkersLength = _afterCheckerList.length;
        for (uint256 i = 0; i < checkersLength;) {
            IMERAWalletTransactionChecker(_afterCheckerList[i]).checkAfter(calls, operationId);
            unchecked {
                ++i;
            }
        }
    }

    function _setBeforeChecker(address checker, bool enabled) internal {
        bool currentlyEnabled = beforeCheckerEnabled[checker];
        if (currentlyEnabled == enabled) {
            return;
        }

        beforeCheckerEnabled[checker] = enabled;
        if (enabled) {
            _addChecker(_beforeCheckerList, _beforeCheckerIndexPlusOne, checker);
        } else {
            _removeChecker(_beforeCheckerList, _beforeCheckerIndexPlusOne, checker);
        }
    }

    function _setAfterChecker(address checker, bool enabled) internal {
        bool currentlyEnabled = afterCheckerEnabled[checker];
        if (currentlyEnabled == enabled) {
            return;
        }

        afterCheckerEnabled[checker] = enabled;
        if (enabled) {
            _addChecker(_afterCheckerList, _afterCheckerIndexPlusOne, checker);
        } else {
            _removeChecker(_afterCheckerList, _afterCheckerIndexPlusOne, checker);
        }
    }

    function _addChecker(
        address[] storage checkerList,
        mapping(address checker => uint256) storage indexMap,
        address checker
    ) internal {
        checkerList.push(checker);
        indexMap[checker] = checkerList.length;
    }

    function _removeChecker(
        address[] storage checkerList,
        mapping(address checker => uint256) storage indexMap,
        address checker
    ) internal {
        uint256 indexPlusOne = indexMap[checker];
        if (indexPlusOne == 0) {
            return;
        }

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = checkerList.length - 1;
        if (index != lastIndex) {
            address lastChecker = checkerList[lastIndex];
            checkerList[index] = lastChecker;
            indexMap[lastChecker] = index + 1;
        }

        checkerList.pop();
        delete indexMap[checker];
    }
}
