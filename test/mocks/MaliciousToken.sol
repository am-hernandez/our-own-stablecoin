// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OOSCEngine} from "../../src/OOSCEngine.sol";

contract MaliciousToken is ERC20 {
    bool attacking;

    constructor() ERC20("Malicious Token", "MAL") {}

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (!attacking) {
            attacking = true;
            OOSCEngine(msg.sender).depositCollateral(address(this), amount);
        }
        return super.transferFrom(from, to, amount);
    }
}
