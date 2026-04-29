// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MERAWalletFull} from "../src/extensions/MERAWalletFull.sol";
import {IBaseMERAWalletErrors} from "../src/interfaces/IBaseMERAWalletErrors.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {MERAWalletTargetWhitelistChecker} from "../src/checkers/MERAWalletTargetWhitelistChecker.sol";
import {IMERAWalletWhitelistErrors} from "../src/checkers/errors/IMERAWalletWhitelistErrors.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ReceiverMock} from "./mocks/ReceiverMock.sol";

contract MERAWalletFullTest is Test {
    uint256 internal primaryPk = 0xA11CE;

    address internal primary = vm.addr(primaryPk);
    address internal backup = vm.addr(0xB0B);
    address internal emergency = vm.addr(0xE911);
    address internal outsider = address(0x1234);

    MERAWalletFull internal wallet;
    ReceiverMock internal receiver;
    ERC20Mock internal token;
    MERAWalletTargetWhitelistChecker internal targetWhitelistChecker;

    function setUp() public {
        wallet = new MERAWalletFull(primary, backup, emergency, address(0), address(0));
        receiver = new ReceiverMock();
        token = new ERC20Mock();
        targetWhitelistChecker = new MERAWalletTargetWhitelistChecker(emergency);

        vm.startPrank(emergency);
        _setAllRoleTimelocks(0);
        wallet.setOptionalCheckers(_mkWl(address(0), true, ""));
        vm.stopPrank();
    }

    function test_LifeControl_BlocksExtensionCallsUntilHeartbeat() public {
        vm.prank(emergency);
        wallet.setLifeControl(true, 1 days);

        vm.deal(address(wallet), 1 ether);
        vm.warp(block.timestamp + 2 days);

        vm.prank(primary);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBaseMERAWalletErrors.LifeHeartbeatExpired.selector,
                wallet.lastLifeHeartbeatAt(),
                wallet.lifeHeartbeatTimeout(),
                block.timestamp
            )
        );
        wallet.transferNative(payable(outsider), 0.1 ether, 1);

        vm.prank(emergency);
        wallet.confirmAlive();

        uint256 outsiderBalanceBefore = outsider.balance;
        vm.prank(primary);
        wallet.transferNative(payable(outsider), 0.1 ether, 1);
        assertEq(outsider.balance, outsiderBalanceBefore + 0.1 ether);
    }

    function test_TransferNativeWrapper_ExecutesSingleCall() public {
        vm.deal(address(wallet), 2 ether);

        vm.prank(primary);
        wallet.transferNative(payable(address(receiver)), 1 ether, 1);

        assertEq(address(receiver).balance, 1 ether);
    }

    function test_TransferERC20AndApproveWrappers() public {
        token.mint(address(wallet), 1000);

        vm.prank(primary);
        wallet.transferERC20(address(token), outsider, 250, address(0), "", 1);
        assertEq(token.balanceOf(outsider), 250);

        vm.prank(primary);
        wallet.callExternal(address(token), 0, abi.encodeWithSelector(IERC20.approve.selector, outsider, 400), 2);
        assertEq(token.allowance(address(wallet), outsider), 400);
    }

    function test_TargetWhitelistChecker_AllowsConfiguredTargetsAndWrappers() public {
        vm.deal(address(wallet), 2 ether);
        token.mint(address(wallet), 1000);

        vm.startPrank(emergency);
        targetWhitelistChecker.setAllowedTarget(address(receiver), true);
        targetWhitelistChecker.setAllowedTarget(address(token), true);
        {
            (address[] memory __rqA, bool[] memory __rqB) = _mkReq(address(targetWhitelistChecker), true);
            wallet.setRequiredCheckers(__rqA, __rqB);
        }
        vm.stopPrank();

        vm.prank(primary);
        wallet.transferNative(payable(address(receiver)), 1 ether, 1);
        assertEq(address(receiver).balance, 1 ether);

        vm.prank(primary);
        wallet.transferERC20(address(token), outsider, 250, address(0), "", 2);
        assertEq(token.balanceOf(outsider), 250);

        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(IMERAWalletWhitelistErrors.TargetNotAllowed.selector, outsider, 0));
        wallet.callExternal(outsider, 0, "", 3);
    }

    function _mkReq(address c, bool e) internal pure returns (address[] memory cc, bool[] memory ee) {
        cc = new address[](1);
        ee = new bool[](1);
        cc[0] = c;
        ee[0] = e;
    }

    function _mkWl(address checker, bool allowed, bytes memory config)
        internal
        pure
        returns (MERAWalletTypes.OptionalCheckerUpdate[] memory u)
    {
        u = new MERAWalletTypes.OptionalCheckerUpdate[](1);
        u[0] = MERAWalletTypes.OptionalCheckerUpdate({checker: checker, allowed: allowed, config: config});
    }

    function _setAllRoleTimelocks(uint256 delay) internal {
        wallet.setRoleTimelock(MERAWalletTypes.Role.Primary, delay);
        wallet.setRoleTimelock(MERAWalletTypes.Role.Backup, delay);
        wallet.setRoleTimelock(MERAWalletTypes.Role.Emergency, delay);
    }
}
