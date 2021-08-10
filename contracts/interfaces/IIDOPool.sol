// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IIDOPool {

    /**
     * @notice stake tokens and get xWoof value
     * @param _amountToStake amount of stakeToken
     * @dev Callable by user
     */
    function stakeTokens(
        uint256 _amountToStake
    ) external;

    /**
     * @notice withdraw all the staked token
     * @dev Callable by user
     */
    function withdrawStake() external;

    /**
     * @notice return tier level per stake holer
     * @param stakeHolder stake holder address
     */
    function getTierLevel(address stakeHolder) external view returns (uint256);
}