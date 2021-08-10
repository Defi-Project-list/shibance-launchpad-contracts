// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import './interfaces/IShibanceLotteryFactory.sol';
import './interfaces/IIDOPool.sol';
import './libraries/Utils.sol';

interface IRandomNumberGenerator {
    /**
     * Requests randomness from a user-provided seed
     */
    function getRandomNumber(uint256 _seed) external;

    /**
     * View latest lotteryId numbers
     */
    function viewLatestLotteryId() external view returns (uint256);

    /**
     * Views random result
     */
    function viewRandomResult() external view returns (uint32);
}

contract ShibanceLotteryFactory is ReentrancyGuard, IShibanceLotteryFactory, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public operatorAddress;
    address public lotteryFeeAddress;

    IRandomNumberGenerator public randomGenerator;

    enum Status {
        Pending,
        Open,
        Close,
        Claimable
    }

    struct Lottery {
        address idoPool; // address for IDOPool contract
        IERC20 allocatedToken;
        uint256 allocatedAmount;
        uint256 lotteryFee; // fee percentage in unit of 10000
        Status status;
        uint256 startTime;
        uint256 endTime;
        uint256 basicMultiplier; // 1x basic
        uint256 premiumMultiplier; // 8x premium
        uint256 eliteMultiplier; // 45x elite
        uint256 ticketCount;
        uint32[5] finalNumbers; // length of final numbers must be same with WINNER_COUNT
        uint256 winningTickets; // number of winning tickets corresponding finalNumbers
    }

    struct Ticket {
        uint32 number;
        address owner;
    }

    // check defined value in IDOPool
    uint256 public constant BASIC_TIER = 1;
    uint256 public constant PREMIUM_TIER = 2;
    uint256 public constant ELITE_TIER = 3;
    uint256 public constant WINNER_COUNT = 5; // number of winners

    // lotteryId => Lottery
    mapping(uint256 => Lottery) public _lotteries; // todo, make it private when deploy on mainnet
    // lotteryId => ticketId[]
    mapping(uint256 => uint256[]) public _lotteryTicketIds; // todo, make it private when deploy on mainnet
    // ticketId => Ticket
    mapping(uint256 => Ticket) public _tickets; // todo, make it private when deploy on mainnet

    // Keeps track of number of ticket per unique combination for each lotteryId, lotteryId => mapping(ticketNumber, repeatCount)
    mapping(uint256 => mapping(uint32 => uint256)) public _numberTicketsPerLotteryId; // todo, make it private when deploy on mainnet

    // Keep track of user ticket ids for a given lotteryId, userAddr => mapping(lotteryId, ticketId)
    mapping(address => mapping(uint256 => uint256[])) public _userTicketIdsPerLotteryId; // todo, make it private when deploy on mainnet
    
    uint256 public currentLotteryId;
    uint256 public currentTicketId;
    
    uint256 public constant MIN_LENGTH_LOTTERY = 4 hours - 5 minutes; // 4 hours
    uint256 public constant MAX_LENGTH_LOTTERY = 4 days + 5 minutes; // 4 days

    modifier notContract() {
        require(!_isContract(msg.sender), "Contract not allowed");
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "Not operator");
        _;
    }

    event GenerateTickets(
        address stakeHolder,
        uint256 lotteryId
    );
    event TicketsClaim(
        address stakeHolder,
        uint256 lotteryId,
        uint256 rewardToTransfer
    );
    event LotteryOpen(
        uint256 indexed lotteryId,
        IERC20 allocatedToken,
        uint256 allocatedAmount,
        uint256 startTime,
        uint256 endTime,
        uint256 basicMultiplier,
        uint256 premiumMultiplier,
        uint256 eliteMultiplier
    );
    event LotteryClose(
        uint256 indexed lotteryId
    );
    event LotteryNumberDrawn(
        uint256 indexed lotteryId,
        uint32 finalNumber1,
        uint32 finalNumber2,
        uint32 finalNumber3,
        uint32 finalNumber4,
        uint32 finalNumber5
    );
    event NewRandomGenerator(address indexed randomGenerator);
    event NewOperatorAndFeeAddress(
        address operatorAddress,
        address lotteryFeeAddress
    );

    constructor(address _randomGenerator) {
        randomGenerator = IRandomNumberGenerator(_randomGenerator);
    }

    /**
     * @notice Generate random generated tickets for current lottery
     * @param _stakeHolder: stake holder address
     * @param _lotteryId: lottery id
     * @dev Callable by IDO master(operator)
     */
    function generateTickets(
        address _stakeHolder,
        uint256 _lotteryId
    )
        external
        override
        nonReentrant
        onlyOperator
    {
        require(_lotteries[_lotteryId].status == Status.Open, "Lottery is not open");
        require(block.timestamp < _lotteries[_lotteryId].endTime, "Lottery is over");

        IIDOPool idoPool = IIDOPool(_lotteries[_lotteryId].idoPool);

        uint256 tierLevel = idoPool.getTierLevel(_stakeHolder);
        uint256 ticketCount = tierLevel == ELITE_TIER ? _lotteries[_lotteryId].eliteMultiplier :
            (tierLevel == PREMIUM_TIER ? _lotteries[_lotteryId].premiumMultiplier :
            (tierLevel == BASIC_TIER ? _lotteries[_lotteryId].basicMultiplier : 0));

        for (uint256 i = 0; i < ticketCount; i++) {
            uint32 ticketNumber = uint32(Utils.random(1000000, 1999999, uint256(keccak256(abi.encodePacked(_stakeHolder, _lotteryId)))));

            _numberTicketsPerLotteryId[_lotteryId][ticketNumber]++;
            _userTicketIdsPerLotteryId[_stakeHolder][_lotteryId].push(currentTicketId);

            _tickets[currentTicketId] = Ticket({number: ticketNumber, owner: _stakeHolder});
            _lotteryTicketIds[_lotteryId].push(currentTicketId);
            currentTicketId++;
        }
        _lotteries[_lotteryId].ticketCount = _lotteries[_lotteryId].ticketCount.add(ticketCount);

        emit GenerateTickets(_stakeHolder, _lotteryId);
    }

    /**
     * @notice Claim a set of winning tickets for a lottery
     * @param _lotteryId: lottery id
     * @dev Callable by users only, not contract!
     */
    function claimTickets(
        uint256 _lotteryId
    )
        external
        override
        notContract
        nonReentrant {
        require(_lotteries[_lotteryId].status == Status.Claimable, "Lottery not claimable");
        require(_userTicketIdsPerLotteryId[msg.sender][_lotteryId].length > 0, "No tickets");

        if (_lotteries[_lotteryId].winningTickets < 1) {
            return;
        }

        uint256 ticketCount = _userTicketIdsPerLotteryId[msg.sender][_lotteryId].length;
        uint256 winningCount;
        for (uint256 i = 0; i < ticketCount; i++) {
            uint256 ticketId = _userTicketIdsPerLotteryId[msg.sender][_lotteryId][i];
            require(msg.sender == _tickets[ticketId].owner, "Not the owner");
            for (uint256 j = 0; j < WINNER_COUNT; j++) {
                if (_tickets[ticketId].number == _lotteries[_lotteryId].finalNumbers[j]) {
                    winningCount++;
                }
            }

            // Update the lottery ticket owner to 0x address
            _tickets[ticketId].owner = address(0);
        }

        uint256 rewardAmount = _lotteries[_lotteryId].allocatedAmount.mul(10000 - _lotteries[_lotteryId].lotteryFee).div(10000);
        uint256 rewardToTransfer = rewardAmount.mul(winningCount).div(_lotteries[_lotteryId].winningTickets);
        _lotteries[_lotteryId].allocatedToken.safeTransfer(msg.sender, rewardToTransfer);

        emit TicketsClaim(msg.sender, _lotteryId, rewardToTransfer);
    }

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
    )
        external
        override
        onlyOperator
        returns (uint256) {
        require(
            ((_endTime - block.timestamp) > MIN_LENGTH_LOTTERY) && ((_endTime - block.timestamp) < MAX_LENGTH_LOTTERY),
            "Lottery length outside of range"
        );

        currentLotteryId++;
        _lotteries[currentLotteryId] = Lottery({
            idoPool: _idoPool,
            allocatedToken: _tokenAddress,
            allocatedAmount: _allocatedAmount,
            lotteryFee: _lotteryFee,
            status: Status.Open,
            startTime: block.timestamp,
            endTime: _endTime,
            basicMultiplier: _basicMultiplier,
            premiumMultiplier: _premiumMultiplier,
            eliteMultiplier: _eliteMultiplier,
            ticketCount: 0,
            finalNumbers: [uint32(0), uint32(0), uint32(0), uint32(0), uint32(0)],
            winningTickets: 0
        });

        // Request a random number from the generator based on a seed
        randomGenerator.getRandomNumber(uint256(keccak256(abi.encodePacked(currentLotteryId, currentTicketId))));

        emit LotteryOpen(
            currentLotteryId,
            _tokenAddress,
            _allocatedAmount,
            block.timestamp,
            _endTime,
            _basicMultiplier,
            _premiumMultiplier,
            _eliteMultiplier
        );
        return currentLotteryId;
    }

    /**
     * @notice Close lottery after project closed
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function closeLottery(
        uint256 _lotteryId
    ) external override onlyOperator nonReentrant {
        require(_lotteries[_lotteryId].status == Status.Open, "Lottery not open");
        require(block.timestamp > _lotteries[_lotteryId].endTime, "Lottery not over");

        // Request a random number from the generator based on a seed
        randomGenerator.getRandomNumber(uint256(keccak256(abi.encodePacked(_lotteryId, currentTicketId))));

        _lotteries[_lotteryId].status = Status.Close;

        emit LotteryClose(_lotteryId);
    }
    
    /**
     * @notice Draw the final number, calculate reward in CAKE per group, and make lottery claimable
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function drawFinalNumberAndMakeLotteryClaimable(uint256 _lotteryId)
        external
        override
        onlyOperator
        nonReentrant {
        require(_lotteries[_lotteryId].status == Status.Close, "Lottery not close");

        for (uint256 i = 0; i < WINNER_COUNT; i++) {
            randomGenerator.getRandomNumber(uint256(keccak256(abi.encodePacked(block.timestamp, currentLotteryId, i))));

            // Calculate the finalNumber based on the randomResult generated by ChainLink's fallback
            uint32 finalNumber = randomGenerator.viewRandomResult();
            _lotteries[_lotteryId].finalNumbers[i] = finalNumber;
        }

        // Count number of winning tickets
        uint256 length = _lotteryTicketIds[_lotteryId].length;
        uint256 winningTickets;
        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = 0; j < WINNER_COUNT; j++) {
                if (_tickets[_lotteryTicketIds[_lotteryId][i]].number == _lotteries[_lotteryId].finalNumbers[j]) {
                    winningTickets++;
                }
            }
        }

        _lotteries[_lotteryId].winningTickets = winningTickets;
        _lotteries[_lotteryId].status = Status.Claimable;

        uint256 feeAmount = _lotteries[_lotteryId].allocatedAmount.mul(_lotteries[_lotteryId].lotteryFee).div(10000);
        _lotteries[_lotteryId].allocatedToken.safeTransfer(lotteryFeeAddress, feeAmount);

        emit LotteryNumberDrawn(
            _lotteryId,
            _lotteries[_lotteryId].finalNumbers[0],
            _lotteries[_lotteryId].finalNumbers[1],
            _lotteries[_lotteryId].finalNumbers[2],
            _lotteries[_lotteryId].finalNumbers[3],
            _lotteries[_lotteryId].finalNumbers[4]
        );
    }

    /**
     * @notice Return last lottery id
     * @dev Callable by RandomGenerator
     */
    function viewLastLotteryId() external override view returns (uint256) {
        return currentLotteryId;
    }

    function viewLottery(uint256 _lotteryId) external view returns (Lottery memory) {
        return _lotteries[_lotteryId];
    }

    /**
     * @notice View user ticket ids, numbers, and statuses of user for a given lottery
     * @param _user: user address
     * @param _lotteryId: lottery id
     * @param _cursor: cursor to start where to retrieve the tickets
     * @param _size: the number of tickets to retrieve
     */
    function viewUserInfoForLotteryId(
        address _user,
        uint256 _lotteryId,
        uint256 _cursor,
        uint256 _size
    )
        external
        view
        returns (
            uint256[] memory,
            uint32[] memory,
            bool[] memory,
            uint256
        )
    {
        uint256 length = _size;
        uint256 numberTicketsBoughtAtLotteryId = _userTicketIdsPerLotteryId[_user][_lotteryId].length;

        if (length > (numberTicketsBoughtAtLotteryId - _cursor)) {
            length = numberTicketsBoughtAtLotteryId - _cursor;
        }

        uint256[] memory lotteryTicketIds = new uint256[](length);
        uint32[] memory ticketNumbers = new uint32[](length);
        bool[] memory ticketStatuses = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            lotteryTicketIds[i] = _userTicketIdsPerLotteryId[_user][_lotteryId][i + _cursor];
            ticketNumbers[i] = _tickets[lotteryTicketIds[i]].number;

            // True = ticket claimed
            if (_tickets[lotteryTicketIds[i]].owner == address(0)) {
                ticketStatuses[i] = true;
            } else {
                // ticket not claimed (includes the ones that cannot be claimed)
                ticketStatuses[i] = false;
            }
        }

        return (lotteryTicketIds, ticketNumbers, ticketStatuses, _cursor + length);
    }

    /**
     * @notice Set operator, fee address
     * @param _operatorAddress operator address
     * @param _lotteryFeeAddress lottery fee address
     * @dev Only callable by owner
     */
    function setOperatorAndFeeAddress(
        address _operatorAddress,
        address _lotteryFeeAddress
    ) external onlyOwner {
        require(_operatorAddress != address(0), "Cannot be zero address");
        require(_lotteryFeeAddress != address(0), "Cannot be zero address");

        operatorAddress = _operatorAddress;
        lotteryFeeAddress = _lotteryFeeAddress;

        emit NewOperatorAndFeeAddress(_operatorAddress, _lotteryFeeAddress);
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
