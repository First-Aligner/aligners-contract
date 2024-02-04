// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VestingNFT is ERC721, Ownable {
    IERC20 public erc20Token;
    
    // Vesting schedule data structure
    struct VestingSchedule {
        uint256 releaseTime;
        uint256 amount;
        bool released;
    }

    // Mapping from token ID to vesting schedule
    mapping(uint256 => VestingSchedule[]) public vestingSchedules;

    constructor(
        string memory _name,
        string memory _symbol,
        address _erc20Token
    ) ERC721(_name, _symbol) {
        erc20Token = IERC20(_erc20Token);
    }

    // Mint a new NFT with a vesting schedule
    function mintWithVesting(
        address to,
        uint256 tokenId,
        uint256[] memory releaseTimes,
        uint256[] memory amounts
    ) external onlyOwner {
        require(releaseTimes.length == amounts.length, "Array length mismatch");

        _mint(to, tokenId);

        for (uint256 i = 0; i < releaseTimes.length; i++) {
            vestingSchedules[tokenId].push(VestingSchedule({
                releaseTime: releaseTimes[i],
                amount: amounts[i],
                released: false
            }));
        }
    }

    // Release vested tokens
    function releaseVestedTokens(uint256 tokenId) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved or not owner");

        VestingSchedule[] storage schedules = vestingSchedules[tokenId];

        for (uint256 i = 0; i < schedules.length; i++) {
            if (!schedules[i].released && block.timestamp >= schedules[i].releaseTime) {
                schedules[i].released = true;
                erc20Token.transfer(msg.sender, schedules[i].amount);
            }
        }
    }

    // Get the vesting schedule for a token
    function getVestingSchedule(uint256 tokenId) external view returns (VestingSchedule[] memory) {
        return vestingSchedules[tokenId];
    }
}