// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address cnyPriceFeedAddress;
        address wETHPriceFeedAddress;
        address wBTCPriceFeedAddress;
        address wETH;
        address wBTC;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant CNY_PRICE = 0.148e8;
    int256 public constant ETH_PRICE = 2000e8;
    int256 public constant BTC_PRICE = 60_000e8;

    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            cnyPriceFeedAddress: 0xeF8A4aF35cd47424672E3C590aBD37FBB7A7759a,
            wETHPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wBTCPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wETHPriceFeedAddress != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator cnyPriceFeed = new MockV3Aggregator(DECIMALS, CNY_PRICE);

        MockV3Aggregator wEthPriceFeed = new MockV3Aggregator(DECIMALS, ETH_PRICE);
        ERC20Mock wEthMock = new ERC20Mock();

        MockV3Aggregator wBtcPriceFeed = new MockV3Aggregator(DECIMALS, BTC_PRICE);
        ERC20Mock wBtcMock = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            cnyPriceFeedAddress: address(cnyPriceFeed),
            wETHPriceFeedAddress: address(wEthPriceFeed),
            wBTCPriceFeedAddress: address(wBtcPriceFeed),
            wETH: address(wEthMock),
            wBTC: address(wBtcMock),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}
