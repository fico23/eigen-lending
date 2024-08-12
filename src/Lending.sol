// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import {ILending} from "./ILending.sol";
import {IOracle} from "./IOracle.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";

contract LendingProtocol is ReentrancyGuard, ILending {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant DOUBLE_PRECISION = 1e36;

    IERC20 public immutable COLLATERAL_TOKEN;
    IERC20 public immutable LOAN_TOKEN;
    IOracle public immutable ORACLE;
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

    uint256 totalDepositAssets;
    uint256 totalDepositShares;
    uint256 totalBorrowAssets;
    uint256 totalBorrowShares;
    uint256 lastUpdate;
    uint256 fee;

    uint256 _lastInterestAccrualTimestamp;
    uint256 _interestAnchor;
    mapping(address => Position) internal _userPosition;

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
        LTV = ltv;
        INTEREST_RATE = interestRate;
        PREMIUM_RATE = premiumRate;
        PROTOCOL_FEE = protocolFee;
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

        uint256 shares = assets.mulDiv(totalDepositShares, totalDepositAssets, Math.Rounding.Floor);

        _userPosition[msg.sender].depositShares += shares;
        totalBorrowShares += shares;
        totalBorrowAssets += assets;

        emit DepositedLoanToken(msg.sender, assets, shares);
    }

    function withdrawLoanToken(uint256 shares) external {
        _accrueInterest();

        uint256 assets = shares.mulDiv(totalDepositAssets, totalDepositShares, Math.Rounding.Floor);

        _userPosition[msg.sender].depositShares -= shares;
        totalDepositShares -= shares;
        totalDepositAssets -= assets;

        LOAN_TOKEN.safeTransfer(msg.sender, assets);

        emit WithdrawnLoanToken(msg.sender, assets, shares);
    }

    function borrow(uint256 assets) external {
        _accrueInterest();

        uint256 shares = assets.mulDiv(totalDepositShares, totalBorrowAssets, Math.Rounding.Floor);

        _userPosition[msg.sender].borrowShares += shares;
        totalBorrowShares += shares;
        totalBorrowAssets += assets;

        LOAN_TOKEN.safeTransfer(msg.sender, assets);

        emit Borrowed(msg.sender, assets, shares);
    }

    function repay(uint256 assets) external {
        _accrueInterest();

        uint256 shares = assets.mulDiv(totalDepositShares, totalBorrowAssets, Math.Rounding.Floor);

        _userPosition[msg.sender].borrowShares -= shares;
        totalBorrowShares -= shares;
        totalBorrowAssets -= assets;

        LOAN_TOKEN.safeTransfer(msg.sender, assets);

        emit Repayed(msg.sender, assets, shares);
    }

    function _accrueInterest() internal {
        uint256 secondsPassed = block.timestamp - _lastInterestAccrualTimestamp;
        _interestAnchor *= INTEREST_RATE * secondsPassed / PRECISION;
    }
}
