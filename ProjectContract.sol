// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts@4.7.3/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./AlignerNFT.sol";

contract ProjectContract {
    IERC20 public IWO;
    AlignerNFT public NFTContract;
    // AlignerNFT public nftContract;
    address owner;

    struct Project {
        address owner;
        string projectName;
        string projectDescription;
        string socialInfo;
        uint256 biddingStartDate;
        uint256 biddingEndDate;
        bool biddingActive;
        mapping(address => Bid) bids;
        address[] bidderAddresses;
        uint256 bidCounter;
        VestingRound[] vestingRounds;
        address referralAddress;
        mapping(address => bool) whitelist; // Mapping to store whitelist status for each project
    }

    struct VestingRound {
        uint256 roundAmount;
        uint256 bidsAmount;
        bool completed;
        uint256 iwoPrice;
    }

    struct Bid {
        uint256 allocationSize;
        uint256 vestingLength;
        uint256 allocationIWOSize;
        uint256 timestamp;
        uint256 lockedIWOSize;
        bool locked;
        address bidder;
    }

    mapping(uint256 => Project) public projects;
    uint256 public projectCounter;

    event VestingRoundAdded(
        uint256 projectId,
        uint256 roundIndex,
        uint256 roundAmount,
        uint256 iwoPrice
    );
    event BiddingEnded(uint256 projectId);
    event BidPlaced(
        uint256 projectId,
        uint256 allocationSize,
        uint256 vestingLength,
        uint256 timestamp
    );
    event Withdrawal(
        uint256 projectId,
        address indexed bidder,
        uint256 vestedAmount,
        uint256 timestamp
    );

    modifier onlyProjectOwner(uint256 projectId) {
        require(
            msg.sender == projects[projectId].owner,
            "Only the owner can call this function"
        );
        _;
    }

    modifier onlyProjectOwnerOrReferral(uint256 projectId) {
        require(
            msg.sender == projects[projectId].referralAddress ||
                msg.sender == projects[projectId].owner,
            "Only referral address or owner can call this function"
        );
        _;
    }

    modifier onlyDuringBidding(uint256 projectId) {
        require(
            projects[projectId].biddingActive &&
                block.timestamp >= projects[projectId].biddingStartDate &&
                block.timestamp <= projects[projectId].biddingEndDate,
            "Bidding is not active or has ended"
        );
        _;
    }

    modifier biddingEnded(uint256 projectId) {
        require(
            !projects[projectId].biddingActive ||
                !(block.timestamp >= projects[projectId].biddingStartDate &&
                    block.timestamp <= projects[projectId].biddingEndDate),
            "Bidding is active"
        );
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    // Modifier to check if the sender is whitelisted for the specific project
    modifier onlyWhitelisted(uint256 projectId) {
        require(
            projects[projectId].whitelist[msg.sender],
            "Address not whitelisted for this project"
        );
        _;
    }

    modifier onlyNFTHolder() {
        require(
            NFTContract.balanceOf(msg.sender) > 0,
            "Only NFT holders of this project can perform this action"
        );
        _;
    }

    constructor(address _token, address nftAddress) {
        IWO = IERC20(_token);
        owner = msg.sender;
        NFTContract = AlignerNFT(nftAddress);
    }

    function createProject(
        string memory _projectName,
        string memory _projectDescription,
        string memory _socialInfo,
        uint256 _biddingStartDate,
        uint256 _biddingDuration
    ) public onlyOwner returns (uint256) {
        projectCounter++;
        uint256 projectId = projectCounter;
        Project storage project = projects[projectId];
        project.owner = msg.sender;
        project.projectName = _projectName;
        project.projectDescription = _projectDescription;
        project.socialInfo = _socialInfo;
        project.biddingStartDate = _biddingStartDate;
        project.biddingEndDate = _biddingStartDate + _biddingDuration;
        project.biddingActive = true;
        project.referralAddress = address(0); // No referral address initially
        return projectId;
    }

    function placeBid(
        uint256 projectId,
        uint256 _allocationSize,
        uint256 _vestingLength
    ) public payable onlyDuringBidding(projectId) onlyWhitelisted(projectId) {
        Project storage project = projects[projectId];
        require(msg.value > 0, "Bid amount must be greater than 0");
        require(msg.value >= _allocationSize, "Incorrect bid amount sent");
        require(
            _allocationSize > 0 && _allocationSize % 100 == 0,
            "Bid amount must be greater than 0 and multiple of 100 USDT"
        );
        require(
            _vestingLength > 0 && _vestingLength % 3 == 0,
            "Vesting lengths must be greater than 0 and multiple of 3 months"
        );

        if (project.bids[msg.sender].timestamp == 0) {
            project.bidCounter++;
            project.bidderAddresses.push(msg.sender);
            Bid memory b = Bid({
                allocationSize: _allocationSize,
                vestingLength: _vestingLength,
                allocationIWOSize: 0,
                timestamp: block.timestamp,
                lockedIWOSize: 0,
                locked: false,
                bidder: msg.sender
            });
            project.bids[msg.sender] = b;
        } else {
            project.bids[msg.sender].allocationSize += _allocationSize;
            project.bids[msg.sender].vestingLength += _vestingLength;
            project.bids[msg.sender].timestamp = block.timestamp;
        }

        emit BidPlaced(
            projectId,
            _allocationSize,
            _vestingLength,
            block.timestamp
        );
    }

    function endBidding(uint256 projectId)
        external
        payable
        onlyProjectOwnerOrReferral(projectId)
    {
        Project storage project = projects[projectId];
        require(project.biddingActive, "Bidding has already ended");
        project.biddingActive = false;
        project.biddingEndDate = block.timestamp;
        emit BiddingEnded(projectId);

        // Sort bids based on allocation size in descending order
        address[] memory bidders = new address[](project.bidCounter);
        uint256[] memory allocationSizes = new uint256[](project.bidCounter);

        // Populate arrays with bidder addresses and their allocation sizes
        for (uint256 i = 0; i < project.bidCounter; i++) {
            address bidderAddress = project.bidderAddresses[i];
            bidders[i] = bidderAddress;
            allocationSizes[i] = project.bids[bidderAddress].allocationSize;
        }

        // Use a sorting function to sort in descending order
        selectionSort(bidders, allocationSizes, project.bidCounter);

        // Calculate IWO tokens for each bidder and deduct from vesting rounds
        for (uint256 i = 0; i < project.bidCounter; i++) {
            address bidder = bidders[i];
            uint256 allocationSizeUSDT = project.bids[bidder].allocationSize;

            // Iterate through vesting rounds
            for (uint256 j = 0; j < project.vestingRounds.length; j++) {
                VestingRound storage round = project.vestingRounds[j];
                uint256 allocationIWO = allocationSizeUSDT / round.iwoPrice;
                // Store the original round amount
                uint256 leftRoundAmount = round.roundAmount - round.bidsAmount;

                // Calculate tokens to deduct from this round
                uint256 tokensToDeduct = allocationIWO < leftRoundAmount
                    ? allocationIWO
                    : leftRoundAmount;

                // Add tokens to the round and bidder
                round.bidsAmount += tokensToDeduct;
                project.bids[bidder].allocationIWOSize += tokensToDeduct;

                // Update the bidder's allocation
                allocationIWO -= tokensToDeduct;
                allocationSizeUSDT -= tokensToDeduct * round.iwoPrice;

                // Check if the round is completed
                if (round.roundAmount - round.bidsAmount <= 0)
                    round.completed = true;

                // Check if the bidder's allocation is fully processed
                if (allocationSizeUSDT <= 0) break;
            }

            // Transfer IWO tokens to the contract
            uint256 vestedAmount = project.bids[bidder].allocationIWOSize;
            require(
                IWO.transferFrom(project.owner, address(this), vestedAmount),
                "Token transfer failed"
            );
        }
        mintNFT(projectId);
    }

    function selectionSort(
        address[] memory bidders,
        uint256[] memory allocationSizes,
        uint256 n
    ) internal pure {
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

    function mintNFT(uint256 projectId) internal {
        // Mint NFT to successful bidders
        address[] memory bidders = projects[projectId].bidderAddresses;
        for (uint256 i = 0; i < bidders.length; i++) {
            address bidder = bidders[i];
            if (projects[projectId].bids[bidder].allocationIWOSize > 0) {
                NFTContract.safeMint(bidder);
            }
        }
    }

    function addVestingRound(
        uint256 projectId,
        uint256 _roundAmount,
        uint256 _iwoPrice
    )
        external
        onlyProjectOwnerOrReferral(projectId)
        onlyDuringBidding(projectId)
    {
        Project storage project = projects[projectId];
        uint256 roundIndex = project.vestingRounds.length;
        project.vestingRounds.push(
            VestingRound(_roundAmount, 0, false, _iwoPrice)
        );
        emit VestingRoundAdded(projectId, roundIndex, _roundAmount, _iwoPrice);
    }

    function setReferralAddress(uint256 projectId, address _referralAddress)
        external
        onlyProjectOwner(projectId)
    {
        projects[projectId].referralAddress = _referralAddress;
    }

    function getNumberOfVestingRounds(uint256 projectId)
        external
        view
        returns (uint256)
    {
        return projects[projectId].vestingRounds.length;
    }

    function getBidderAddresses(uint256 projectId)
        external
        view
        returns (address[] memory)
    {
        return projects[projectId].bidderAddresses;
    }

    function getBidDetails(uint256 projectId, address bidder)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool
        )
    {
        Bid memory bid = projects[projectId].bids[bidder];
        return (
            bid.allocationSize,
            bid.vestingLength,
            bid.allocationIWOSize,
            bid.timestamp,
            bid.lockedIWOSize,
            bid.locked
        );
    }

    function getProjectDetails(uint256 projectId)
        external
        view
        returns (
            address,
            string memory,
            string memory,
            string memory,
            uint256,
            uint256,
            bool,
            address
        )
    {
        Project storage project = projects[projectId];
        return (
            project.owner,
            project.projectName,
            project.projectDescription,
            project.socialInfo,
            project.biddingStartDate,
            project.biddingEndDate,
            project.biddingActive,
            project.referralAddress
        );
    }

    // Function to be able to receive ETH
    receive() external payable {}

    struct ProjectData {
        address owner;
        string projectName;
        string projectDescription;
        string socialInfo;
        uint256 biddingStartDate;
        uint256 biddingEndDate;
        bool biddingActive;
        uint256 bidCounter;
        address referralAddress;
        VestingRound[] vestingRounds;
        Bid[] bids;
    }

    function getAllProjects() external view returns (ProjectData[] memory) {
        ProjectData[] memory allProjects = new ProjectData[](projectCounter);
        for (uint256 i = 1; i <= projectCounter; i++) {
            Project storage project = projects[i];
            allProjects[i - 1] = ProjectData({
                owner: project.owner,
                projectName: project.projectName,
                projectDescription: project.projectDescription,
                socialInfo: project.socialInfo,
                biddingStartDate: project.biddingStartDate,
                biddingEndDate: project.biddingEndDate,
                biddingActive: project.biddingActive,
                bidCounter: project.bidCounter,
                referralAddress: project.referralAddress,
                vestingRounds: project.vestingRounds,
                bids: getBidsArray(project.bidderAddresses, project)
            });
        }
        return allProjects;
    }

    function getBidsArray(address[] memory bidders, Project storage project)
        internal
        view
        returns (Bid[] memory)
    {
        Bid[] memory allBids = new Bid[](bidders.length);
        for (uint256 i = 0; i < bidders.length; i++) {
            allBids[i] = project.bids[bidders[i]];
        }
        return allBids;
    }

    struct ClaimingDetails {
        uint256 allocationSize; // Allocation size for the bid
        uint256 balance; // Balance available for claiming
        uint256 date; // Current date
        bool claimAllowed; // Whether claiming is allowed for this month
    }

    uint256 public period = 2 minutes; // One month in seconds

    function calculateVestedAmount(
        uint256 projectId,
        address bidder,
        uint256 month
    ) internal view returns (uint256) {
        Project storage project = projects[projectId];
        Bid storage bid = project.bids[bidder];

        // Ensure the bid exists
        require(bid.timestamp > 0, "Bid not found");

        // Calculate the monthly vesting amount
        uint256 monthlyVestingAmount = bid.allocationIWOSize /
            bid.vestingLength;

        // Calculate the vested amount for the specified month
        uint256 vestedAmount = monthlyVestingAmount * month;

        // Ensure vested amount does not exceed the total allocation
        if (vestedAmount > bid.allocationIWOSize) {
            vestedAmount = bid.allocationIWOSize;
        }

        // Subtract any previously locked amount
        // vestedAmount -= bid.lockedIWOSize;

        return vestedAmount;
    }

    function getClaimingDetails(uint256 projectId, address bidder)
        public
        view
        biddingEnded(projectId)
        returns (ClaimingDetails[] memory)
    {
        Project storage project = projects[projectId];
        Bid storage bid = project.bids[bidder];

        uint256 claimingPeriods = bid.vestingLength;
        ClaimingDetails[] memory claimingDetails = new ClaimingDetails[](
            claimingPeriods
        );

        uint256 claimedAmount = 0;
        uint256 vestedAmount = 0;
        uint256 currentPeriod = block.timestamp;

        for (uint256 i = 0; i < claimingPeriods; i++) {
            vestedAmount = calculateVestedAmount(projectId, bidder, i + 1);

            uint256 balance = vestedAmount - claimedAmount;
            claimedAmount = vestedAmount;

            // Check if claiming is allowed for this month
            bool claimAllowed = balance > 0 &&
                currentPeriod >= project.biddingEndDate + ((i + 1) * period);

            claimingDetails[i] = ClaimingDetails({
                allocationSize: bid.allocationIWOSize,
                balance: balance,
                date: project.biddingEndDate + ((i + 1) * period),
                claimAllowed: claimAllowed
            });
        }

        return claimingDetails;
    }

    function withdraw(uint256 projectId)
        external
        biddingEnded(projectId)
        onlyNFTHolder
    {
        Project storage project = projects[projectId];
        Bid storage bid = project.bids[msg.sender];
        require(!project.biddingActive, "Bidding must be ended to withdraw");
        require(bid.timestamp > 0, "No bid found for the sender");
        uint256 currentMonth = (block.timestamp - project.biddingEndDate) /
            period;
        require(currentMonth > 0, "No vested amount to withdraw yet");

        uint256 vestedAmount = calculateVestedAmount(
            projectId,
            msg.sender,
            currentMonth
        );

        // Check if the user has any new vested amount to withdraw
        require(
            vestedAmount > 0 && vestedAmount > bid.lockedIWOSize,
            "No new vested amount to withdraw"
        );

        require(
            IWO.transfer(msg.sender, vestedAmount - bid.lockedIWOSize),
            "Token transfer failed during withdrawal"
        );

        bid.lockedIWOSize = vestedAmount;
        if (bid.lockedIWOSize >= bid.allocationIWOSize) {
            project.bids[msg.sender].locked = true;
        }

        emit Withdrawal(projectId, msg.sender, vestedAmount, block.timestamp);
    }

    // Function to add an address to the whitelist for a specific project
    function addToWhitelist(uint256 projectId, address _address)
        public
        onlyOwner
    {
        projects[projectId].whitelist[_address] = true;
    }

    // Function to remove an address from the whitelist for a specific project
    function removeFromWhitelist(uint256 projectId, address _address)
        public
        onlyOwner
    {
        projects[projectId].whitelist[_address] = false;
    }
}
