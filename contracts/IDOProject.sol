// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IDOContext.sol";
import "./IDOJudgement.sol";
import "./IDOVault.sol";

contract IDOProject is IDOContext, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public developer;

  IDOJudgement public idoJudgement;
  IDOVault public idoVault;

  // bool active; // true if opening, false if closed
  // bool canceled; // true if canceled, canceled project will return back contribution token.
  IERC20 public idoToken; // new token
  IERC20 public contributionToken; // BUSD
  uint256 public contributionTokenDecimal = 1; // decimal point for contribution token
  uint256 public totalTokens; // total amount to be going to sell
  uint256 public totalClaimed; // total amount which is already claimed in idoToken
  uint256 public totalContributedAmount; // total contribution amount in contributionToken
  uint256 public softCaps; // soft capacity threshold in contributionToken
  uint256 public ratePerContributionToken = 1; // rate of idoToken per contributeToken(BUSD)
  uint256 public snapshotTime; // IDO snapshot date, private, hidden to user, todo
  uint256 public userContributionTime; // whitelist user can send BUSD to IDO contract
  uint256 public minContributionAmount; // minimum amount in idoToken
  uint256 public overflowTime1; // only tier 4 and 5 can contribute more
  uint256 public overflowTime2; // only tier 1,2,and 3 can contribute more
  uint256 public generalSaleTime; // general opening, everybody can contribute
  uint256 public distributionTime; // distribute tokens to contributors

  struct User {
    // uint256 pid; // project id
    address addr; // user address
    uint256 snapshotAmount; // maximum allocation amount in idoToken at snapshot stage
    uint256 allocatedTokenAmount; // allocated token amount for idoToken in Project
    uint256 contributionAmount; // contributed token amount for contributionToken in Project
    // uint256 returnableAmount; // returnable amount when project is canceled, todo
    uint256 returnBackAmount; // returning token amount for contributionToken in Project when project is canceled, todo
    uint256 lastContributionTime; // last contribute time
    uint256 claimTime; // last claimed time
    uint256 returnBackTime; // last returned time
    bool active; // false if blacklist user, blacklist user can purchase but can not get allocation
    bool claimed; // true if claimed
    bool returned; // true if returned back, todo
  }

  mapping(uint256 => address[]) participants;
  mapping(address => User) public whiteList;
  
  event ProjectUpdated(
    IERC20 idoToken,
    IERC20 contributeToken,
    uint256 contributionTokenDecimal,
    uint256 minContributionAmount,
    uint256 softCaps,
    uint256 ratePerContributionToken,
    uint256 contributeTime,
    uint256 overflowTime1,
    uint256 overflowTime2,
    uint256 generalSaleTime,
    uint256 distributionTime
  );

  modifier onlyDeveloper() {
    require(msg.sender == developer, "Developer is required");
    _;
  }

  constructor(
    IDOJudgement _idoJudgement,
    IDOVault _idoVault,
    IERC20 _idoToken,
    IERC20 _contributionToken,
    uint256 _contributionTokenDecimal,
    uint256 _totalTokens,
    uint256 _softCaps
  ) {
    idoJudgement = _idoJudgement;
    idoVault = _idoVault;

    idoToken = _idoToken;
    contributionToken = _contributionToken;
    contributionTokenDecimal = _contributionTokenDecimal;
    totalTokens = _totalTokens;
    softCaps = _softCaps;
  }

  /**
   * @notice Sets developer address
   * @dev Only callable by the contract owner.
   */
  function setDeveloper(address _dev) external onlyOwner {
    require(_dev != address(0), "Cannot be zero address");
    developer = _dev;
  }

  function setRatePerContributionToken(uint256 _ratePerContributionToken) external onlyOwner {
    ratePerContributionToken = _ratePerContributionToken;
  }

  /**
   * @notice Update project information, can not update after snapshot time
   * @param _contributionToken contribution token(ex. BUSD)
   * @param _contributionTokenDecimal decimal point for contribution token(ex. 18)
   * @param _minContributionAmount minimum contribution amount
   * @param _softCaps soft capacity threshold in BUSD
   * @param _ratePerContributionToken rate per contribution token(ex. BUSD)
   * @param _userContributionTime user can send BUSD to IDO contract
   * @param _overflowTime1 only tier 4 and 5 can contribute more
   * @param _overflowTime2 only tier 1,2,and 3 can contribute more
   * @param _generalSaleTime general opening, everybody can contribute
   * @param _distributionTime distribute tokens to contributors
   */
  function updateProject(
    IERC20 _contributionToken,
    uint256 _contributionTokenDecimal,
    uint256 _minContributionAmount,
    uint256 _softCaps,
    uint256 _ratePerContributionToken,
    uint256 _userContributionTime,
    uint256 _overflowTime1,
    uint256 _overflowTime2,
    uint256 _generalSaleTime,
    uint256 _distributionTime
  ) external onlyOwner {
    require(!isCanceled(), "Canceled project");
    require(totalTokens > _softCaps, "Total token amount is smaller than soft capability");
    require(snapshotTime > block.timestamp, "Do not allow to update project");

    contributionToken = _contributionToken;
    contributionTokenDecimal = _contributionTokenDecimal;
    minContributionAmount = _minContributionAmount;
    softCaps = _softCaps;
    ratePerContributionToken = _ratePerContributionToken;
    userContributionTime = _userContributionTime;
    overflowTime1 = _overflowTime1;
    overflowTime2 = _overflowTime2;
    generalSaleTime = _generalSaleTime;
    distributionTime = _distributionTime;

    emit ProjectUpdated(
      idoToken,
      _contributionToken,
      _contributionTokenDecimal,
      _minContributionAmount,
      _softCaps,
      _ratePerContributionToken,
      _userContributionTime,
      _overflowTime1,
      _overflowTime2,
      _generalSaleTime,
      _distributionTime
    );
  }

  /**
   * @notice Take snapshot and calculate allocation amount
   * @param _weights weightage for every tier level, percentage in 1000 as 100%
   */
  function takeSnapshotAndAllocate(
    uint256[5] calldata _weights
  ) public onlyDeveloper {
    
    address[] memory users = idoVault.getUsers();
    for (uint256 i = 0; i < users.length; i++) {
      uint256 tierLevel = idoJudgement.getTierLevel(users[i]);
      if (tierLevel < BASIC_TIER) {
        continue;
      }
      addWhiteList(users[i], 0);
      participants[tierLevel].push(users[i]);
    }

    for (uint tierLevel = BASIC_TIER; tierLevel <= DIVINE_TIER; tierLevel++) {
      // snapshot allocation for all the tiers
      uint256 allocationPerUserTier = 
        participants[tierLevel].length > 0 ?
        totalTokens.mul(_weights[ROYAL_TIER - 1]).div(10000).div(participants[tierLevel].length) : 0;
      for (uint256 i = 0; i < participants[tierLevel].length; i++) {
        whiteList[participants[tierLevel][i]].snapshotAmount = allocationPerUserTier;
      }
    }
  }
  
  /**
   * @notice return total/sold token amount
   * @return (total token amount, total sold amount)
   */
  function getProjectBalance() public view returns (uint256, uint256) {
    return (totalTokens, totalClaimed);
  }

  function isCanceled() public view returns (bool) {
    return block.timestamp > distributionTime &&
      totalContributedAmount < softCaps;
  }

  function addWhiteList(
    address addr,
    uint256 snapshotAmount
  ) internal {
    whiteList[addr].addr = addr;
    whiteList[addr].snapshotAmount = snapshotAmount;
    whiteList[addr].active = true;
    whiteList[addr].claimed = false;
  }

  /**
   * @notice Block user
   * @param _user user address
   */
  function blockUser(address _user) public onlyOwner {
    require(_user != address(0), "Zero address");

    User storage user = whiteList[_user];
    user.active = false;
  }

  /**
   * @notice Check if user is active
   * @return true if active
   */
  function isUserActive() public view returns (bool) {
    return whiteList[msg.sender].active;
  }

  /**
   * @notice Get user's total purchased amount
   */
  function getUserTotalPurchase() public view returns (uint256) {
    return whiteList[msg.sender].contributionAmount;
  }

  /**
   * @notice Contribute on project
   * @param _contributionAmount contribution amount in contributeToken
   */
  function contributeProject(
    uint256 _contributionAmount
  ) public nonReentrant {
    require(!isCanceled(), "Canceled project");
    require(_contributionAmount >= minContributionAmount, "Need to contribute more");
    
    uint256 tierLevel = idoJudgement.getTierLevel(msg.sender);
    require(tierLevel >= BASIC_TIER, "Only tier users can contribute");

    // require(active, "Inactive project");
    require(distributionTime < block.timestamp, "Already ended contribution time");
    require(generalSaleTime > block.timestamp, "Now is general sale time");

    if (generalSaleTime > block.timestamp) { // general sale stage
    } else if (overflowTime2 < block.timestamp) {
      require(tierLevel == BASIC_TIER || tierLevel == PREMIUM_TIER || tierLevel == ELITE_TIER, "Tier 1,2,3 can contribute");
    } else if (overflowTime1 < block.timestamp) {
      require(tierLevel == ROYAL_TIER || tierLevel == DIVINE_TIER, "Tier 4,5 can contribute");
    } else { // first contribution stage
      limitedContribute(msg.sender, _contributionAmount);
      return;
    }

    unlimitedContribute(msg.sender, _contributionAmount);
  }

  function limitedContribute(
    address _addr,
    uint256 _contributionAmount
  ) private {
    User storage user = whiteList[_addr];
    require(user.active, "Only for KYC user");

    // every user has limitation newtoken amount to contribute
    require(
      calculateTokenAmount(user.contributionAmount.add(_contributionAmount)) < user.snapshotAmount,
      "First stage has limitation amount"
    );

    unlimitedContribute(_addr, _contributionAmount);
  }

  function unlimitedContribute(
    address _addr,
    uint256 _contributionAmount
  ) private {
    User storage user = whiteList[_addr];
    require(user.active, "Only for KYC user");

    uint256 tokenAmount =
      calculateTokenAmount(totalContributedAmount.add(_contributionAmount));
    require(tokenAmount < totalTokens, "Exceed the total token amount");

    user.contributionAmount = user.contributionAmount.add(_contributionAmount);
    user.lastContributionTime = block.timestamp;

    totalContributedAmount = totalContributedAmount.add(_contributionAmount);
  }

  /**
   * @notice Return back contributed tokens when project is canceled
   * @return returned tokens
   */
  function returnBack() public nonReentrant returns (uint256) {
    require(isCanceled(), "Not a canceled project");
    require(block.timestamp < distributionTime, "Now is not distribution time");

    User storage user = whiteList[msg.sender];
    require(user.active, "Only for KYC user");
    require(!user.returned, "Already returned");

    if (user.contributionAmount > 0) {
      contributionToken.safeTransfer(msg.sender, user.contributionAmount);
    }
    user.returnBackAmount = user.contributionAmount;
    user.returnBackTime = block.timestamp;
    user.returned = true;

    return user.returnBackAmount;
  }

  /**
   * @notice Claim allocated tokens, blocked list can not claim token
   * @return claimed amount
   */
  function claimTokens() public nonReentrant returns (uint256) {
    require(!isCanceled(), "Canceled project");
    require(block.timestamp < distributionTime, "Now is not distribution time");

    User storage user = whiteList[msg.sender];
    require(user.active, "Only for KYC user");
    require(!user.claimed, "Already claimed");

    user.allocatedTokenAmount = calculateTokenAmount(user.contributionAmount);
    if (user.allocatedTokenAmount > 0) {
      idoToken.transfer(msg.sender, user.allocatedTokenAmount);
      totalClaimed = totalClaimed.add(user.allocatedTokenAmount);
    }
    user.claimTime = block.timestamp;
    user.claimed = true;

    return user.allocatedTokenAmount;
  }

  function calculateTokenAmount(
    uint256 amount
  ) public view returns (uint256) {
    return amount.mul(ratePerContributionToken).div(10 ** contributionTokenDecimal);
  }
}
