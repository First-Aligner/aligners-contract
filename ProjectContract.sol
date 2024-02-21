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
    // Add a variable to track the current round
    uint256 public currentRound = 0;

    struct VestingRound {
        uint256 roundAmount; // Round vesting amount (default 100 000 IVO)
        uint256 bidsCount; // Number of bids placed in this round
        bool completed; // Flag to track if the round is completed
        uint256 ivoPrice; // IVO price in USDT
    }
    struct Bid {
        address bidder;
        uint256 allocationSize;
        uint256 vestingLength;
        uint256 ivoPrice;
        uint256 timestamp; // Include the current UTC timestamp
        uint256 roundIndex; // Added round index to track the round of the bid
    }

    mapping(uint256 => Bid) public bids;
    uint256 public bidCounter = 0;

    // Events to log important activities
    event VestingRoundAdded(
        uint256 roundIndex,
        uint256 roundAmount,
        uint256 ivoPrice
    );
    event BiddingEnded(); // Added event to log the end of bidding
    event BidPlaced(
        address bidder,
        uint256 allocationSize,
        uint256 vestingLength,
        uint256 ivoPrice,
        uint256 timestamp,
        uint256 roundIndex
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

    modifier visitingRoundsNotCompleted() {
        VestingRound storage round = vestingRounds[vestingRounds.length - 1];
        require(
            currentRound >= 0 &&
                (round.completed || round.bidsCount >= round.roundAmount),
            "All visiting rounds completed"
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

    function placeBid(uint256 _allocationSize, uint256 _vestingLength)
        public
        payable
        onlyDuringBidding
        visitingRoundsNotCompleted
    {
        // Ensure that the bid amount is greater than 0
        require(msg.value > 0, "Bid amount must be greater than 0");
        require(msg.value == _allocationSize, "Incorrect bid amount sent");
        // Ensure the _allocationSize divided by 100
        require(
            _allocationSize > 0 && _allocationSize % 100 == 0,
            "Bid amount must be greater than 0 and multiple of 100 USDT"
        ); 
        // Ensure the _vestingLength divided by 3
        require(
            _vestingLength > 0 && _vestingLength % 3 == 0,
            "Vesting lengths must be greater than 0 and multiple of 3 months"
        );

        VestingRound storage round = vestingRounds[currentRound];
        // TODO: add the bid to the current VestingRound and if the amount more than current VestingRound split it to complete this round and the rest add it in the next VestingRound and if this last round return the rest mony to bidder
        if (round.completed || round.bidsCount >= round.roundAmount) {
            currentRound++;
            require(
                vestingRounds.length > currentRound,
                "No enough round to complete the bid"
            );
            round = vestingRounds[currentRound];
        }

        // Transfer the bid amount in tokens from the bidder to the contract
        require(
            token.transferFrom(msg.sender, address(this), _allocationSize),
            "Failed to transfer tokens"
        );

        uint256 bidAmount = msg.value;
        if (round.bidsCount + _allocationSize > round.roundAmount) {
            uint256 restRoundAmount = round.roundAmount - round.bidsCount;
            uint256 excessAmount = bidAmount - restRoundAmount;
            // Transfer the excess Ether back to the bidder
            if (excessAmount > 0) payable(msg.sender).transfer(excessAmount);
            bidAmount = restRoundAmount;
        }
        // Store bid information in the mapping
        bids[bidCounter] = Bid({
            bidder: msg.sender,
            allocationSize: bidAmount,
            vestingLength: _vestingLength,
            ivoPrice: round.ivoPrice,
            timestamp: block.timestamp,
            roundIndex: currentRound
        });
        // Increment the bid counter to get a unique bid ID
        bidCounter++;

        // Emit an event to log the bid placement
        // You can customize the event parameters based on your contract requirements
        emit BidPlaced(
            msg.sender,
            _allocationSize,
            _vestingLength,
            round.ivoPrice,
            block.timestamp,
            currentRound
        );

        // Update the current round's bids count
        round.bidsCount += bidAmount;
        if (round.bidsCount >= round.roundAmount) {
            round.completed = true;
            currentRound++;
        }
    }

    // Function to get the current IVO price based on the latest vesting round
    function getCurrentIvoPrice() public view returns (uint256) {
        require(vestingRounds.length > 0, "No vesting rounds available");
        require(
            vestingRounds.length > currentRound,
            "No vesting rounds available"
        );
        return vestingRounds[currentRound].ivoPrice;
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
        vestingRounds.push(VestingRound(_roundAmount, 0, false, _ivoPrice));

        // Emit an event to log the addition of a vesting round
        emit VestingRoundAdded(roundIndex, _roundAmount, _ivoPrice);
    }

    // Function to get the total number of vesting rounds
    function getNumberOfVestingRounds() external view returns (uint256) {
        return vestingRounds.length;
    }
}
