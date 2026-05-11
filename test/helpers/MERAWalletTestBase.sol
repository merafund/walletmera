// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

import {BaseMERAWallet} from "../../src/BaseMERAWallet.sol";
import {MERAWalletTypes} from "../../src/types/MERAWalletTypes.sol";

abstract contract MERAWalletTestBase is Test {
    uint256 internal constant PRIMARY_PK = 0xA11CE;
    uint256 internal constant BACKUP_PK = 0xB0B;
    uint256 internal constant EMERGENCY_PK = 0xE911;

    address internal constant OUTSIDER_ADDRESS = address(0xCAFE);
    address internal constant PAUSE_AGENT = address(0xBEEF);

    uint256 internal constant DEFAULT_TEST_TIMESTAMP = 1_000_000;
    uint256 internal constant DEFAULT_MAX_ORACLE_NEGATIVE_DEVIATION_BPS = 100;
    uint256 internal constant DEFAULT_MAX_ORACLE_STALE_SECONDS = 3600;
    bool internal constant DEFAULT_REQUIRE_ROUTER_ALLOWLIST = true;

    bytes4 internal constant UNSUPPORTED_SELECTOR = 0xdeadbeef;

    uint256 internal constant ROLE_TIMELOCK_PRIMARY_SALT = 7101;
    uint256 internal constant ROLE_TIMELOCK_BACKUP_SALT = 7102;
    uint256 internal constant ROLE_TIMELOCK_EMERGENCY_SALT = 7103;

    function _oneAddress(address value) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value;
    }

    function _twoAddresses(address first, address second) internal pure returns (address[] memory values) {
        values = new address[](2);
        values[0] = first;
        values[1] = second;
    }

    function _oneBool(bool value) internal pure returns (bool[] memory values) {
        values = new bool[](1);
        values[0] = value;
    }

    function _twoBools(bool first, bool second) internal pure returns (bool[] memory values) {
        values = new bool[](2);
        values[0] = first;
        values[1] = second;
    }

    function _mkOptionalCheckerUpdate(address checker, bool allowed, bytes memory config)
        internal
        pure
        returns (MERAWalletTypes.OptionalCheckerUpdate[] memory updates)
    {
        updates = new MERAWalletTypes.OptionalCheckerUpdate[](1);
        updates[0] = MERAWalletTypes.OptionalCheckerUpdate({checker: checker, allowed: allowed, config: config});
    }

    function _singleCall(address target, uint256 value, bytes memory data)
        internal
        pure
        virtual
        returns (MERAWalletTypes.Call[] memory calls)
    {
        calls = new MERAWalletTypes.Call[](1);
        calls[0] =
            MERAWalletTypes.Call({target: target, value: value, data: data, checker: address(0), checkerData: ""});
    }

    function _singleCallWithChecker(
        address target,
        uint256 value,
        bytes memory data,
        address checker,
        bytes memory checkerData
    ) internal pure virtual returns (MERAWalletTypes.Call[] memory calls) {
        calls = new MERAWalletTypes.Call[](1);
        calls[0] = MERAWalletTypes.Call({
            target: target, value: value, data: data, checker: checker, checkerData: checkerData
        });
    }

    function _executeWalletSelfCall(BaseMERAWallet wallet, bytes memory data, uint256 salt) internal virtual {
        wallet.executeTransaction(_singleCall(address(wallet), 0, data), salt);
    }

    function _executeEmergencyWalletSelfCallTimelocked(BaseMERAWallet wallet, bytes memory data, uint256 salt)
        internal
        virtual
    {
        MERAWalletTypes.Call[] memory calls = _singleCall(address(wallet), 0, data);
        if (wallet.getRequiredDelay(calls) == 0) {
            wallet.executeTransaction(calls, salt);
            return;
        }
        bytes32 opId = wallet.proposeTransaction(calls, salt);
        (,,, uint64 executeAfter,,,,,,,) = wallet.operations(opId);
        vm.warp(executeAfter);
        wallet.executePending(calls, salt);
    }

    function _setAllRoleTimelocks(BaseMERAWallet wallet, uint256 delay) internal virtual {
        _executeWalletSelfCall(
            wallet,
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Primary, delay),
            ROLE_TIMELOCK_PRIMARY_SALT
        );
        _executeWalletSelfCall(
            wallet,
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Backup, delay),
            ROLE_TIMELOCK_BACKUP_SALT
        );
        _executeWalletSelfCall(
            wallet,
            abi.encodeWithSelector(wallet.setRoleTimelock.selector, MERAWalletTypes.Role.Emergency, delay),
            ROLE_TIMELOCK_EMERGENCY_SALT
        );
    }
}
