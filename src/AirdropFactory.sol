pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AirdropFactory is Ownable {
    constructor(address initialOwner) Ownable(initialOwner) {}
}
