// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts@4.7.3/token/ERC20/IERC20.sol";

// Or VestingContract
contract ProjectContract {
    IERC20 public token;
    address public owner;
    string public projectName;
    string public projectDescription;
    string public socialInfo;
    uint256 public biddingStartDate;
    uint256 public biddingEndDate; // Added variable to store the bidding end date
    bool public biddingActive; // Added variable to track bidding status
    VestingRound[] public vestingRounds;

    struct VestingRound {
        uint256 roundAmount; // Round vesting amount (default 100 000 IVO)
        uint256 ivoPrice; // IVO price in USDT
    }

    // Events to log important activities
    event VestingRoundAdded(
        uint256 roundIndex,
        uint256 roundAmount,
        uint256 ivoPrice
    );
    event BiddingEnded(); // Added event to log the end of bidding
    event BidPlaced(
        address indexed bidder,
        uint256 allocationSize,
        uint256 vestingLength,
        uint256 ivoPrice
    );

    // Modifier to ensure that only the owner can execute certain functions
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    modifier onlyDuringBidding() {
        require(
            biddingActive &&
                block.timestamp >= biddingStartDate &&
                block.timestamp <= biddingEndDate,
            "Bidding is not active or has ended"
        );
        _;
    }

    // Constructor to initialize the contract
    constructor(
        address _token,
        string memory _projectName,
        string memory _projectDescription,
        string memory _socialInfo,
        uint256 _biddingStartDate,
        uint256 _biddingDuration // Added parameter for bidding duration
    ) {
        token = IERC20(_token);
        owner = msg.sender;
        projectName = _projectName;
        projectDescription = _projectDescription;
        socialInfo = _socialInfo;
        biddingStartDate = _biddingStartDate;
        biddingEndDate = _biddingStartDate + _biddingDuration; // Set bidding end date
        biddingActive = true; // Activate bidding on contract deployment
    }

    function placeBid2(uint256 _allocationSize, uint256 _vestingLength)
        public
        payable
    {
        // Complete the function
    }

    function placeBid(uint256 _allocationSize, uint256 _vestingLength)
        public
        payable
        onlyDuringBidding
    {
        // Ensure that the bid amount is greater than 0
        // TODO Ensure the amount divided by 100
        require(msg.value > 0, "Bid amount must be greater than 0");

        // Calculate the total bid amount by multiplying the allocation size with the IVO price
        uint256 totalBidAmount = _allocationSize * getCurrentIvoPrice();

        // Ensure that the sent Ether matches the calculated bid amount
        require(msg.value == totalBidAmount, "Incorrect bid amount sent");

        // Transfer the bid amount in tokens from the bidder to the contract
        require(
            token.transferFrom(msg.sender, address(this), _allocationSize),
            "Failed to transfer tokens"
        );

        // Update the contract state to reflect the bid
        // Here, you might want to store the bid information, such as the bidder's address, allocation size, vesting length, etc.
        // For simplicity, let's assume you have a mapping to store bidder information:
        // mapping(address => Bid) public bids;
        // where Bid is a struct containing relevant information about the bid.

        // Emit an event to log the bid placement
        // You can customize the event parameters based on your contract requirements
        emit BidPlaced(
            msg.sender,
            _allocationSize,
            _vestingLength,
            getCurrentIvoPrice()
        );
    }

    // Function to get the current IVO price based on the latest vesting round
    function getCurrentIvoPrice() public view returns (uint256) {
        require(vestingRounds.length > 0, "No vesting rounds available");
        return vestingRounds[vestingRounds.length - 1].ivoPrice;
    }

    // Function to add a vesting round
    function endBidding() external onlyOwner {
        require(biddingActive, "Bidding has already ended");
        biddingActive = false;
        emit BiddingEnded();
    }

    // Function to add a vesting round
    function addVestingRound(uint256 _roundAmount, uint256 _ivoPrice)
        external
        onlyOwner
        onlyDuringBidding // Ensure that vesting rounds can only be added during the bidding period
    {
        uint256 roundIndex = vestingRounds.length;
        vestingRounds.push(VestingRound(_roundAmount, _ivoPrice));

        // Emit an event to log the addition of a vesting round
        emit VestingRoundAdded(roundIndex, _roundAmount, _ivoPrice);
    }

    // Function to get the total number of vesting rounds
    function getNumberOfVestingRounds() external view returns (uint256) {
        return vestingRounds.length;
    }
}
