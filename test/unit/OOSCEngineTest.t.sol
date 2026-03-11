// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployOOSC} from "../../script/DeployOOSC.s.sol";
import {OOSCEngine} from "../../src/OOSCEngine.sol";
import {OurOwnStablecoin} from "../../src/OurOwnStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MaliciousToken} from "../mocks/MaliciousToken.sol";
import {MaliciousOOSC} from "../mocks/MaliciousOOSC.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
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

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function setUp() public {
        deployer = new DeployOOSC();
        (oosc, ooscEngine, config) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    function getWethPriceFromMock() internal view returns (uint256) {
        return uint256(MockV3Aggregator(ethUsdPriceFeed).latestAnswer());
    }

    //
    // CONSTRUCTOR TESTS
    //

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
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ooscEngine), AMOUNT_COLLATERAL);
        ooscEngine.depositCollateralAndMintOosc(weth, AMOUNT_COLLATERAL, amountOoscToMint);
        vm.stopPrank();

        (uint256 totalOoscMinted, uint256 collateralValueInUsd) = ooscEngine.getAccountInformation(USER);
        assertEq(totalOoscMinted, amountOoscToMint);
        assertGt(collateralValueInUsd, totalOoscMinted);
    }

    //
    // MINT OOSC TESTS
    //

    function test_mintOosc() public depositCollateral {
        uint256 amountOoscToMint = 100 ether;
        vm.startPrank(USER);
        ooscEngine.mintOosc(amountOoscToMint);
        vm.stopPrank();

        (uint256 totalOoscMinted, uint256 collateralValueInUsd) = ooscEngine.getAccountInformation(USER);
        assertEq(totalOoscMinted, amountOoscToMint);
        assertGt(collateralValueInUsd, totalOoscMinted);
    }

    function test_revertsWhenMintAmountIsZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(OOSCEngine.OOSCEngine_MustBeMoreThanZero.selector);
        ooscEngine.mintOosc(0);
        vm.stopPrank();
    }

    function test_revertsWhenMintWouldBreakHealthFactor() public depositCollateral {
        // 10 ETH at $2000 = $20k collateral; with 50% threshold, max safe mint ≈ $10k OOSC
        vm.startPrank(USER);
        uint256 excessMint = 15_000 ether; // over the ~10k limit
        vm.expectRevert(
            abi.encodeWithSelector(OOSCEngine.OOSCEngine_BreaksHealthFactor.selector, 666666666666666666) // 0.666666666666666666 * 1e18
        );
        ooscEngine.mintOosc(excessMint);
        vm.stopPrank();
    }

    function test_revertsForReentrantWhenMintingOosc() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);

        MaliciousOOSC maliciousOosc = new MaliciousOOSC();
        OOSCEngine vulnerableEngine = new OOSCEngine(tokenAddresses, priceFeedAddresses, address(maliciousOosc));
        maliciousOosc.setEngine(address(vulnerableEngine));
        maliciousOosc.transferOwnership(address(vulnerableEngine));

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(vulnerableEngine), AMOUNT_COLLATERAL);
        vulnerableEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vulnerableEngine.mintOosc(100 ether);
        vm.stopPrank();
    }

    //
    // BURN OOSC TESTS
    //

    function test_burnOosc() public {
        uint256 amountToMint = 100 ether;
        uint256 amountToBurn = 50 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ooscEngine), AMOUNT_COLLATERAL);
        ooscEngine.depositCollateralAndMintOosc(weth, AMOUNT_COLLATERAL, amountToMint);
        OurOwnStablecoin(oosc).approve(address(ooscEngine), amountToBurn);
        ooscEngine.burnOosc(amountToBurn);
        vm.stopPrank();

        (uint256 totalOoscMinted, uint256 collateralValueInUsd) = ooscEngine.getAccountInformation(USER);
        assertEq(totalOoscMinted, amountToMint - amountToBurn);
        assertGt(collateralValueInUsd, totalOoscMinted);
    }

    function test_revertsWhenBurnAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ooscEngine), AMOUNT_COLLATERAL);
        ooscEngine.depositCollateralAndMintOosc(weth, AMOUNT_COLLATERAL, 100 ether);

        vm.expectRevert(OOSCEngine.OOSCEngine_MustBeMoreThanZero.selector);
        ooscEngine.burnOosc(0);
        vm.stopPrank();
    }

    function test_revertsWhenBurnAmountExceedsBalance() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ooscEngine), AMOUNT_COLLATERAL);
        ooscEngine.depositCollateralAndMintOosc(weth, AMOUNT_COLLATERAL, 100 ether);
        OurOwnStablecoin(oosc).approve(address(ooscEngine), 101 ether);

        vm.expectRevert(OOSCEngine.OOSCEngine_BurnAmountExceedsBalance.selector);
        ooscEngine.burnOosc(101 ether);
        vm.stopPrank();
    }

    //
    // REDEEM COLLATERAL TESTS
    //

    function test_canRedeemCollateral() public depositCollateral {
        uint256 amountToRedeem = 5 ether;

        (, uint256 collateralValueInUsdBefore) = ooscEngine.getAccountInformation(USER);
        uint256 usdValueRedeemed = ooscEngine.getTokenUsdValue(weth, amountToRedeem);
    
        vm.startPrank(USER);
        ooscEngine.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();

        (uint256 totalOoscMintedAfter, uint256 collateralValueInUsdAfter) = ooscEngine.getAccountInformation(USER);

        assertEq(totalOoscMintedAfter, 0);

        assertEq(collateralValueInUsdAfter, collateralValueInUsdBefore - usdValueRedeemed);
    }

    function test_revertsWhenRedeemAmountIsZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(OOSCEngine.OOSCEngine_MustBeMoreThanZero.selector);
        ooscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_revertsWhenNoCollateralToRedeem() public {
        vm.startPrank(USER);
        vm.expectRevert(OOSCEngine.OOSCEngine_NoCollateralToRedeem.selector);
        ooscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_revertsWhenRedeemBreaksHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ooscEngine), AMOUNT_COLLATERAL);
        ooscEngine.depositCollateralAndMintOosc(weth, AMOUNT_COLLATERAL, 8000 ether);
        vm.stopPrank();

        uint256 redeemPercent = 90; // 90% of collateral
        uint256 amountToRedeem = (AMOUNT_COLLATERAL * redeemPercent) / 100;

        console.log("AMOUNT_COLLATERAL", AMOUNT_COLLATERAL);
        console.log("amountToRedeem", amountToRedeem);

        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(OOSCEngine.OOSCEngine_BreaksHealthFactor.selector, 125000000000000000)
        );
        ooscEngine.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();
    }
}
