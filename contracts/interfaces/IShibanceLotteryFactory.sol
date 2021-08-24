// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IShibanceLotteryFactory {

    function addPlayer(
        uint256 level,
        address player
    ) external;

    function generateTicketNumbers(
        uint256 level
    ) external;

    /**
     * @notice Generate final numbers as the count of _numberOfWinners, and match ticket numbers
     * @param _level play level
     * @param _numberOfWinners number of target winners
     */
    function playLottery(
        uint256 _level,
        uint256 _numberOfWinners
    ) external returns (
        address[] memory,   // winner address, contains duplication
        uint256             // winner count
    );
}
