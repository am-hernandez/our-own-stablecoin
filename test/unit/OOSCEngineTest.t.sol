// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployOOSC} from "../../script/DeployOOSC.s.sol";
import {OOSCEngine} from "../../src/OOSCEngine.sol";
import {OurOwnStablecoin} from "../../src/OurOwnStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MaliciousToken} from "../mocks/MaliciousToken.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {console} from "forge-std/console.sol";

contract OOSCEngineTest is Test {
    DeployOOSC deployer;
    OOSCEngine ooscEngine;
    OurOwnStablecoin oosc;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
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
    // CONSTRUCTOR TESTS
    //

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function test_constructor_RevertsIfTokenAddressesAndPriceFeedAddressesLengthMismatch() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(OOSCEngine.OOSCEngine_TokenAddressesAndPriceFeedAddressesLengthMismatch.selector);
        new OOSCEngine(tokenAddresses, priceFeedAddresses, address(oosc));
    }

    function test_constructor_RevertsIfOOSCAddressIsZeroAddress() public {
        vm.expectRevert(OOSCEngine.OOSCEngine_OOSCAddressCannotBeZeroAddress.selector);
        new OOSCEngine(tokenAddresses, priceFeedAddresses, address(0));
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

    function test_getTokenAmountFromUsd() public view {
        // In HelperConfig, we set the ETH_USD_PRICE to 2000e8
        // - 1 ETH = $2000
        // - $100 of ETH = 0.05 ETH
        uint256 usdAmount = 100 ether;
        uint256 expectedWethAmount = 0.05 ether;
        uint256 actualWethAmount = ooscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWethAmount, expectedWethAmount);
    }

    //
    // DEPOSIT COLLATERAL TESTS
    //

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ooscEngine), AMOUNT_COLLATERAL);
        ooscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function test_revertsWhenCollateralTokenNotAllowed() public {
        ERC20Mock mockToken = new ERC20Mock("Mock Token", "MOCK", USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        vm.expectRevert(OOSCEngine.OOSCEngine_TokenNotAllowed.selector);
        ooscEngine.depositCollateral(address(mockToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_revertsWhenCollateralAmountIsZero() public {
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(ooscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(OOSCEngine.OOSCEngine_MustBeMoreThanZero.selector);
        ooscEngine.depositCollateral(weth, 0);

        vm.stopPrank();
    }

    function test_canDepositCollateralAndGetAccountInformation() public depositCollateral {
        (uint256 totalOoscMinted, uint256 collateralValueInUsd) = ooscEngine.getAccountInformation(USER);

        uint256 expectedTotalOoscMinted = 0;
        uint256 expectedDepositAmount = ooscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalOoscMinted, expectedTotalOoscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function test_revertsForReentrantWhenDepositingCollateral() public depositCollateral {
        MaliciousToken maliciousToken = new MaliciousToken();

        tokenAddresses.push(address(maliciousToken));
        priceFeedAddresses.push(ethUsdPriceFeed);

        OOSCEngine vulnerableOoscEngine = new OOSCEngine(tokenAddresses, priceFeedAddresses, address(oosc));

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(vulnerableOoscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vulnerableOoscEngine.depositCollateral(address(maliciousToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_depositCollateralAndMintOosc() public {
        uint256 amountOoscToMint = 100 ether;
        // approve the oosc engine to mint the oosc
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ooscEngine), AMOUNT_COLLATERAL);
        ooscEngine.depositCollateralAndMintOosc(weth, AMOUNT_COLLATERAL, amountOoscToMint);
        vm.stopPrank();

        (uint256 totalOoscMinted, uint256 collateralValueInUsd) = ooscEngine.getAccountInformation(USER);
        assertEq(totalOoscMinted, amountOoscToMint);
        assertGt(collateralValueInUsd, totalOoscMinted);
    }
}
