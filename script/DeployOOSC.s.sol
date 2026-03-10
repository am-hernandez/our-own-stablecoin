// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {OOSCEngine} from "../src/OOSCEngine.sol";
import {OurOwnStablecoin} from "../src/OurOwnStablecoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployOOSC is Script {
    function run() external returns (OurOwnStablecoin, OOSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = weth;
        tokenAddresses[1] = wbtc;

        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = wethUsdPriceFeed;
        priceFeedAddresses[1] = wbtcUsdPriceFeed;

        vm.startBroadcast(deployerKey);

        OurOwnStablecoin oosc = new OurOwnStablecoin();
        OOSCEngine ooscEngine = new OOSCEngine(tokenAddresses, priceFeedAddresses, address(oosc));

        oosc.transferOwnership(address(ooscEngine));

        vm.stopBroadcast();

        return (oosc, ooscEngine, helperConfig);
    }
}
