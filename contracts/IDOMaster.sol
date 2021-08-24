// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IShibanceLotteryFactory.sol";
import "./interfaces/IRandomNumberGenerator.sol";
import "./libraries/Utils.sol";
import "./IDOVault.sol";

contract IDOMaster is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  IDOVault public idoVault;
  IShibanceLotteryFactory public lotteryFactory;
  IRandomNumberGenerator public randomGenerator;

  uint256 public constant TIER_COUNT = 5;
  uint256 public constant NORMAL_WHITELIST = 0;
  uint256 public constant BASIC_TIER = 1;
  uint256 public constant PREMIUM_TIER = 2;
  uint256 public constant ELITE_TIER = 3;
  uint256 public constant ROYAL_TIER = 4;
  uint256 public constant DIVINE_TIER = 5;
  
  // // Weightage for tier level
  // uint256 basicPercent = 175; // 1.75%
  // uint256 premiumPercent = 1050; // 10.5%
  // uint256 elitePercent = 2275; // 22.75%
  // uint256 public royalPercent = 2000; // 20%
  // uint256 public divinePercent = 4500; // 45%

  // xWOOF requirements
  uint256 public xWoofForBasic;
  uint256 public xWoofForPremium;
  uint256 public xWoofForElite;
  uint256 public xWoofForRoyal;
  uint256 public xWoofForDivine;

  address public admin;
  
  struct Project {
    uint256 id; // project id
    // bool active; // true if opening, false if closed
    bool canceled; // true if canceled, canceled project will return back contribution token.
    IERC20 idoToken; // new token
    IERC20 contributionToken; // BUSD
    uint256 contributionTokenDecimal; // decimal point for contribution token
    uint256 totalTokens; // total amount to be going to sell
    uint256 totalClaimed; // total amount which is already claimed in idoToken
    uint256 totalContributedAmount; // total contribution amount in contributionToken
    uint256 softCaps; // soft capacity threshold in contributionToken
    uint256 ratePerContributionToken; // rate of idoToken per contributeToken(BUSD)
    uint256 snapshotTime; // IDO snapshot date, private, hidden to user, todo
    uint256 userContributionTime; // whitelist user can send BUSD to IDO contract
    uint256 minContributionAmount; // minimum amount in idoToken
    uint256 overflowTime1; // only tier 4 and 5 can contribute more
    uint256 overflowTime2; // only tier 1,2,and 3 can contribute more
    uint256 generalSaleTime; // general opening, everybody can contribute
    uint256 distributionTime; // distribute tokens to contributors
  }


  Project[] public projects; // todo, make it private when deploy on mainnet

  struct User {
    uint256 pid; // project id
    address addr; // user address
    uint256 snapshotAmount; // maximum allocation amount in idoToken at snapshot stage
    uint256 allocatedTokenAmount; // allocated token amount for idoToken in Project
    uint256 contributionAmount; // contributed token amount for contributionToken in Project
    // uint256 returnableAmount; // returnable amount when project is canceled, todo
    // uint256 returnBackAmount; // returning token amount for contributionToken in Project when project is canceled, todo
    uint256 lastContributionTime; // last contribute time
    uint256 claimTime; // last claimed time
    bool active; // false if blacklist user, blacklist user can purchase but can not get allocation
    bool claimed; // true if claimed
    // bool returned; // true if returned back, todo
  }

  // [project index][tier level]: user address
  mapping(uint256 => mapping(uint256 => address[])) participants;
  // [project index][user address]: User
  mapping(uint256 => mapping(address => User)) public whiteList;

  uint256 public minPeriod = 1 hours; // minimum period between contribute steps

  event ProjectCreated(
    IERC20 idoToken,
    IERC20 contributeToken,
    uint256 totalTokens,
    uint256 snapshotTime,
    uint256 contributionTime,
    uint256 minContributionAmount,
    uint256 overflowTime1,
    uint256 overflowTime2,
    uint256 generalSaleTime,
    uint256 distributionTime
  );
  event ProjectUpdated(
    IERC20 idoToken,
    IERC20 contributeToken,
    uint256 totalTokens,
    uint256 contributeTime,
    uint256 minContributionAmount,
    uint256 overflowTime1,
    uint256 overflowTime2,
    uint256 generalSaleTime,
    uint256 distributionTime
  );

  modifier onlyAdmin() {
    require(msg.sender == admin, "Admin is required");
    _;
  }

  modifier onlyValidProject(uint256 pid) {
    require(pid > 0 && pid <= projects.length, "Invalid project id");
    _;
  }

  constructor(
    address _admin,
    address _idoVault,
    address _lotteryFactory,
    address _randomGenerator,
    uint256 _xWoofForBasic,
    uint256 _xWoofForPremium,
    uint256 _xWoofForElite,
    uint256 _xWoofForRoyal,
    uint256 _xWoofForDivine//,
    // uint256 _basicPercent,
    // uint256 _premiumPercent,
    // uint256 _elitePercent,
    // uint256 _royalPercent,
    // uint256 _divinePercent
  ) {

    admin = _admin;
    idoVault = IDOVault(_idoVault);
    lotteryFactory = IShibanceLotteryFactory(_lotteryFactory);
    randomGenerator = IRandomNumberGenerator(_randomGenerator);
    xWoofForBasic = _xWoofForBasic;
    xWoofForPremium = _xWoofForPremium;
    xWoofForElite = _xWoofForElite;
    xWoofForRoyal = _xWoofForRoyal;
    xWoofForDivine = _xWoofForDivine;

    // basicPercent = _basicPercent;
    // premiumPercent = _premiumPercent;
    // elitePercent = _elitePercent;
    // royalPercent = _royalPercent;
    // divinePercent = _divinePercent;
  }

  /**
   * @notice 
   */
  function setIDOVault(IDOVault _idoVault) external onlyOwner {
    idoVault = _idoVault;
  }

  /**
   * @notice 
   */
  function setLotteryFactory(IShibanceLotteryFactory _lotteryFactory) external onlyOwner {
    lotteryFactory = _lotteryFactory;
  }

  function setRandomGenerator(IRandomNumberGenerator _randomGenerator) external onlyOwner {
    randomGenerator = _randomGenerator;
  }

  /**
   * @notice set minimum period between contribute steps
   * @param _period unit in minutes
   */
  function setMinPeriod(uint256 _period) external onlyAdmin {
    minPeriod = _period * 60;
  }

  /**
  * @notice Sets admin address
  * @dev Only callable by the contract owner.
  */
  function setAdmin(address _admin) external onlyOwner {
    require(_admin != address(0), "Cannot zero address");
    admin = _admin;
  }

  /**
   */
  function setxWOOFLevel(
    uint256 _xWoofForBasic,
    uint256 _xWoofForPremium,
    uint256 _xWoofForElite,
    uint256 _xWoofForRoyal,
    uint256 _xWoofForDivine
  ) external onlyAdmin {
    require(_xWoofForBasic < _xWoofForPremium &&
      _xWoofForPremium < _xWoofForElite &&
      _xWoofForElite < _xWoofForRoyal &&
      _xWoofForRoyal < _xWoofForDivine, "Invalid xWOOF level");
    xWoofForBasic = _xWoofForBasic;
    xWoofForPremium = _xWoofForPremium;
    xWoofForElite = _xWoofForElite;
    xWoofForRoyal = _xWoofForRoyal;
    xWoofForDivine = _xWoofForDivine;
  }

  /**
   * @notice add new IDO project
   * @param _idoToken new token
   * @param _contributionToken contribution token(ex. BUSD)
   * @param _contributionTokenDecimal contribution token decimal(ex. 18)
   * @param _totalTokens total amount to be going to sell
   * @param _softCaps soft capacity threshold in BUSD
   * @param _ratePerContributionToken rate per contribution token(ex. BUSD)
   * @param _snapshotTime IDO snapshot date, private, hidden to user
   * @param _userContributionTime user can send BUSD to IDO contract
   * @param _minContributionAmount minimum contribution amount
   * @param _overflowTime1 only tier 4 and 5 can contribute more
   * @param _overflowTime2 only tier 1,2,and 3 can contribute more
   * @param _generalSaleTime general opening, everybody can contribute
   * @param _distributionTime distribute tokens to contributors
   */
  function addProject(
    IERC20 _idoToken,
    IERC20 _contributionToken,
    uint256 _contributionTokenDecimal,
    uint256 _totalTokens,
    uint256 _softCaps//,
    uint256 _ratePerContributionToken,
    uint256 _snapshotTime,
    uint256 _userContributionTime,
    uint256 _minContributionAmount,
    uint256 _overflowTime1,
    uint256 _overflowTime2,
    uint256 _generalSaleTime,
    uint256 _distributionTime
  ) external onlyAdmin returns (uint256) {
    require(_contributionTokenDecimal > 0, "Invalid token decimal");
    require(_totalTokens > _softCaps, "Total token amount is smaller than soft capability");
    require(block.timestamp < _snapshotTime, "Invalid snapshot time");
    require(_snapshotTime <= _userContributionTime + minPeriod, "Invalid user contribution time");
    require(_userContributionTime <= _overflowTime1 + minPeriod, "Invalid overflow window1 time");
    require(_overflowTime1 <= _overflowTime2 + minPeriod, "Invalid overflow window2 time");
    require(_overflowTime2 <= _generalSaleTime + minPeriod, "Invalid general sale time");
    require(_generalSaleTime <= _distributionTime + minPeriod, "Invalid distribution time");
    require(_minContributionAmount > 0, "Invalid minimum contribution amount");

    uint256 pid = projects.length.add(1);
    // projects.push(Project({
    //   id: pid,
    //   canceled: false,
    //   idoToken: _idoToken,
    //   contributionToken: _contributionToken,
    //   contributionTokenDecimal: _contributionTokenDecimal,
    //   totalTokens: _totalTokens,
    //   totalClaimed: 0,
    //   totalContributedAmount: 0,
    //   softCaps: _softCaps
    // }));

    Project storage project = projects[pid];
    project.id = pid;
    project.canceled = false;
    project.idoToken = _idoToken;
    project.contributionToken = _contributionToken;
    project.contributionTokenDecimal = _contributionTokenDecimal;
    project.totalTokens = _totalTokens;
    project.totalClaimed = 0;
    project.softCaps = _softCaps;
    project.ratePerContributionToken = _ratePerContributionToken;
    project.snapshotTime = _snapshotTime;
    project.userContributionTime = _userContributionTime;
    project.minContributionAmount = _minContributionAmount;
    project.overflowTime1 = _overflowTime1;
    project.overflowTime2 = _overflowTime2;
    project.generalSaleTime = _generalSaleTime;
    project.distributionTime = _distributionTime;

    emit ProjectCreated(
      _idoToken,
      _contributionToken,
      _totalTokens,
      _snapshotTime,
      _userContributionTime,
      _minContributionAmount,
      _overflowTime1,
      _overflowTime2,
      _generalSaleTime,
      _distributionTime);

    return pid;
  }

  /**
   * @notice Update project information, can not update after snapshot time
   * @param _pid project id
   * @param _contributionToken contribution token(ex. BUSD)
   * @param _totalTokens total amount to be going to sell
   * @param _softCaps soft capacity threshold in BUSD
   * @param _ratePerContributionToken rate per contribution token(ex. BUSD)
   * @param _userContributionTime user can send BUSD to IDO contract
   * @param _minContributionAmount minimum contribution amount
   * @param _overflowTime1 only tier 4 and 5 can contribute more
   * @param _overflowTime2 only tier 1,2,and 3 can contribute more
   * @param _generalSaleTime general opening, everybody can contribute
   * @param _distributionTime distribute tokens to contributors
   */
  function updateProject(
    uint _pid,
    IERC20 _contributionToken,
    uint256 _totalTokens,
    uint256 _softCaps,
    uint256 _ratePerContributionToken,
    uint256 _userContributionTime,
    uint256 _minContributionAmount,
    uint256 _overflowTime1,
    uint256 _overflowTime2,
    uint256 _generalSaleTime,
    uint256 _distributionTime
  ) external onlyAdmin onlyValidProject(_pid) {
    require(_totalTokens > _softCaps, "Total token amount is smaller than soft capability");
    require(_userContributionTime <= _overflowTime1 + minPeriod, "Invalid overflow window1 time");
    require(_overflowTime1 <= _overflowTime2 + minPeriod, "Invalid overflow window2 time");
    require(_overflowTime2 <= _generalSaleTime + minPeriod, "Invalid general sale time");
    require(_generalSaleTime <= _distributionTime + minPeriod, "Invalid distribution time");
    require(_minContributionAmount > 0, "Invalid minimum contribution amount");

    uint pid = _pid.sub(1);
    Project storage project = projects[pid];
    // require(project.active, "Inactive project");
    require(!project.canceled, "Canceled project");
    require(project.snapshotTime > block.timestamp, "Do not allow to update project");

    project.contributionToken = _contributionToken;
    project.totalTokens = _totalTokens;
    project.softCaps = _softCaps;
    project.ratePerContributionToken = _ratePerContributionToken;
    project.userContributionTime = _userContributionTime;
    project.minContributionAmount = _minContributionAmount;
    project.overflowTime1 = _overflowTime1;
    project.overflowTime2 = _overflowTime2;
    project.generalSaleTime = _generalSaleTime;
    project.distributionTime = _distributionTime;
  }

  // /**
  //  * @notice Because of not-enough soft caps or other reason, cancel given project and return back
  //  * @param _pid project id
  //  */
  // function inactiveProject(uint256 _pid) public onlyAdmin onlyValidProject(_pid) {
  //   uint256 pid = _pid.sub(1);
  //   projects[pid].active = false;
  // }

  // /**
  //  * @notice Activate given project
  //  * @param _pid project id
  //  * @param _active active status
  //  */
  // function activeProject(uint256 _pid) public onlyAdmin onlyValidProject(_pid) {
  //   uint256 pid = _pid.sub(1);
  //   projects[pid].active = true;
  // }

  // /**
  //  * @notice Return project's active status
  //  * @return true/false
  //  */
  // function isProjectActive(uint256 _pid) public view onlyValidProject(_pid) returns (bool) {
  //   uint256 pid = _pid.sub(1);
  //   return projects[pid].active;
  // }

  /**
   * @notice return total/sold token amount
   * @param _pid project id
   * @return (total token amount, total sold amount)
   */
  function getProjectBalance(uint256 _pid) public view onlyValidProject(_pid) returns (uint256, uint256) {
    uint pid = _pid.sub(1);
    Project storage project = projects[pid];
    return (project.totalTokens, project.totalClaimed);
  }

  /**
   * @notice this don't return snapshotTime
   * @param _pid project id
   */
  function getProjectInfo(uint256 _pid) public view onlyValidProject(_pid) returns (
    // bool active,
    bool canceled,
    IERC20 idoToken,
    IERC20 contributeToken,
    uint256 totalTokens,
    uint256 totalClaimed,
    uint256 softCaps,
    uint256 ratePerContributionToken,
    uint256 userContributionTime,
    uint256 minContributeAmount,
    uint256 overflowTime1,
    uint256 overflowTime2,
    uint256 generalSaleTime,
    uint256 distributionTime
  ) {
    uint pid = _pid.sub(1);
    Project storage project = projects[pid];
    return (
      // project.active,
      project.canceled,
      project.idoToken,
      project.contributionToken,
      project.totalTokens,
      project.totalClaimed,
      project.softCaps,
      project.ratePerContributionToken,
      project.userContributionTime,
      project.minContributionAmount,
      project.overflowTime1,
      project.overflowTime2,
      project.generalSaleTime,
      project.distributionTime
    );
  }

  /**
   * @notice Take snapshot and calculate allocation amount
   * @param _pid project id
   * @param _weights weightage for every tier level, percentage in 1000 as 100%
   * @param _numberOfLotteryWinners [0]: for basic, [1]: for premium, [2]: for elite
   */
  function takeSnapshotAndAllocate(
    uint256 _pid,
    uint256[5] calldata _weights,
    uint256[3] calldata _numberOfLotteryWinners
  ) external onlyAdmin onlyValidProject(_pid) {
    uint pid = _pid.sub(1);
    Project storage project = projects[pid];

    address[] memory users = idoVault.getUsers();

    uint256 userCount = users.length;
    for (uint256 i = 0; i < userCount; i++) {
      uint256 tierLevel = getTierLevel(users[i]);
      if (tierLevel < BASIC_TIER) {
        continue;
      }
      participants[_pid][tierLevel].push(users[i]);
    }

    // guaranteed allocation for Royal and Divine tier
    for (uint256 i = ROYAL_TIER; i <= DIVINE_TIER; i++) {
      uint256 allocationPerTier = project.totalTokens.mul(_weights[i - 1]).div(10000);
      uint256 len = participants[_pid][i].length;
      for (uint256 j = 0; j < len; j++) {
        address addr = participants[_pid][i][j];
        whiteList[_pid][addr].pid = _pid;
        whiteList[_pid][addr].addr = addr;
        whiteList[_pid][addr].snapshotAmount = allocationPerTier.div(len);
        whiteList[_pid][addr].active = true;
        whiteList[_pid][addr].claimed = false;
        // whiteList[_pid][addr].returned = false;
      }
    }

    randomGenerator.getRandomNumber(block.timestamp);
    uint256 seed = randomGenerator.viewRandomResult();

    // lottery-based allocation for Basic, Premium, Elite tier
    for (uint256 i = BASIC_TIER; i <= ELITE_TIER; i++) {
      if (participants[_pid][i].length < 1) {
        continue;
      }

      // generate random ticket numbers
      uint32[] memory ticketNumbers = new uint32[](participants[_pid][i].length);
      for (uint256 j = 0; j < participants[_pid][i].length; j++) {
        ticketNumbers[j] = uint32(Utils.random(
          1000000,
          1999999,
          uint256(keccak256(abi.encodePacked(seed, uint256(uint160(participants[_pid][i][j])))))
        ));
      }

      // determine lottery winner address
      (
        address[] memory winnerAddress,
        uint256[] memory numberOfWins,
        uint256 numberOfWinsWithoutDuplication
      ) = lotteryFactory.playLottery(participants[_pid][i], ticketNumbers, _numberOfLotteryWinners[i - 1]);
      if (numberOfWinsWithoutDuplication < 1) { // if nobody matched
        continue;
      }

      // allocate maximum amount to contribute
      uint256 allocationPerTier = project.totalTokens.mul(_weights[i - 1]).div(10000);
      uint256 allocationPerEntry = allocationPerTier.div(numberOfWinsWithoutDuplication);
      for (uint256 j = 0; j < winnerAddress.length; j++) {
        address addr = winnerAddress[j];
        whiteList[_pid][addr].pid = _pid;
        whiteList[_pid][addr].addr = addr;
        whiteList[_pid][addr].snapshotAmount = allocationPerEntry.mul(numberOfWins[i]);
        whiteList[_pid][addr].active = true;
        whiteList[_pid][addr].claimed = false;
        // whiteList[_pid][addr].returned = false;
      }
    }
  }

  /**
   * @notice Contribute on project
   * @param _pid project id
   * @param _contributionAmount contribution amount in contributeToken
   */
  function contributeProject(
    uint256 _pid,
    uint256 _contributionAmount
  ) public nonReentrant onlyValidProject(_pid) {
    require(_contributionAmount > 0, "Invalid contribution amount");
    
    User storage user = whiteList[_pid][msg.sender];
    // require(user.active, "Not a active user");

    uint256 tierLevel = getTierLevel(user.addr);
    require(tierLevel >= BASIC_TIER, "Only tier users can contribute");

    uint pid = _pid.sub(1);
    Project storage project = projects[pid];
    // require(project.active, "Inactive project");
    require(!project.canceled, "Canceled project");
    require(project.distributionTime < block.timestamp, "Already ended contribution time");
    require(project.generalSaleTime > block.timestamp, "Now is general sale time");

    if (project.generalSaleTime > block.timestamp) { // general sale stage
    } else if (project.overflowTime2 < block.timestamp) {
      require(tierLevel == BASIC_TIER || tierLevel == PREMIUM_TIER || tierLevel == ELITE_TIER, "Tier 1,2,3 can contribute");
    } else if (project.overflowTime1 < block.timestamp) {
      require(tierLevel == ROYAL_TIER || tierLevel == DIVINE_TIER, "Tier 4,5 can contribute");
    } else { // first contribution stage
      // every user has limitation newtoken amount to contribute
      require(
        calculateTokenAmount(
          user.contributionAmount.add(_contributionAmount),
          project.ratePerContributionToken,
          project.contributionTokenDecimal
        ) < user.snapshotAmount,
        "First stage has limitation amount"
      );
    }

    require(_contributionAmount >= project.minContributionAmount, "Need to contribute more");
    uint256 tokenAmount = 
      calculateTokenAmount(
        project.totalContributedAmount.add(_contributionAmount),
        project.ratePerContributionToken,
        project.contributionTokenDecimal);
    require(tokenAmount < project.totalTokens, "Exceed the total token amount");

    user.contributionAmount = user.contributionAmount.add(_contributionAmount);
    user.lastContributionTime = block.timestamp;

    project.totalContributedAmount = project.totalContributedAmount.add(_contributionAmount);
  }

  /**
   * @notice Claim allocated tokens, blocked list can not claim token
   * @param _pid project id
   * @return claimed amount
   */
  function claimTokens(uint256 _pid) public onlyValidProject(_pid) returns (uint256) {
    uint pid = _pid.sub(1);
    Project storage project = projects[pid];
    // require(!project.active, "Not closed project");

    User storage user = whiteList[_pid][msg.sender];
    require(user.active, "Blocked user");

    uint256 userBalance = getUserTotalPurchase(pid);
    require(userBalance > 0, "Invalid claim");

    user.allocatedTokenAmount = calculateTokenAmount(
      userBalance,
      project.ratePerContributionToken,
      project.contributionTokenDecimal);

    project.idoToken.transfer(msg.sender, user.allocatedTokenAmount);
    project.totalClaimed = project.totalClaimed.add(user.allocatedTokenAmount);
    user.claimed = true;
    return user.allocatedTokenAmount;
  }

  /**
   * @notice Block user
   * @param _pid project id
   * @param _user user address
   */
  function blockUser(uint256 _pid, address _user) public onlyAdmin onlyValidProject(_pid) {
    require(_user != address(0), "Zero address");

    User storage user = whiteList[_pid][_user];
    user.active = false;
  }

  /**
   * @notice Check if user is active
   * @param _pid project id
   * @param _user user address
   * @return true if active
   */
  function isUserActive(uint256 _pid, address _user) public view onlyValidProject(_pid) returns (bool) {
    require(_user != address(0), "Zero address");
    return whiteList[_pid][_user].active;
  }

  /**
   * @notice Get user's tier level according to staking WOOF amount
   * @param _user user address
   * @return tier level
   */
  function getTierLevel(address _user) internal view returns (uint256) {
    require(_user != address(0), "Zero address");
    (, uint256 xWOOF,,,,,) = idoVault.getUserInfo(_user);
    if (xWOOF >= xWoofForDivine) {
      return DIVINE_TIER;
    } else if (xWOOF >= xWoofForRoyal) {
      return ROYAL_TIER;
    } else if (xWOOF >= xWoofForElite) {
      return ELITE_TIER;
    } else if (xWOOF >= xWoofForPremium) {
      return PREMIUM_TIER;
    } else if (xWOOF >= xWoofForBasic) {
      return BASIC_TIER;
    }
    return NORMAL_WHITELIST;
  }

  /**
   * @notice Get user's total purchased amount
   * @param _pid project id
   */
  function getUserTotalPurchase(uint256 _pid) public view onlyValidProject(_pid) returns (uint256) {
    return whiteList[_pid][msg.sender].contributionAmount;
  }

  function calculateTokenAmount(
    uint256 contributionAmount,
    uint256 rate,
    uint256 decimal
  ) public pure returns (uint256) {
    return contributionAmount.mul(rate).div(10 ** decimal);
  }
}