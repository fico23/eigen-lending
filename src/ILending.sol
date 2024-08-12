// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILending {
    function depositCollateral(uint256 assets) external;
    function withdrawCollateral(uint256 assets) external;
    function depositLoanToken(uint256 assets) external;
    function withdrawLoanToken(uint256 assets) external;
    function borrow(uint256 assets) external;
    function repay(uint256 assets) external;
    // function liquidate

    event DepositedCollateral(address user, uint256 assets);
    event WithdrawnCollateral(address user, uint256 assets);
    event DepositedLoanToken(address user, uint256 assets, uint256 shares);
    event WithdrawnLoanToken(address user, uint256 assets, uint256 shares);
    event Borrowed(address user, uint256 assets, uint256 shares);
    event Repayed(address user, uint256 assets, uint256 shares);

    struct Position {
        uint256 depositShares;
        uint256 borrowShares;
        uint256 collateral;
    }
}
