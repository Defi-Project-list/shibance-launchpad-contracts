// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import './interfaces/IIDOPool.sol';

contract IDOPool is IIDOPool, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    enum Status {
        Pending,
        Open,
        Close,
        Claimable
    }

    uint256 public constant BASIC_TIER = 1;
    uint256 public constant PREMIUM_TIER = 2;
    uint256 public constant ELITE_TIER = 3;

    IERC20 public stakeToken;
    IERC20 public rewardToken;
    uint256 public decimals;
    uint256 public startTimestamp;
    uint256 public closeTimestamp;
    uint256 public startClaimTimestamp;
    uint256 public minStakeTokens; // minimum amount to stake stakeToken
    uint256 public maxStakeTokens; // maximum amount to stake stakeToken
    uint256 public xWoofForBasic;
    uint256 public xWoofForPremium;
    uint256 public xWoofForElite;

    uint256 public currentTotalStake; // total amount of staked stakeToken
    Status public status; // status of this IDO project
    
    struct StakeHolder {
        uint stakeAmount;
        uint withdrawAmount;
        uint xWoof;
    }
    
    mapping(address => StakeHolder) public holders;

    event TokenStaked(
        address indexed holder,
        uint256 amount,
        uint256 xWoof
    );

    event TokenWithdraw(
        address indexed holder,
        uint256 amount
    );

    modifier guardMaxTokenLimit(uint256 amount) {
        require(amount >= minStakeTokens, "Less than minimum amount");
        uint256 stakedAmount = currentTotalStake.add(amount);
        require(stakedAmount <= maxStakeTokens, "Exceed the limit of staking amount");
        _;
    }

    modifier notLocked() {
        require(block.timestamp > startClaimTimestamp, "Timelock is not unlocked yet");
        _;
    }

    constructor(
        IERC20 _stakeToken,
        IERC20 _rewardToken,
        uint256 _startTimestamp,
        uint256 _closeTimestamp,
        uint256 _startClaimTimestamp,
        uint256 _minStakeTokens,
        uint256 _maxStakeTokens,
        uint256 _xWoofForBasic,
        uint256 _xWoofForPremium,
        uint256 _xWoofForElite
    ) {
        stakeToken = _stakeToken;
        rewardToken = _rewardToken;

        require(_startTimestamp < _closeTimestamp,
            "Start timestamp must be less than finish timestamp");
        require(_closeTimestamp > block.timestamp,
            "Finish timestamp must be more than current block");

        startTimestamp = _startTimestamp;
        closeTimestamp = _closeTimestamp;
        startClaimTimestamp = _startClaimTimestamp;
        minStakeTokens = _minStakeTokens;
        maxStakeTokens = _maxStakeTokens;

        require(_xWoofForBasic < _xWoofForPremium && _xWoofForPremium < _xWoofForElite,
            "Error Tier requirements");
        xWoofForBasic = _xWoofForBasic;
        xWoofForPremium = _xWoofForPremium;
        xWoofForElite = _xWoofForElite;
    }

    /**
     * @notice stake tokens and get xWoof value
     * @param _amountToStake amount of stakeToken
     * @dev Callable by user
     */
    function stakeTokens(
        uint256 _amountToStake
    )
        external
        override
        nonReentrant
        guardMaxTokenLimit(_amountToStake) {
        require(block.timestamp >= startTimestamp, "Not started");
        require(block.timestamp < closeTimestamp, "Already ended");
        require(block.timestamp < startClaimTimestamp, "Now is claiming");

        if (_amountToStake < 1) {
            return;
        }

        StakeHolder storage stakeHolder = holders[msg.sender];

        stakeToken.safeTransferFrom(msg.sender, address(this), _amountToStake);
        stakeHolder.stakeAmount = stakeHolder.stakeAmount.add(_amountToStake);
        currentTotalStake = currentTotalStake.add(_amountToStake);
        stakeHolder.xWoof = stakeHolder.xWoof.add(_amountToStake); // todo import xWoof calculation formula
        
        emit TokenStaked(
            msg.sender,
            _amountToStake,
            stakeHolder.xWoof
        );
    }

    /**
     * @notice withdraw all the staked token
     * @dev Callable by user
     */
    function withdrawStake()
        external
        override
        notLocked
        nonReentrant {
        StakeHolder storage stakeHolder = holders[msg.sender];

        stakeToken.safeTransfer(msg.sender, stakeHolder.stakeAmount);
        stakeHolder.withdrawAmount = stakeHolder.stakeAmount;

        emit TokenWithdraw(
            msg.sender,
            stakeHolder.stakeAmount
        );
    }

    /**
     * @notice return tier level per stake holer
     * @param stakeHolder stake holder address
     */
    function getTierLevel(
        address stakeHolder
    )
        external
        override
        view
        returns (uint256) {
        if (holders[stakeHolder].xWoof < xWoofForBasic) {
            return 0;
        }
        if (holders[stakeHolder].xWoof < xWoofForPremium) {
            return BASIC_TIER;
        }
        if (holders[stakeHolder].xWoof < xWoofForElite) {
            return PREMIUM_TIER;
        }
        return ELITE_TIER;
    }
}