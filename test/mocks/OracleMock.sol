// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../../src/IOracle.sol";

contract OracleMock is IOracle {
    uint256 internal _price;

    function setPrice(uint256 newPrice) external {
        _price = newPrice;
    }

    function price() external view returns (uint256) {
        return _price;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}
