// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

contract IDOContext is Ownable {

  uint256 public constant TIER_COUNT = 5;
  uint256 public constant NORMAL_WHITELIST = 0;
  uint256 public constant BASIC_TIER = 1;
  uint256 public constant PREMIUM_TIER = 2;
  uint256 public constant ELITE_TIER = 3;
  uint256 public constant ROYAL_TIER = 4;
  uint256 public constant DIVINE_TIER = 5;
}