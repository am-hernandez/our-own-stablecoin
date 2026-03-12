// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OOSCEngine} from "../../src/OOSCEngine.sol";
import {OurOwnStablecoin} from "../../src/OurOwnStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../test/mocks/ERC20Mock.sol";
import {DeployOOSC} from "../../script/DeployOOSC.s.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    OOSCEngine ooscEngine;
    DeployOOSC deployer;
    OurOwnStablecoin oosc;
    HelperConfig config;
    Handler handler;

    address weth;
    address wbtc;
    address USER = makeAddr("user");
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployOOSC();
        (oosc, ooscEngine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();

        // targetContract(address(ooscEngine));
        handler = new Handler(ooscEngine, oosc);
        targetContract(address(handler));
    }

    function invariant_totalSupplyOfOOSCIsLessThanTotalValueOfCollateral() public view {
        uint256 totalSupply = oosc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(ooscEngine));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(ooscEngine));

        uint256 wethValue = ooscEngine.getTokenUsdValue(weth, totalWethDeposited);
        uint256 btcValue = ooscEngine.getTokenUsdValue(wbtc, totalBtcDeposited);

        console.log("totalSupply", totalSupply);
        console.log("wethValue", wethValue);
        console.log("btcValue", btcValue);

        assert(totalSupply == 0 && wethValue == 0 && btcValue == 0 || wethValue + btcValue > totalSupply);
    }
}
