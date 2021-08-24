// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import './interfaces/IShibanceLotteryFactory.sol';
import "./interfaces/IRandomNumberGenerator.sol";
import "./libraries/Utils.sol";

contract ShibanceLotteryFactory is IShibanceLotteryFactory, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public operatorAddress;
    IRandomNumberGenerator public randomGenerator;

    bool public isLotteryEnabled = true;

    mapping(address => bool) joined;
    // level => address[]
    mapping(uint256 => address[]) players;

    mapping(address => uint32) tickets; // length of address[] == length of mapping
    // level => uint32[]
    mapping(uint256 => uint32[]) finalNumbers;

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "Not operator");
        _;
    }
    
    event RandomGenerated(
        uint32 randomNumber
    );
    event LotteryClosed(
        uint256 level,
        uint256 numberOfTargetWinners,
        address[] winners,
        uint256 numberOfWinners
    );
    event NewOperator(
        address operatorAddress
    );
    event NewRandomGenerator(address indexed randomGenerator);

    constructor(IRandomNumberGenerator _randomGenerator) {
        randomGenerator = IRandomNumberGenerator(_randomGenerator);
        operatorAddress = owner();
    }
    
    /**
     * @notice enable/disable lottery
     */
    function setLotteryEnabled(bool _enabled) external onlyOwner {
        isLotteryEnabled = _enabled;
    }

    function addPlayer(uint256 level, address player) external onlyOwner override {
        require(!joined[player], "Already joined player");
        players[level].push(player);
        joined[player] = true;
    }

    function generateTicketNumbers(uint256 level) external onlyOwner override {
        randomGenerator.getRandomNumber(block.timestamp);
        uint256 seed = randomGenerator.viewRandomResult();

        for (uint256 i = 0; i < players[level].length; i++) {
            tickets[players[level][i]] = uint32(Utils.random(
                1000000,
                1999999,
                uint256(keccak256(abi.encodePacked(seed, uint256(uint160(players[level][i])))))
            ));
        }
    }

    /**
     * @notice Generate final numbers as the count of _numberOfWinners, and match ticket numbers
     * @param _level play level
     * @param _numberOfWinners number of target winners
     */
    function playLottery(
        uint256 _level,
        uint256 _numberOfWinners
    )
        external
        override
        onlyOwner
        returns (
            address[] memory,   // winner address, contains duplication
            uint256             // winner count
        )
    {
        require(isLotteryEnabled, "Lottery not enabled");
        require(_numberOfWinners > 0, "Number of winners must be one or more");
        require(players[_level].length >= _numberOfWinners, "Overflow number of winners");

        drawFinalNumbers(_level, _numberOfWinners);

        address[] memory winners = new address[](_numberOfWinners);
        uint256 k;

        for (uint256 j = 0; j < players[_level].length; j++) {
            for (uint256 i = 0; i < _numberOfWinners; i++) {
                require(tickets[players[_level][j]] >= 1000000 && tickets[players[_level][j]] <= 1999999, "Ticket number overflow");
                if (tickets[players[_level][j]] == finalNumbers[_level][i]) {
                    winners[k++] = players[_level][j];
                    break;
                }
            }
        }

        emit LotteryClosed(
            _level,
            _numberOfWinners,
            winners,
            k
        );

        return (winners, k);
    }

    /**
     * @notice Generate random final numbers
     * @param _level play level
     * @param _numberOfWinners number of target winners
     * @dev Callable as private function
     */
    function drawFinalNumbers(
        uint256 _level,
        uint256 _numberOfWinners
    ) private {
        randomGenerator.getRandomNumber(block.timestamp);
        uint256 seed = randomGenerator.viewRandomResult32();

        for (uint256 i = 0; i < _numberOfWinners; i++) {
            finalNumbers[_level].push(uint32(Utils.random(
                1000000,
                1999999,
                uint256(keccak256(abi.encodePacked(seed, players[_level][i])))
            )));
        }
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
