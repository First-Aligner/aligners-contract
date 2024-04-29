// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AlignerNFT is ERC721, Ownable {
    uint256 private _nextTokenId;
    mapping(address => bool) private _minters;

    constructor(address initialOwner)
        ERC721("AlignerNFT", "ANFT")
        Ownable(initialOwner)
    {}

    modifier onlyMinter() {
        require(
            _minters[msg.sender] || msg.sender == owner(),
            "Caller is not a minter"
        );
        _;
    }

    function safeMint(address to) public onlyMinter {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }

    function setMinter(address minter, bool allowed) public onlyOwner {
        _minters[minter] = allowed;
    }
}
