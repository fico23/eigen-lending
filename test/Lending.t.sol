// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Lending} from "../src/Lending.sol";
import {ERC20Mock} from "@openzeppelin/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {OracleMock} from "./mocks/OracleMock.sol";
import {ILending} from "../src/ILending.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";

contract CounterTest is Test {
    using Math for uint256;

    ERC20Mock public collateralToken;
    ERC20Mock public loanToken;
    Lending public lending;
    OracleMock public oracle;

    uint256 internal constant ORACLE_SCALE = 10 ** 18;
    uint256 internal constant PRECISION = 1e18;

    uint256 internal constant USER_COLLATERAL_BALANCE = 1e30;
    uint256 internal constant USER_LOANTOKEN_BALANCE = 1e30;
    uint256 internal constant LTV = 8e17;
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;
    // accounts roughly to 10% yearly
    uint256 internal constant INTEREST_RATE = 3170979198;
    // 5%
    uint256 internal constant PREMIUM_RATE = 5e16;
    // 1%
    uint256 internal constant PROTOCOL_FEE = 1e16;

    address internal constant ALICE = address(0xabcd);
    address internal constant BOB = address(0xdcba);

    event DepositedCollateral(address user, uint256 assets);
    event WithdrawnCollateral(address user, uint256 assets);
    event DepositedLoanToken(address user, uint256 assets, uint256 shares);
    event WithdrawnLoanToken(address user, uint256 assets, uint256 shares);
    event Borrowed(address user, uint256 assets, uint256 shares);
    event Repayed(address user, uint256 assets, uint256 shares);

    function setUp() public {
        collateralToken = new ERC20Mock();
        collateralToken.mint(address(this), USER_COLLATERAL_BALANCE);
        collateralToken.mint(ALICE, USER_COLLATERAL_BALANCE);
        collateralToken.mint(BOB, USER_COLLATERAL_BALANCE);

        loanToken = new ERC20Mock();
        loanToken.mint(address(this), USER_LOANTOKEN_BALANCE);
        loanToken.mint(ALICE, USER_LOANTOKEN_BALANCE);
        loanToken.mint(BOB, USER_LOANTOKEN_BALANCE);

        oracle = new OracleMock();
        oracle.setPrice(1e19);

        lending = new Lending(
            IERC20(address(collateralToken)),
            IERC20(address(loanToken)),
            oracle,
            LTV,
            INTEREST_RATE,
            PREMIUM_RATE,
            PROTOCOL_FEE
        );
    }

    function test_depositCollateral(uint256 assets) public {
        vm.assume(assets < USER_COLLATERAL_BALANCE);

        _depositCollateral(ALICE, assets);

        Lending.Position memory userPosition = lending.getUserPosition(ALICE);

        assertEq(userPosition.collateral, assets);
        assertEq(collateralToken.balanceOf(address(lending)), assets);
    }

    function test_withdrawCollateral(uint256 assets) public {
        vm.assume(assets < USER_COLLATERAL_BALANCE);

        _depositCollateral(ALICE, assets);

        _withdrawCollateral(ALICE, assets);

        Lending.Position memory userPosition = lending.getUserPosition(ALICE);

        assertEq(userPosition.collateral, 0);
        assertEq(collateralToken.balanceOf(address(lending)), 0);
    }

    function test_depositLoanToken(uint256 assets) public {
        vm.assume(assets < USER_LOANTOKEN_BALANCE);

        uint256 expectedShares = assets.mulDiv(VIRTUAL_SHARES, VIRTUAL_ASSETS, Math.Rounding.Floor);

        _depositLoanToken(ALICE, assets, expectedShares);

        Lending.Position memory userPosition = lending.getUserPosition(ALICE);

        assertEq(userPosition.depositShares, expectedShares);
        assertEq(lending.totalDepositAssets(), assets);
        assertEq(lending.totalDepositShares(), expectedShares);
    }

    function test_withdrawLoanToken(uint256 assets) public {
        vm.assume(assets < USER_LOANTOKEN_BALANCE);

        uint256 expectedShares = assets.mulDiv(VIRTUAL_SHARES, VIRTUAL_ASSETS, Math.Rounding.Floor);

        _depositLoanToken(ALICE, assets, expectedShares);

        uint256 expectedAssets =
            expectedShares.mulDiv(assets + VIRTUAL_ASSETS, expectedShares + VIRTUAL_SHARES, Math.Rounding.Floor);

        _withdrawLoanToken(ALICE, expectedShares, expectedAssets);

        Lending.Position memory userPosition = lending.getUserPosition(ALICE);

        assertEq(userPosition.depositShares, 0);
        assertEq(lending.totalDepositAssets(), 0);
        assertEq(lending.totalDepositShares(), 0);
    }

    function test_borrowMax(uint256 assets) public {
        vm.assume(assets < USER_LOANTOKEN_BALANCE);
        vm.assume(assets > 10);

        uint256 expectedMaxBorrow = assets * oracle.price() / ORACLE_SCALE * LTV / PRECISION;

        vm.assume(expectedMaxBorrow < USER_LOANTOKEN_BALANCE);

        _depositCollateral(ALICE, assets);

        uint256 expectedShares = expectedMaxBorrow.mulDiv(VIRTUAL_SHARES, VIRTUAL_ASSETS, Math.Rounding.Floor);
        _depositLoanToken(BOB, expectedMaxBorrow, expectedShares);

        _borrow(ALICE, expectedMaxBorrow, expectedShares);

        Lending.Position memory userPosition = lending.getUserPosition(ALICE);

        assertEq(userPosition.borrowShares, expectedShares);
        assertEq(lending.totalBorrowAssets(), expectedMaxBorrow);
        assertEq(lending.totalBorrowShares(), expectedShares);
    }

    function test_borrow_revertWith_CantBorrowThatMuch(uint256 assets) public {
        vm.assume(assets < USER_LOANTOKEN_BALANCE);
        vm.assume(assets > 10);

        uint256 expectedMaxBorrow = assets * oracle.price() / ORACLE_SCALE * LTV / PRECISION;

        vm.assume(expectedMaxBorrow < USER_LOANTOKEN_BALANCE);

        _depositCollateral(ALICE, assets);

        uint256 expectedShares = expectedMaxBorrow.mulDiv(VIRTUAL_SHARES, VIRTUAL_ASSETS, Math.Rounding.Floor);
        _depositLoanToken(BOB, expectedMaxBorrow, expectedShares);

        vm.expectRevert(
            abi.encodeWithSelector(Lending.CantBorrowThatMuch.selector, expectedMaxBorrow + 1, expectedMaxBorrow)
        );
        vm.prank(ALICE);
        lending.borrow(expectedMaxBorrow + 1);
    }

    function test_borrowMaxAndRepay(uint256 assets) public {
        vm.assume(assets < USER_LOANTOKEN_BALANCE);
        vm.assume(assets > 10);

        uint256 expectedMaxBorrow = assets * oracle.price() / ORACLE_SCALE * LTV / PRECISION;

        vm.assume(expectedMaxBorrow < USER_LOANTOKEN_BALANCE);

        _depositCollateral(ALICE, assets);

        uint256 expectedShares = expectedMaxBorrow.mulDiv(VIRTUAL_SHARES, VIRTUAL_ASSETS, Math.Rounding.Floor);
        _depositLoanToken(BOB, expectedMaxBorrow, expectedShares);

        _borrow(ALICE, expectedMaxBorrow, expectedShares);

        _repay(ALICE, expectedMaxBorrow, expectedShares);

        Lending.Position memory userPosition = lending.getUserPosition(ALICE);

        assertEq(userPosition.borrowShares, 0);
        assertEq(lending.totalBorrowAssets(), 0);
        assertEq(lending.totalBorrowShares(), 0);
    }

    function test_interestAccrual(uint256 assets) public {
        vm.assume(assets < USER_LOANTOKEN_BALANCE);
        vm.assume(assets > 10);

        uint256 expectedMaxBorrow = assets * oracle.price() / ORACLE_SCALE * LTV / PRECISION;

        vm.assume(expectedMaxBorrow < USER_LOANTOKEN_BALANCE);

        _depositCollateral(ALICE, assets);

        uint256 expectedShares = expectedMaxBorrow.mulDiv(VIRTUAL_SHARES, VIRTUAL_ASSETS, Math.Rounding.Floor);
        _depositLoanToken(BOB, expectedMaxBorrow, expectedShares);

        _borrow(ALICE, expectedMaxBorrow, expectedShares);

        uint256 timePassed = 10 days;
        skip(timePassed);

        lending.accrueInterest();

        uint256 interest = timePassed * expectedMaxBorrow * INTEREST_RATE / PRECISION;

        assertEq(lending.totalBorrowAssets(), expectedMaxBorrow + interest);
        assertEq(lending.totalDepositAssets(), expectedMaxBorrow + interest);
    }

    function _repay(address from, uint256 assets, uint256 expectedShares) internal {
        vm.startPrank(from);

        loanToken.approve(address(lending), assets);

        vm.expectEmit(false, false, false, true);
        emit Repayed(from, assets, expectedShares);
        lending.repay(assets);

        vm.stopPrank();
    }

    function _borrow(address from, uint256 assets, uint256 expectedShares) internal {
        vm.prank(from);

        vm.expectEmit(false, false, false, true);
        emit Borrowed(from, assets, expectedShares);
        lending.borrow(assets);
    }

    function _depositLoanToken(address from, uint256 assets, uint256 expectedShares) internal {
        vm.startPrank(from);
        loanToken.approve(address(lending), assets);

        vm.expectEmit(false, false, false, true);
        emit DepositedLoanToken(from, assets, expectedShares);
        lending.depositLoanToken(assets);
        vm.stopPrank();
    }

    function _withdrawLoanToken(address from, uint256 shares, uint256 expectedAssets) internal {
        vm.prank(from);
        vm.expectEmit(false, false, false, true);
        emit WithdrawnLoanToken(from, expectedAssets, shares);
        lending.withdrawLoanToken(shares);
    }

    function _depositCollateral(address from, uint256 assets) internal {
        vm.startPrank(from);
        collateralToken.approve(address(lending), assets);

        vm.expectEmit(false, false, false, true);
        emit DepositedCollateral(from, assets);
        lending.depositCollateral(assets);
        vm.stopPrank();
    }

    function _withdrawCollateral(address from, uint256 assets) internal {
        vm.prank(from);
        vm.expectEmit(false, false, false, true);
        emit WithdrawnCollateral(from, assets);
        lending.withdrawCollateral(assets);
    }
}
