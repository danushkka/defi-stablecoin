// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (
            address cnyPriceFeedAddress,
            address wETHPriceFeedAddress,
            address wBTCPriceFeedAddress,
            address wETH,
            address wBTC,
            uint256 deployerKey
        ) = config.activeNetworkConfig();

        tokenAddresses = [wETH, wBTC];
        priceFeedAddresses = [wETHPriceFeedAddress, wBTCPriceFeedAddress];

        vm.startBroadcast(deployerKey);
        address deployer = vm.addr(deployerKey);

        DecentralizedStableCoin dsc = new DecentralizedStableCoin(deployer);
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, cnyPriceFeedAddress, address(dsc));

        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dsc, dscEngine, config);
    }
}
