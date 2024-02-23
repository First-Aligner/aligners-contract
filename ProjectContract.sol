// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts@4.7.3/token/ERC20/IERC20.sol";

// Or VestingContract
contract ProjectContract {
    IERC20 public IVO;
    address public owner;
    string public projectName;
    string public projectDescription;
    string public socialInfo;
    uint256 public biddingStartDate;
    uint256 public biddingEndDate; // Added variable to store the bidding end date
    bool public biddingActive; // Added variable to track bidding status
    VestingRound[] public vestingRounds;
    // Add a variable to track the current round

    struct VestingRound {
        uint256 roundAmount; // Round vesting amount (default 100 000 IVO)
        uint256 bidsAmount; // Amount of bids placed in this round
        bool completed; // Flag to track if the round is completed
        uint256 ivoPrice; // IVO price in USDT
    }

    struct Bid {
        uint256 allocationSize;
        uint256 vestingLength;
        uint256 allocationIVOSize;
        uint256 timestamp; // Include the current UTC timestamp
    }

    mapping(address => Bid) public bids;
    address[] public bidderAddresses;
    uint256 public bidCounter = 0;

    // Events to log important activities
    event VestingRoundAdded(
        uint256 roundIndex,
        uint256 roundAmount,
        uint256 ivoPrice
    );
    event BiddingEnded(); // Added event to log the end of bidding
    event BidPlaced(
        uint256 allocationSize,
        uint256 vestingLength,
        uint256 timestamp
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
        IVO = IERC20(_token);
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
    {
        // Ensure that the bid amount is greater than 0
        require(msg.value > 0, "Bid amount must be greater than 0");
        require(msg.value == _allocationSize, "Incorrect bid amount sent");
        // Ensure the _allocationSize divided by 100 in USDT
        require(
            _allocationSize > 0 && _allocationSize % 100 == 0,
            "Bid amount must be greater than 0 and multiple of 100 USDT"
        );
        // Ensure the _vestingLength divided by 3
        require(
            _vestingLength > 0 && _vestingLength % 3 == 0,
            "Vesting lengths must be greater than 0 and multiple of 3 months"
        );

        // Check if the bidder has an existing bid
        if (bids[msg.sender].timestamp == 0) {
            // If no existing bid, create a new bid record
            bids[msg.sender] = Bid({
                allocationSize: _allocationSize,
                vestingLength: _vestingLength,
                allocationIVOSize: 0,
                timestamp: block.timestamp
            });
            // Increment the bid counter to get a unique bid ID
            bidCounter++;
            bidderAddresses.push(msg.sender);
        } else {
            // If an existing bid is found, update the existing bid record
            bids[msg.sender].allocationSize += _allocationSize;
            bids[msg.sender].vestingLength += _vestingLength;
            bids[msg.sender].timestamp = block.timestamp;
        }

        // Emit an event to log the bid placement
        // You can customize the event parameters based on your contract requirements
        emit BidPlaced(_allocationSize, _vestingLength, block.timestamp);
    }

    // Function to add a vesting round
    function endBidding() external onlyOwner {
        require(biddingActive, "Bidding has already ended");
        biddingActive = false;
        emit BiddingEnded();

        // Sort bids based on allocation size in descending order
        address[] memory bidders = new address[](bidCounter);
        uint256[] memory allocationSizes = new uint256[](bidCounter);

        // Populate arrays with bidder addresses and their allocation sizes
        for (uint256 i = 0; i < bidCounter; i++) {
            // for (address bidderAddress : bids) {
            address bidderAddress = bidderAddresses[i];
            bidders[i] = bidderAddress;
            allocationSizes[i] = bids[bidderAddress].allocationSize;
        }

        // Use a sorting function to sort in descending order
        selectionSort(bidders, allocationSizes);

        // Calculate IVO tokens for each bidder and deduct from vesting rounds
        for (uint256 i = 0; i < bidCounter; i++) {
            address bidder = bidders[i];
            uint256 allocationSizeUSDT = bids[bidder].allocationSize;

            // Iterate through vesting rounds
            for (uint256 j = 0; j < vestingRounds.length; j++) {
                VestingRound storage round = vestingRounds[j];
                uint256 allocationIVO = allocationSizeUSDT / round.ivoPrice;
                // Store the original round amount
                uint256 leftRoundAmount = round.roundAmount - round.bidsAmount;

                // Calculate tokens to deduct from this round
                uint256 tokensToDeduct = allocationIVO < leftRoundAmount
                    ? allocationIVO
                    : leftRoundAmount;

                // Add tokens to the round and bidder
                round.bidsAmount += tokensToDeduct;
                bids[bidder].allocationIVOSize += tokensToDeduct;

                // Update the bidder's allocation
                allocationIVO -= tokensToDeduct;
                allocationSizeUSDT -= tokensToDeduct * round.ivoPrice;

                // Check if the round is completed
                if (round.roundAmount - round.bidsAmount <= 0)
                    round.completed = true;

                // Check if the bidder's allocation is fully processed
                if (allocationSizeUSDT <= 0) break;
            }

            // Transfer IVO tokens to the contract
            uint256 vestedAmount = bids[bidder].allocationIVOSize;
            require(
                IVO.transferFrom(owner, address(this), vestedAmount),
                "Token transfer failed"
            );
            // TODO: create withdrow function to collect the tokens depend on the vesting schedule
        }
    }

    function selectionSort(
        address[] memory bidders,
        uint256[] memory allocationSizes
    ) internal pure {
        uint256 n = bidders.length;
        for (uint256 i = 0; i < n - 1; i++) {
            uint256 maxIndex = i;
            // Find the index of the maximum element in the unsorted part
            for (uint256 j = i + 1; j < n; j++)
                if (allocationSizes[j] > allocationSizes[maxIndex])
                    maxIndex = j;

            // Swap the found maximum element with the first element
            (bidders[i], bidders[maxIndex]) = (bidders[maxIndex], bidders[i]);
            (allocationSizes[i], allocationSizes[maxIndex]) = (
                allocationSizes[maxIndex],
                allocationSizes[i]
            );
        }
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
