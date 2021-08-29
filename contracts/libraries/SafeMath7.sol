// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./ABDKMathQuad.sol";

contract SafeMath7 {
  using ABDKMathQuad for bytes16;

  /**
   * @notice Calculate decimal power value, base^exponent
   * @param base: base, can be decimal
   * @param exponent: exponent
   */
  function pow7(uint256 base, uint256 exponent) public pure returns (uint256) {
    // x = z^(log_z(x))
    // means that x^y = (z^(log_z(x)))^y
    // Let us assume z = 2
    // returns = base * 1.0224 ^ exponent = base * 2 ^ (exponent * (log_2(10224) - log_2(10000)))
    bytes16 ratesBy = ABDKMathQuad.fromUInt(10224);
    bytes16 ratesBaseBy = ABDKMathQuad.fromUInt(10000);

    bytes16 baseBy = ABDKMathQuad.fromUInt(base);
    bytes16 exponentBy = ABDKMathQuad.fromUInt(exponent);

    bytes16 logBy10224 = ABDKMathQuad.log_2(ratesBy);
    bytes16 logBy10000 = ABDKMathQuad.log_2(ratesBaseBy);

    bytes16 returnBy = baseBy.mul(ABDKMathQuad.pow_2(exponentBy.mul(logBy10224.sub(logBy10000))));
    return returnBy.toUInt();
  }
}
