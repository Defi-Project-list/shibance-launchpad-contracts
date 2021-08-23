// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IIDOVault {

    function stake(uint256 _amount, uint256 _period) external;

    function unstakeAll() external;

    function unstake(uint256 _shares) external;

    function restake(uint256 _period) external;

    function getPricePerFullShare() external view returns (uint256);

    function getStakeAmount() external view returns (uint256);
}
