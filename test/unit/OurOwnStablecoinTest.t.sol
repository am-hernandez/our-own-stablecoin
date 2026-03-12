// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {OurOwnStablecoin} from "../../src/OurOwnStablecoin.sol";

contract OurOwnStablecoinTest is Test {
    OurOwnStablecoin oosc;

    address public USER = makeAddr("user");

    function setUp() public {
        oosc = new OurOwnStablecoin();
    }

    function test_mint_Success() public {
        uint256 amount = 100 ether;
        oosc.mint(USER, amount);
        assertEq(oosc.balanceOf(USER), amount);
    }

    function test_mint_RevertWhenToIsZeroAddress() public {
        vm.expectRevert(OurOwnStablecoin.OurOwnStablecoin_MustNotBeZeroAddress.selector);
        oosc.mint(address(0), 100 ether);
    }

    function test_mint_RevertWhenAmountIsZero() public {
        vm.expectRevert(OurOwnStablecoin.OurOwnStablecoin_MustBeMoreThanZero.selector);
        oosc.mint(USER, 0);
    }

    function test_burn_Success() public {
        uint256 mintAmount = 100 ether;
        uint256 burnAmount = 40 ether;
        oosc.mint(address(this), mintAmount);
        oosc.burn(burnAmount);
        assertEq(oosc.balanceOf(address(this)), mintAmount - burnAmount);
    }

    function test_burn_RevertWhenAmountIsZero() public {
        oosc.mint(address(this), 100 ether);
        vm.expectRevert(OurOwnStablecoin.OurOwnStablecoin_MustBeMoreThanZero.selector);
        oosc.burn(0);
    }

    function test_burn_RevertWhenAmountExceedsBalance() public {
        oosc.mint(address(this), 100 ether);
        vm.expectRevert(OurOwnStablecoin.OurOwnStablecoin_BurnAmountExceedsBalance.selector);
        oosc.burn(150 ether);
    }
}
