// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./AlignerNFT.sol";

contract ProjectContract is ReentrancyGuard {
    // Global variables
    IERC20 public IWO;
    IERC20 public USDT;
    AlignerNFT public NFTContract;
    address public owner;
    address public operatorAddress; // Operator address that can act as owner
    mapping(uint256 => Project) public projects;
    uint256 public projectCounter;
    mapping(address => address) public referrals; // Mapping to store who referred whom
    mapping(address => address[]) public referralsByUser; // Mapping to store referrals made by each user
    // State variable for pause functionality
    bool public paused;
    uint256 public period = 5 minutes;
    uint256 public FixedPoint = 10**6;

    // Structs
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
        address operatorAddress;
        mapping(address => bool) whitelist;
    }
    struct VestingRound {
        uint256 roundAmount;
        uint256 bidsAmount;
        bool completed;
        uint256 iwoPrice;
    }
    struct Bid {
        uint256 allocationSize; // USDT
        uint256 allocatedUSDT; // USDT allocated for IWO tokens
        uint256 refundableUSDT; // USDT to be refunded
        uint256 allocationIWOSize; // IWO
        uint256 vestingLength;
        uint256 timestamp;
        uint256 lockedIWOSize;
        bool locked;
        address bidder;
        uint256 nftTokenId;
    }
    struct ProjectData {
        address owner;
        string projectName;
        string projectDescription;
        string socialInfo;
        uint256 biddingStartDate;
        uint256 biddingEndDate;
        bool biddingActive;
        uint256 bidCounter;
        address operatorAddress;
        VestingRound[] vestingRounds;
        Bid[] bids;
    }
    struct ClaimingDetails {
        uint256 allocationSize;
        uint256 balance;
        uint256 date;
        bool claimAllowed;
        bool withdrawn;
    }

    // Events
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
    event ReferralRecorded(address indexed referrer, address indexed referee);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }
    modifier onlyOwnerOrOperator() {
        require(
            msg.sender == owner || msg.sender == operatorAddress,
            "Not owner or operator"
        );
        _;
    }
    modifier onlyProjectOwner(uint256 projectId) {
        require(
            msg.sender == projects[projectId].owner,
            "Only the owner can call this function"
        );
        _;
    }
    modifier onlyProjectOwnerOrOperator(uint256 projectId) {
        require(
            msg.sender == projects[projectId].operatorAddress ||
                msg.sender == projects[projectId].owner,
            "Only operator address or owner can call this function"
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
                block.timestamp > projects[projectId].biddingEndDate,
            "Bidding is active"
        );
        _;
    }
    modifier onlyWhitelisted(uint256 projectId) {
        require(
            projects[projectId].whitelist[msg.sender],
            "Address not whitelisted for this project"
        );
        _;
    }
    modifier onlyNFTHolder(uint256 tokenId) {
        require(
            NFTContract.ownerOf(tokenId) == msg.sender,
            "Only the current NFT holder can perform this action"
        );
        _;
    }
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }
    modifier whenPaused() {
        require(paused, "Contract is not paused");
        _;
    }

    constructor(
        address _token,
        address nftAddress,
        address _usdtAddress,
        address _operatorAddress
    ) {
        IWO = IERC20(_token);
        owner = msg.sender;
        NFTContract = AlignerNFT(nftAddress);
        USDT = IERC20(_usdtAddress);
        operatorAddress = _operatorAddress;
    }

    // Functions
    function createProject(
        string memory _projectName,
        string memory _projectDescription,
        string memory _socialInfo,
        uint256 _biddingStartDate,
        uint256 _biddingDuration
    ) public onlyOwnerOrOperator returns (uint256) {
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
        project.operatorAddress = address(0);
        return projectId;
    }

    function placeBid(
        uint256 projectId,
        uint256 _allocationSize,
        uint256 _vestingLength
    )
        public
        payable
        onlyDuringBidding(projectId)
        onlyWhitelisted(projectId)
        whenNotPaused
    {
        Project storage project = projects[projectId];
        require(_allocationSize >= 0, "Bid amount must be greater than 0");
        require(
            _allocationSize % 100 == 0,
            "Bid amount must be a multiple of 100 USDT"
        );
        require(
            _vestingLength >= 0 && _vestingLength % 1 == 0,
            "Vesting lengths must be a multiple of 1 months"
        );

        uint256 allowed = USDT.allowance(msg.sender, address(this));
        require(
            allowed >= _allocationSize * (10**18),
            "Check the token allowance"
        );

        require(
            USDT.transferFrom(
                msg.sender,
                address(this),
                _allocationSize * (10**18)
            ),
            "Failed to transfer USDT"
        );

        if (project.bids[msg.sender].timestamp == 0) {
            project.bidCounter++;
            project.bidderAddresses.push(msg.sender);
            Bid memory b = Bid({
                allocationSize: _allocationSize,
                allocatedUSDT: 0,
                refundableUSDT: 0,
                vestingLength: _vestingLength,
                allocationIWOSize: 0,
                timestamp: block.timestamp,
                lockedIWOSize: 0,
                locked: false,
                bidder: msg.sender,
                nftTokenId: 0
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
        onlyProjectOwnerOrOperator(projectId)
        whenNotPaused
    {
        Project storage project = projects[projectId];
        require(project.biddingActive, "Bidding has already ended");
        project.biddingActive = false;
        project.biddingEndDate = block.timestamp;
        emit BiddingEnded(projectId);

        // Sort bids based on allocation size in descending order
        address[] memory bidders = new address[](project.bidCounter);
        uint256[] memory vestingLengthArray = new uint256[](project.bidCounter);

        for (uint256 i = 0; i < project.bidCounter; i++) {
            address bidderAddress = project.bidderAddresses[i];
            bidders[i] = bidderAddress;
            vestingLengthArray[i] = project.bids[bidderAddress].vestingLength;
        }

        selectionSort(bidders, vestingLengthArray, project.bidCounter);

        for (uint256 i = 0; i < project.bidCounter; i++) {
            address bidder = bidders[i];
            uint256 allocationSizeUSDT = project.bids[bidder].allocationSize;

            for (uint256 j = 0; j < project.vestingRounds.length; j++) {
                VestingRound storage round = project.vestingRounds[j];
                uint256 allocationIWO = (allocationSizeUSDT * FixedPoint) /
                    round.iwoPrice;
                uint256 leftRoundAmount = round.roundAmount - round.bidsAmount;
                uint256 tokensToDeduct = allocationIWO < leftRoundAmount
                    ? allocationIWO
                    : leftRoundAmount;

                round.bidsAmount += tokensToDeduct;
                project.bids[bidder].allocationIWOSize += tokensToDeduct;

                uint256 usdtUsed = (tokensToDeduct * round.iwoPrice) /
                    FixedPoint;
                allocationSizeUSDT -= usdtUsed;
                project.bids[bidder].allocatedUSDT += usdtUsed;

                if (round.roundAmount - round.bidsAmount <= 0)
                    round.completed = true;
                if (allocationSizeUSDT <= 0) break;
            }

            uint256 vestedAmount = project.bids[bidder].allocationIWOSize;
            uint256 refundableUSDT = project.bids[bidder].allocationSize -
                project.bids[bidder].allocatedUSDT;
            project.bids[bidder].refundableUSDT = refundableUSDT;
            // Refund remaining USDT if not enough IWO tokens available
            if (refundableUSDT > 0) {
                require(
                    USDT.transfer(bidder, refundableUSDT * (10**18)),
                    "USDT refund transfer failed"
                );
            }
            // If vested amount is greater than zero, transfer IWO tokens to the contract
            if (vestedAmount > 0) {
                require(
                    IWO.transferFrom(
                        project.owner,
                        address(this),
                        vestedAmount * (10**18)
                    ),
                    "Token transfer failed"
                );
            }
        }
        mintNFT(projectId);
    }

    function selectionSort(
        address[] memory bidders,
        uint256[] memory arr,
        uint256 n
    ) internal pure {
        for (uint256 i = 0; i < n - 1; i++) {
            uint256 maxIndex = i;
            for (uint256 j = i + 1; j < n; j++)
                if (arr[j] > arr[maxIndex]) maxIndex = j;

            (bidders[i], bidders[maxIndex]) = (bidders[maxIndex], bidders[i]);
            (arr[i], arr[maxIndex]) = (arr[maxIndex], arr[i]);
        }
    }

    function mintNFT(uint256 projectId) internal {
        address[] memory bidders = projects[projectId].bidderAddresses;
        for (uint256 i = 0; i < bidders.length; i++) {
            address bidder = bidders[i];
            if (projects[projectId].bids[bidder].allocationIWOSize > 0) {
                uint256 tokenId = NFTContract.safeMint(bidder);
                projects[projectId].bids[bidder].nftTokenId = tokenId;
            }
        }
    }

    function addVestingRound(
        uint256 projectId,
        uint256 _roundAmount,
        uint256 _iwoPrice
    )
        external
        onlyProjectOwnerOrOperator(projectId)
        onlyDuringBidding(projectId)
    {
        Project storage project = projects[projectId];
        uint256 roundIndex = project.vestingRounds.length;
        project.vestingRounds.push(
            VestingRound(_roundAmount, 0, false, _iwoPrice)
        );
        emit VestingRoundAdded(projectId, roundIndex, _roundAmount, _iwoPrice);
    }

    function setOperatorAddress(uint256 projectId, address _operatorAddress)
        external
        onlyProjectOwner(projectId)
    {
        projects[projectId].operatorAddress = _operatorAddress;
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
            uint256,
            uint256,
            bool,
            uint256
        )
    {
        Bid memory bid = projects[projectId].bids[bidder];
        return (
            bid.allocationSize,
            bid.allocatedUSDT,
            bid.refundableUSDT,
            bid.vestingLength,
            bid.allocationIWOSize,
            bid.timestamp,
            bid.lockedIWOSize,
            bid.locked,
            bid.nftTokenId
        );
    }

    function getBidDetailsByTokenId(uint256 projectId, uint256 tokenId)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool,
            uint256,
            address
        )
    {
        Project storage project = projects[projectId];
        address bidder = address(0);
        bool bidFound = false;

        // Find the bid that matches the given tokenId
        for (uint256 i = 0; i < project.bidderAddresses.length; i++) {
            address bidderAddress = project.bidderAddresses[i];
            if (project.bids[bidderAddress].nftTokenId == tokenId) {
                bidder = bidderAddress;
                bidFound = true;
                break;
            }
        }

        require(bidFound, "No bid found for the given token ID");
        Bid memory bid = project.bids[bidder];

        return (
            bid.allocationSize,
            bid.allocatedUSDT,
            bid.refundableUSDT,
            bid.vestingLength,
            bid.allocationIWOSize,
            bid.timestamp,
            bid.lockedIWOSize,
            bid.locked,
            bid.nftTokenId,
            bid.bidder
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
            project.operatorAddress
        );
    }

    function getProjectFullDetails(uint256 projectId)
        external
        view
        returns (ProjectData memory)
    {
        Project storage project = projects[projectId];

        // Create and return the ProjectData struct
        ProjectData memory projectData = ProjectData({
            owner: project.owner,
            projectName: project.projectName,
            projectDescription: project.projectDescription,
            socialInfo: project.socialInfo,
            biddingStartDate: project.biddingStartDate,
            biddingEndDate: project.biddingEndDate,
            biddingActive: project.biddingActive,
            bidCounter: project.bidCounter,
            operatorAddress: project.operatorAddress,
            vestingRounds: project.vestingRounds,
            bids: getBidsArray(project.bidderAddresses, project)
        });

        return projectData;
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
                operatorAddress: project.operatorAddress,
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

    function calculateVestedAmount(
        uint256 projectId,
        address bidder,
        uint256 month
    ) internal view returns (uint256) {
        Project storage project = projects[projectId];
        Bid storage bid = project.bids[bidder];

        require(bid.timestamp > 0, "Bid not found");

        if (bid.vestingLength == 0) return bid.allocationIWOSize;

        uint256 totalAllocation = bid.allocationIWOSize;
        uint256 monthlyVestingAmount = totalAllocation / bid.vestingLength;

        // Calculate the vested amount up to the given month
        uint256 vestedAmount = monthlyVestingAmount * month;

        // If it's the last month, add any remaining tokens to the vested amount
        if (month >= bid.vestingLength) {
            uint256 remainder = totalAllocation % bid.vestingLength;
            vestedAmount += remainder;
        }

        // Ensure vestedAmount does not exceed the total allocation
        if (vestedAmount > totalAllocation) {
            vestedAmount = totalAllocation;
        }

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

            bool claimAllowed = balance > 0 &&
                currentPeriod >= project.biddingEndDate + (i * period);
            bool withdrawn = bid.lockedIWOSize >= claimedAmount;

            claimingDetails[i] = ClaimingDetails({
                allocationSize: bid.allocationIWOSize,
                balance: balance,
                date: project.biddingEndDate + (i * period),
                claimAllowed: claimAllowed,
                withdrawn: withdrawn
            });
        }

        return claimingDetails;
    }

    function getClaimingDetailsByTokenId(uint256 projectId, uint256 tokenId)
        public
        view
        biddingEnded(projectId)
        returns (ClaimingDetails[] memory)
    {
        Project storage project = projects[projectId];
        address bidder = address(0);
        bool bidFound = false;

        // Find the bid that matches the given tokenId
        for (uint256 i = 0; i < project.bidderAddresses.length; i++) {
            address bidderAddress = project.bidderAddresses[i];
            if (project.bids[bidderAddress].nftTokenId == tokenId) {
                bidder = bidderAddress;
                bidFound = true;
                break;
            }
        }

        require(bidFound, "No bid found for the given token ID");
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

            bool claimAllowed = balance > 0 &&
                currentPeriod >= project.biddingEndDate + (i * period);
            bool withdrawn = bid.lockedIWOSize >= claimedAmount;

            claimingDetails[i] = ClaimingDetails({
                allocationSize: bid.allocationIWOSize,
                balance: balance,
                date: project.biddingEndDate + (i * period),
                claimAllowed: claimAllowed,
                withdrawn: withdrawn
            });
        }

        return claimingDetails;
    }

    function withdraw(uint256 projectId, uint256 tokenId)
        external
        nonReentrant
        biddingEnded(projectId)
        onlyNFTHolder(tokenId)
    {
        Project storage project = projects[projectId];
        address currentNFTHolder = NFTContract.ownerOf(tokenId);

        // Find the bid that matches the given tokenId
        address bidCreator;
        bool bidFound = false;
        for (uint256 i = 0; i < project.bidderAddresses.length; i++) {
            address bidderAddress = project.bidderAddresses[i];
            if (project.bids[bidderAddress].nftTokenId == tokenId) {
                bidCreator = bidderAddress;
                bidFound = true;
                break;
            }
        }

        require(bidFound, "No bid found for the given token ID");
        Bid storage bid = project.bids[bidCreator];
        require(bid.timestamp > 0, "No bid found for the sender");

        uint256 currentMonth = (block.timestamp - project.biddingEndDate) /
            period;
        require(currentMonth >= 0, "No vested amount to withdraw yet");

        uint256 vestedAmount = calculateVestedAmount(
            projectId,
            bidCreator,
            currentMonth + 1
        );

        require(
            vestedAmount > 0 && vestedAmount > bid.lockedIWOSize,
            "No new vested amount to withdraw"
        );

        uint256 withdrawableAmount = vestedAmount - bid.lockedIWOSize;

        require(
            IWO.transfer(currentNFTHolder, withdrawableAmount * (10**18)),
            "Token transfer failed during withdrawal"
        );

        bid.lockedIWOSize = vestedAmount;
        if (bid.lockedIWOSize >= bid.allocationIWOSize) {
            bid.locked = true;
        }

        emit Withdrawal(
            projectId,
            currentNFTHolder,
            withdrawableAmount,
            block.timestamp
        );
    }

    function addToWhitelist(uint256 projectId, address _address)
        public
        onlyOwnerOrOperator
    {
        projects[projectId].whitelist[_address] = true;
    }

    function removeFromWhitelist(uint256 projectId, address _address)
        public
        onlyOwnerOrOperator
    {
        projects[projectId].whitelist[_address] = false;
    }

    function addReferral(address referrer, address referee) public {
        require(referrals[referee] == address(0), "Referee already referred");
        require(referrer != referee, "Cannot refer yourself");
        referrals[referee] = referrer;
        referralsByUser[referrer].push(referee);
        emit ReferralRecorded(referrer, referee);
    }

    function getReferrer(address referee) external view returns (address) {
        return referrals[referee];
    }

    function getReferralsByUser(address referrer)
        external
        view
        returns (address[] memory)
    {
        return referralsByUser[referrer];
    }

    function pause() public onlyOwner whenNotPaused {
        paused = true;
    }

    function unpause() public onlyOwner whenPaused {
        paused = false;
    }

    function updateProjectOwner(uint256 projectId, address newOwner)
        public
        onlyProjectOwner(projectId)
    {
        require(newOwner != address(0), "New owner is the zero address");
        projects[projectId].owner = newOwner;
    }

    function updateProjectDetails(
        uint256 projectId,
        string memory newProjectName,
        string memory newProjectDescription,
        string memory newSocialInfo
    ) public onlyProjectOwner(projectId) {
        Project storage project = projects[projectId];
        project.projectName = newProjectName;
        project.projectDescription = newProjectDescription;
        project.socialInfo = newSocialInfo;
    }

    function updateBiddingDates(
        uint256 projectId,
        uint256 newBiddingStartDate,
        uint256 newBiddingEndDate
    ) public onlyProjectOwner(projectId) {
        require(
            newBiddingEndDate > newBiddingStartDate,
            "End date must be after start date"
        );
        Project storage project = projects[projectId];
        project.biddingStartDate = newBiddingStartDate;
        project.biddingEndDate = newBiddingEndDate;
    }

    function updateVestingRound(
        uint256 projectId,
        uint256 roundIndex,
        uint256 newRoundAmount,
        uint256 newIwoPrice
    ) public onlyProjectOwner(projectId) {
        require(
            roundIndex < projects[projectId].vestingRounds.length,
            "Invalid round index"
        );
        VestingRound storage round = projects[projectId].vestingRounds[
            roundIndex
        ];
        round.roundAmount = newRoundAmount;
        round.iwoPrice = newIwoPrice;
    }

    function updateOperatorAddress(
        uint256 projectId,
        address newOperatorAddress
    ) public onlyProjectOwner(projectId) {
        Project storage project = projects[projectId];
        project.operatorAddress = newOperatorAddress;
    }

    function updateOwner(address newOwner) public onlyOwner {
        owner = newOwner;
    }

    function updateOperatorAddress(address newOperatorAddress)
        public
        onlyOwnerOrOperator
    {
        operatorAddress = newOperatorAddress;
    }

    function updateContractAddresses(
        address newIWOAddress,
        address newUSDTAddress,
        address newNFTAddress
    ) public payable onlyOwnerOrOperator {
        IWO = IERC20(newIWOAddress);
        USDT = IERC20(newUSDTAddress);
        NFTContract = AlignerNFT(newNFTAddress);
    }

    // New functions to set and get the period
    function updatePeriod(uint256 newPeriod) external onlyOwner {
        period = newPeriod;
    }

    function withdrawUSDT() public payable onlyOwnerOrOperator {
        uint256 contractBalance = USDT.balanceOf(address(this));
        require(contractBalance > 0, "Insufficient balance in contract");

        require(USDT.transfer(msg.sender, contractBalance), "Transfer failed");
    }
}
