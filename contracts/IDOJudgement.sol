// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IDOContext.sol";
import "./IDOVault.sol";

contract IDOJudgement is IDOContext {

  IDOVault public idoVault;

  // xWOOF requirements
  uint256 public xWoofForBasic;
  uint256 public xWoofForPremium;
  uint256 public xWoofForElite;
  uint256 public xWoofForRoyal;
  uint256 public xWoofForDivine;

  constructor(
    IDOVault _idoVault
  ) {
    idoVault = _idoVault;
  }

  /**
   * @notice 
   */
  function setIDOVault(IDOVault _idoVault) external onlyOwner {
    idoVault = _idoVault;
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
  ) external onlyOwner {
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
   * @notice Get user's tier level according to staking WOOF amount
   * @param _user user address
   * @return tier level
   */
  function getTierLevel(address _user) public view returns (uint256) {
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
}