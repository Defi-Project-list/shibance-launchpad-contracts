// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IShibanceLotteryFactory {

    /**
     * @notice Generate random generated tickets for current lottery
     * @param _stakeHolder: stake holder address
     * @param _lotteryId: lottery id
     * @dev Callable by IDO master(operator)
     */
    function generateTickets(
        address _stakeHolder,
        uint256 _lotteryId
    ) external;

    /**
     * @notice Claim a set of winning tickets for a lottery
     * @param _lotteryId: lottery id
     * @dev Callable by users only, not contract!
     */
    function claimTickets(
        uint256 _lotteryId
    ) external;

    /**
     * @notice create lottery and start right now
     * @param _endTime: endTime of the lottery
     * @dev Callable by operator
     */
    function startLottery(
        address _idoPool,
        IERC20 _tokenAddress,
        uint256 _allocatedAmount,
        uint256 _endTime,
        uint256 _basicMultiplier,
        uint256 _premiumMultiplier,
        uint256 _eliteMultiplier,
        uint256 _lotteryFee
    ) external returns (uint256);

    /**
     * @notice Close lottery after project closed
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function closeLottery(
        uint256 _lotteryId
    ) external;

    /**
     * @notice Draw the final number, calculate reward in CAKE per group, and make lottery claimable
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function drawFinalNumberAndMakeLotteryClaimable(uint256 _lotteryId) external;

    /**
     * @notice Return last lottery id
     * @dev Callable by RandomGenerator
     */
    function viewLastLotteryId() external view returns (uint256);
}
