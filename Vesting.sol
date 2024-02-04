// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts@4.7.3/token/ERC20/IERC20.sol";

contract Vesting {
    IERC20 public token;
    address public receiver;
    uint256 public amount;
    uint256 public expiry;
    bool public locked = false;
    bool public claimed = false;

    constructor (address _token) {
        token = IERC20(_token);
    }

    // Here the create project function 
    function lock(address _from, address _receiver, uint256 _amount, uint256 _expiry) external {
        require(!locked, "We have already locked tokens.");
        token.transferFrom(_from, address(this), _amount);
        receiver = _receiver;
        amount = _amount;
        expiry = _expiry;
        locked = true;
    }

    // Here the ERC721 contract to withdraw
    function withdraw() external {
        require(locked, "Funds have not been locked");
        require(block.timestamp > expiry, "Tokens have not been unlocked");
        require(!claimed, "Tokens have already been claimed");
        claimed = true;
        token.transfer(receiver, amount);
    }

    function getTime() external view returns (uint256) {
        return block.timestamp;
    }
}
