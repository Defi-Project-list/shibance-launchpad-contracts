// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import './interfaces/IShibanceLotteryFactory.sol';
import "./interfaces/IRandomNumberGenerator.sol";
import "./libraries/Utils.sol";

contract ShibanceLotteryFactory is ReentrancyGuard, IShibanceLotteryFactory, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public operatorAddress;
    IRandomNumberGenerator public randomGenerator;

    bool public isLotteryEnabled = true;

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "Not operator");
        _;
    }
    
    event RandomGenerated(
        uint32 randomNumber
    );
    event LotteryClosed(
        uint256 numberOfUsers,
        uint256 numberOfTargetWinners,
        uint256[] finalNumbers,
        address[] winners,
        uint256[] winTimes
    );
    event NewOperator(
        address operatorAddress
    );
    event NewRandomGenerator(address indexed randomGenerator);

    constructor(address _randomGenerator) {
        randomGenerator = IRandomNumberGenerator(_randomGenerator);
        operatorAddress = owner();
    }
    
    /**
     * @notice enable/disable lottery
     */
    function setLotteryEnabled(bool _enabled) external onlyOwner() {
        isLotteryEnabled = _enabled;
    }

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
    )
        external
        override
        onlyOperator
        returns (
            address[] memory,   // winner address
            uint256[] memory,    // number of winning times per address
            uint256              // number of winning times without duplication
        )
    {
        require(isLotteryEnabled, "Lottery not enabled");
        require(_numberOfWinners > 0, "Number of winners must be one or more");
        require(_users.length == _ticketNumbers.length, "Length of users and tickets must be same");
        require(_users.length >= _numberOfWinners, "Overflow number of winners");

        randomGenerator.getRandomNumber(block.timestamp);
        uint256 seed = randomGenerator.viewRandomResult32();

        address[] memory winners = new address[](_numberOfWinners);
        uint256[] memory winTimes = new uint256[](_numberOfWinners);
        uint256[] memory finalNumbers = new uint256[](_numberOfWinners);

        uint256 winTimesWithout;
        uint256 i;
        uint256 j;
        uint256 k;
        // address addr;
        uint256 userCount = _users.length;

        for (i = 0; i < _numberOfWinners; i++) {
            // addr = _users[i];
            finalNumbers[i] = uint32(Utils.random(
                1000000,
                1999999,
                uint256(keccak256(abi.encodePacked(seed, i)))
            ));
            // finalNumbers[i] = finalNumber;

            // emit RandomGenerated(finalNumber);

            for (j = 0; j < userCount; j++) {
                require(_ticketNumbers[j] >= 1000000 && _ticketNumbers[j] <= 1999999, "Ticket number overflow");
                if (_ticketNumbers[j] == finalNumbers[i]) {
                    // if matched ticket number, will count it against user address
                    for (k = 0; k < i; k++) {
                        if (winners[k] == _users[j]) {
                            break;
                        }
                    }
                    winTimesWithout++;
                    winTimes[k]++;
                    winners[k] = _users[j];
                    break;
                }
            }
        }

        emit LotteryClosed(
            userCount,
            _numberOfWinners,
            finalNumbers,
            winners,
            winTimes
        );

        return (winners, winTimes, winTimesWithout);
    }

    /**
     * @notice Set operator
     * @param _operatorAddress operator address
     * @dev Only callable by owner
     */
    function setOperator(
        address _operatorAddress
    ) external onlyOwner {
        require(_operatorAddress != address(0), "Cannot be zero address");

        operatorAddress = _operatorAddress;

        emit NewOperator(_operatorAddress);
    }

    /**
     * @notice Change the random generator
     * @param _randomGeneratorAddress: address of the random generator
     */
    function changeRandomGenerator(address _randomGeneratorAddress) external onlyOwner {
        randomGenerator = IRandomNumberGenerator(_randomGeneratorAddress);

        emit NewRandomGenerator(_randomGeneratorAddress);
    }

    /**
     * @notice Check if an address is a contract
     */
    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
}
