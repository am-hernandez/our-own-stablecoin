// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OOSCEngine} from "../../src/OOSCEngine.sol";

contract MaliciousOOSC is ERC20, ERC20Burnable, Ownable {
    address public engine;

    constructor() ERC20("Malicious OOSC", "MOOSC") Ownable(msg.sender) {}

    function setEngine(address _engine) external onlyOwner {
        engine = _engine;
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (engine != address(0)) {
            OOSCEngine(engine).mintOosc(_amount);
        }
        _mint(_to, _amount);
        return true;
    }

    function burn(uint256 amount) public override onlyOwner {
        super.burn(amount);
    }
}
