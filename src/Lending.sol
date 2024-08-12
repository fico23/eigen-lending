// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILending} from "./ILending.sol";
import {IOracle} from "./IOracle.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Lending is ILending {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant DOUBLE_PRECISION = 1e36;
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    IERC20 public immutable COLLATERAL_TOKEN;
    IERC20 public immutable LOAN_TOKEN;
    IOracle public immutable ORACLE;
    uint256 public immutable ORACLE_SCALE;
    uint256 public immutable LTV;
    uint256 public immutable INTEREST_RATE;
    uint256 public immutable PREMIUM_RATE;
    uint256 public immutable PROTOCOL_FEE;

    // 1 collateral token
    // 1 borrow token
    // LTV
    // interest rate - fixed - per second
    // premium rate - 10%
    // 1 oracle collateral/borrow <->
    // protocol fee - 1% - calculate on every accrual of interest rates

    uint256 public totalDepositAssets;
    uint256 public totalDepositShares;
    uint256 public totalBorrowAssets;
    uint256 public totalBorrowShares;
    uint256 public lastUpdate;
    uint256 public fee;
    mapping(address => Position) internal _userPosition;

    error CantBorrowThatMuch(uint256 totalBorrow, uint256 maxBorrow);

    constructor(
        IERC20 collateralToken,
        IERC20 loanToken,
        IOracle oracle,
        uint256 ltv,
        uint256 interestRate,
        uint256 premiumRate,
        uint256 protocolFee
    ) {
        COLLATERAL_TOKEN = collateralToken;
        LOAN_TOKEN = loanToken;
        ORACLE = oracle;
        ORACLE_SCALE = 10 ** oracle.decimals();
        LTV = ltv;
        INTEREST_RATE = interestRate;
        PREMIUM_RATE = premiumRate;
        PROTOCOL_FEE = protocolFee;

        lastUpdate = block.timestamp;
    }

    function depositCollateral(uint256 assets) external {
        _accrueInterest();

        COLLATERAL_TOKEN.safeTransferFrom(msg.sender, address(this), assets);

        _userPosition[msg.sender].collateral += assets;

        emit DepositedCollateral(msg.sender, assets);
    }

    function withdrawCollateral(uint256 assets) external {
        _accrueInterest();

        _userPosition[msg.sender].collateral -= assets;

        COLLATERAL_TOKEN.safeTransfer(msg.sender, assets);

        emit WithdrawnCollateral(msg.sender, assets);
    }

    function depositLoanToken(uint256 assets) external {
        _accrueInterest();

        LOAN_TOKEN.safeTransferFrom(msg.sender, address(this), assets);

        uint256 shares = _toSharesDown(assets, totalDepositAssets, totalDepositShares);

        _userPosition[msg.sender].depositShares += shares;
        totalDepositShares += shares;
        totalDepositAssets += assets;

        emit DepositedLoanToken(msg.sender, assets, shares);
    }

    function withdrawLoanToken(uint256 shares) external {
        _accrueInterest();

        uint256 assets = _toAssetsDown(shares, totalDepositAssets, totalDepositShares);

        _userPosition[msg.sender].depositShares -= shares;
        totalDepositShares -= shares;
        totalDepositAssets -= assets;

        LOAN_TOKEN.safeTransfer(msg.sender, assets);

        emit WithdrawnLoanToken(msg.sender, assets, shares);
    }

    function borrow(uint256 assets) external {
        _accrueInterest();

        Position storage position = _userPosition[msg.sender];

        uint256 maxBorrow = position.collateral * ORACLE.price() / ORACLE_SCALE * LTV / PRECISION;

        uint256 totalBorrow = _toAssetsDown(position.borrowShares, totalBorrowAssets, totalBorrowShares) + assets;

        if (totalBorrow > maxBorrow) revert CantBorrowThatMuch(totalBorrow, maxBorrow);

        uint256 shares = _toSharesDown(assets, totalBorrowAssets, totalBorrowShares);

        _userPosition[msg.sender].borrowShares += shares;
        totalBorrowShares += shares;
        totalBorrowAssets += assets;

        LOAN_TOKEN.safeTransfer(msg.sender, assets);

        emit Borrowed(msg.sender, assets, shares);
    }

    function repay(uint256 assets) external {
        _accrueInterest();

        uint256 shares = _toSharesDown(assets, totalBorrowAssets, totalDepositShares);

        _userPosition[msg.sender].borrowShares -= shares;
        totalBorrowShares -= shares;
        totalBorrowAssets -= assets;

        LOAN_TOKEN.safeTransferFrom(msg.sender, address(this), assets);

        emit Repayed(msg.sender, assets, shares);
    }

    function accrueInterest() external {
        _accrueInterest();
    }

    function getUserPosition(address user) external view returns (Position memory) {
        return _userPosition[user];
    }

    function _accrueInterest() internal {
        uint256 secondsPassed = block.timestamp - lastUpdate;
        if (secondsPassed == 0) return;

        // not compounded
        uint256 interest = totalBorrowAssets * secondsPassed * INTEREST_RATE / PRECISION;

        totalBorrowAssets += interest;
        totalDepositAssets += interest;
    }

    function _toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDiv(totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS, Math.Rounding.Down);
    }

    function _toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDiv(totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES, Math.Rounding.Down);
    }
}
