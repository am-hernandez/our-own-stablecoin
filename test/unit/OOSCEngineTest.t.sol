// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployOOSC} from "../../script/DeployOOSC.s.sol";
import {OOSCEngine} from "../../src/OOSCEngine.sol";
import {OurOwnStablecoin} from "../../src/OurOwnStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract OOSCEngineTest is Test {
    DeployOOSC deployer;
    OOSCEngine ooscEngine;
    OurOwnStablecoin oosc;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployOOSC();
        (oosc, ooscEngine, config) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //
    // PRICE TESTS
    //

    function test_getUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 *2000/ETH = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = ooscEngine.getTokenUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    //
    // depositCollateral Tests
    //

    function test_revertsIfCollateralZero() public {
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(ooscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(OOSCEngine.OOSCEngine_MustBeMoreThanZero.selector);
        ooscEngine.depositCollateral(weth, 0);

        vm.stopPrank();
    }
}
