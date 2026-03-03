// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title OurOwnStablecoin
 * @author A.M. Hernandez
 * @notice This contract is a stablecoin that is anchored to the price of ETH and BTC.
 * @notice Collateral: Exogenous (ETH & BTC)
 * @notice Minting: Algorithmic (Decentralized)
 * @notice Relative Stability: pegged to USD
 * @notice This is the contract meant to be governed by OOSCEngine. This contract is the ERC20 implementation of our stablecoin system.
 */
contract OurOwnStablecoin is ERC20Burnable, Ownable {
    error OurOwnStablecoin_MustBeMoreThanZero();
    error OurOwnStablecoin_BurnAmountExceedsBalance();
    error OurOwnStablecoin_MustNotBeZeroAddress();

    constructor() ERC20("OurOwnStablecoin", "OOSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert OurOwnStablecoin_MustBeMoreThanZero();
        }

        if (balance < _amount) {
            revert OurOwnStablecoin_BurnAmountExceedsBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert OurOwnStablecoin_MustNotBeZeroAddress();
        }

        if (_amount <= 0) {
            revert OurOwnStablecoin_MustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }
}
