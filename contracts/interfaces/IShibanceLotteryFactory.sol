// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IShibanceLotteryFactory {

    /**
     * @notice Generate final numbers as the count of _numberOfWinners, and match ticket numbers
     * @param _users: list of user address
     * @param _ticketNumbers: list of ticket numbers
     * @param _numberOfWinners: number of target winners
     */
    function playLottery(
        address[] calldata _users,
        uint32[] calldata _ticketNumbers,
        uint256 _numberOfWinners
    ) external returns (
        address[] memory,   // winner address
        uint256[] memory,   // number of winning times per address
        uint256             // number of winning times without duplication
    );
}
