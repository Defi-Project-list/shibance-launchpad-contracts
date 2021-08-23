// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

contract SafeMath7 {

  /**
   * @notice Calculate decimal power value, base^exponent
   * @param base: base, can be decimal
   * @param exponent: exponent
   */
  function pow7(uint256 base, uint256 exponent) internal pure returns (uint256) {
    // x = z^(log_z(x))
    // means that x^y = (z^(log_z(x)))^y
    // Let us assume z = 2
    return base**exponent;
  }
}