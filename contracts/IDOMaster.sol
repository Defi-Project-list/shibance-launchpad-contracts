// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IShibanceLotteryFactory.sol";
import "./interfaces/IRandomNumberGenerator.sol";
import "./libraries/Utils.sol";
import "./IDOVault.sol";
import "./IDOJudgement.sol";
import "./IDOProject.sol";

contract IDOMaster is IDOContext, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  IDOVault public idoVault;
  IDOJudgement public idoJudgement;
  IShibanceLotteryFactory public lotteryFactory;
  IRandomNumberGenerator public randomGenerator;

  address public admin;

  IDOProject[] public projects; // todo, make it private when deploy on mainnet
  // [project index][tier level]: user address
  mapping(uint256 => mapping(uint256 => address[])) participants;

  uint256 public minPeriod = 1 hours; // minimum period between contribute steps

  event ProjectCreated(
    IERC20 idoToken,
    IERC20 contributeToken,
    uint256 contributionTokenDecimal,
    uint256 totalTokens,
    uint256 softCaps
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
    uint256 _xWoofForDivine
  ) {

    admin = _admin;
    idoVault = IDOVault(_idoVault);
    lotteryFactory = IShibanceLotteryFactory(_lotteryFactory);
    randomGenerator = IRandomNumberGenerator(_randomGenerator);

    idoJudgement = new IDOJudgement(idoVault);
    idoJudgement.setxWOOFLevel(
      _xWoofForBasic,
      _xWoofForPremium,
      _xWoofForElite,
      _xWoofForRoyal,
      _xWoofForDivine
    );
  }

  /**
   * @notice 
   */
  function setIDOVault(IDOVault _idoVault) external onlyOwner {
    idoVault = _idoVault;
    idoJudgement.setIDOVault(_idoVault);
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
   * @notice Set xWOOF requirements
   * @param _xWoofForBasic basic
   * @param _xWoofForPremium premium
   * @param _xWoofForElite elite
   * @param _xWoofForRoyal royal
   * @param _xWoofForDivine divine
   */
  function setxWOOFLevel(
    uint256 _xWoofForBasic,
    uint256 _xWoofForPremium,
    uint256 _xWoofForElite,
    uint256 _xWoofForRoyal,
    uint256 _xWoofForDivine
  ) external onlyAdmin {
    idoJudgement.setxWOOFLevel(
      _xWoofForBasic,
      _xWoofForPremium,
      _xWoofForElite,
      _xWoofForRoyal,
      _xWoofForDivine
    );
  }

  /**
   * @notice add new IDO project
   * @param _idoToken new token
   * @param _contributionToken contribution token(ex. BUSD)
   * @param _contributionTokenDecimal contribution token decimal(ex. 18)
   * @param _totalTokens total amount to be going to sell
   * @param _softCaps soft capacity threshold in BUSD
   */
  function addProject(
    IERC20 _idoToken,
    IERC20 _contributionToken,
    uint256 _contributionTokenDecimal,
    uint256 _totalTokens,
    uint256 _softCaps
  ) external onlyAdmin {
    require(_contributionTokenDecimal > 0, "Invalid token decimal");
    require(_totalTokens > _softCaps, "Total token amount is smaller than soft capability");

    IDOProject idoProject = new IDOProject(
      _idoToken,
      _contributionToken,
      _contributionTokenDecimal,
      _totalTokens,
      _softCaps
    );

    _idoToken.safeTransferFrom(
      msg.sender,
      address(idoProject),
      _totalTokens
    );

    projects.push(idoProject);

    emit ProjectCreated(
      _idoToken,
      _contributionToken,
      _contributionTokenDecimal,
      _totalTokens,
      _softCaps);
  }

  /**
   * @notice Update project information, can not update after snapshot time
   * @param _pid project id
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
    uint _pid,
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
  ) external onlyAdmin onlyValidProject(_pid) {
    require(_userContributionTime <= _overflowTime1 + minPeriod, "Invalid overflow window1 time");
    require(_overflowTime1 <= _overflowTime2 + minPeriod, "Invalid overflow window2 time");
    require(_overflowTime2 <= _generalSaleTime + minPeriod, "Invalid general sale time");
    require(_generalSaleTime <= _distributionTime + minPeriod, "Invalid distribution time");
    require(_minContributionAmount > 0, "Invalid minimum contribution amount");

    uint pid = _pid.sub(1);
    projects[pid].updateProject(
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
   * @param _pid project id
   * @param _weights weightage for every tier level, percentage in 1000 as 100%
   * @param _numberOfLotteryWinners [0]: for basic, [1]: for premium, [2]: for elite
   */
  function takeSnapshotAndAllocate(
    uint256 _pid,
    uint256[5] calldata _weights,
    uint256[3] calldata _numberOfLotteryWinners
  ) external onlyAdmin onlyValidProject(_pid) {

    _pid = _pid.sub(1);
    getParticipants(_pid);

    IDOProject project = projects[_pid];

    (uint256 totalTokens,) = project.getProjectBalance();

    // guaranteed allocation for Royal and Divine tier
    for (uint256 i = ROYAL_TIER; i <= DIVINE_TIER; i++) {
      uint256 allocationPerTier = totalTokens.mul(_weights[i - 1]).div(10000);
      uint256 len = participants[_pid][i].length;
      for (uint256 j = 0; j < len; j++) {
        address addr = participants[_pid][i][j];
        project.addWhiteList(
          addr,
          allocationPerTier.div(len)
        );
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
      uint32[] memory ticketNumbers = generateTicketNumber(_pid, i, seed);

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
      uint256 allocationPerTier = totalTokens.mul(_weights[i - 1]).div(10000);
      uint256 allocationPerEntry = allocationPerTier.div(numberOfWinsWithoutDuplication);
      for (uint256 j = 0; j < winnerAddress.length; j++) {
        address addr = winnerAddress[j];
        project.addWhiteList(
          addr,
          allocationPerEntry.mul(numberOfWins[i])
        );
      }
    }
  }

  /**
   * @notice List all stakeholders according to their tier level
   * @param _pid project index
   * @dev only used as private function
   */
  function getParticipants(
    uint256 _pid
  ) private {
    address[] memory users = idoVault.getUsers();
    for (uint256 i = 0; i < users.length; i++) {
      uint256 tierLevel = idoJudgement.getTierLevel(users[i]);
      if (tierLevel < BASIC_TIER) {
        continue;
      }
      participants[_pid][tierLevel].push(users[i]);
    }
  }

  /**
   * @notice Generate ticket number for participants of given projects
   * @param _pid project index
   * @param _tierLevel tier level
   * @param _seed seed for random
   * @return array of ticket numbers, length is equal to length of participants
   */
  function generateTicketNumber(
    uint256 _pid,
    uint256 _tierLevel,
    uint256 _seed
  ) private view returns (uint32[] memory) {
    uint32[] memory ticketNumbers = new uint32[](participants[_pid][_tierLevel].length);
    for (uint256 j = 0; j < participants[_pid][_tierLevel].length; j++) {
      ticketNumbers[j] = uint32(Utils.random(
        1000000,
        1999999,
        uint256(keccak256(abi.encodePacked(_seed, uint256(uint160(participants[_pid][_tierLevel][j])))))
      ));
    }
    return ticketNumbers;
  }
}