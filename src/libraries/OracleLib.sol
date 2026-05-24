// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title OracleLib
 * @author daniko
 *
 * This is a library that contains the functions related to the Chainlink Oracles.
 * It is used by the DSCEngine to monitor the price of the collateral tokens and prevent the DSC System from
 * collapsing if Chainlink crashes. The library is designed to be used with the Chainlink AggregatorV3Interface,
 * which is the interface for the Chainlink Price Feeds.
 *
 * The core idea: Freeze the DSC System if the price is too old or if the price is too far from the last price.
 */

library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant MAX_TIME_SINCE_LAST_UPDATE = 3 hours; // 3 hours = 10800 seconds

    function stalePriceCheck(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed.latestRoundData();
        uint256 timePassedSinceLastUpdate = block.timestamp - updatedAt;

        if (timePassedSinceLastUpdate > MAX_TIME_SINCE_LAST_UPDATE) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
