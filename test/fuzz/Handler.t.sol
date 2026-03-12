// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {OOSCEngine} from "../../src/OOSCEngine.sol";
import {OurOwnStablecoin} from "../../src/OurOwnStablecoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract Handler is Test {
    OOSCEngine ooscEngine;
    OurOwnStablecoin oosc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 timesRedeemIsCalled = 0;

    address[] public depositors;

    constructor(OOSCEngine _ooscEngine, OurOwnStablecoin _oosc) {
        ooscEngine = _ooscEngine;
        oosc = _oosc;

        address[] memory collateralTokens = ooscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    // - Don't call redeemCollateral unless there is collateral to redeem.
    // - Don't call mintOosc if there is no collateral to mint.
    // - Don't call liquidate if the health factor is not broken.
    // - Don't call burnOosc if there is no OOSC to burn.
    // - etc.

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(ooscEngine), amountCollateral);
        ooscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        depositors.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral, uint256 depositorSeed) public {
        if (depositors.length == 0) return;
        address depositor = depositors[depositorSeed % depositors.length];
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = ooscEngine.getCollateralBalanceOfUser(depositor, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        if (amountCollateral == 0) {
            return;
        }

        timesRedeemIsCalled++;
        console.log("timesRedeemIsCalled", timesRedeemIsCalled);

        vm.startPrank(depositor);
        ooscEngine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }

        return wbtc;
    }
}
