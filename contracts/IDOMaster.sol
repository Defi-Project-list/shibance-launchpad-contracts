// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IDOPool.sol";
import "./interfaces/IShibanceLotteryFactory.sol";

contract IDOMaster is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IShibanceLotteryFactory public lotteryFactory;
    
    uint256 basicMultiplier;
    uint256 premiumMultiplier;
    uint256 eliteMultiplier;
    uint256 public royalPercent = 1000; // 10%
    uint256 public divinePercent = 4000; // 40%

    uint256 public xWoofForBasic;
    uint256 public xWoofForPremium;
    uint256 public xWoofForElite;
    uint256 public xWoofForRoyal;
    uint256 public xWoofForDivine;

    mapping(address => uint256) pool2Lottery;

    event IDOCreated(
        address owner,
        address idoPool,
        IERC20 stakeToken,
        IERC20 rewardToken,
        uint256 startTimestamp,
        uint256 closeTimestamp,
        uint256 startClainTimestamp,
        uint256 minStakeTokens,
        uint256 maxStakeTokens,
        uint256 xWoofForBasic,
        uint256 xWoofForPremium,
        uint256 xWoofForElite
    );

    constructor(
        address _lotteryFactory,
        uint256 _xWoofForBasic,
        uint256 _xWoofForPremium,
        uint256 _xWoofForElite,
        uint256 _xWoofForRoyal,
        uint256 _xWoofForDivine,
        uint256 _basicMultiplier,
        uint256 _premiumMultiplier,
        uint256 _eliteMultiplier,
        uint256 _royalPercent,
        uint256 _divinePercent) {

        lotteryFactory = IShibanceLotteryFactory(_lotteryFactory);
        xWoofForBasic = xWoofForBasic;
        xWoofForPremium = _xWoofForPremium;
        xWoofForElite = _xWoofForElite;
        xWoofForRoyal = _xWoofForRoyal;
        xWoofForDivine = _xWoofForDivine;

        basicMultiplier = _basicMultiplier;
        premiumMultiplier = _premiumMultiplier;
        eliteMultiplier = _eliteMultiplier;
        royalPercent = _royalPercent;
        divinePercent = _divinePercent;
    }

    function createIDO(
        IERC20 _stakeToken,
        IERC20 _rewardToken,
        uint256 _startTimestamp,
        uint256 _closeTimestamp,
        uint256 _startClaimTimestamp,
        uint256 _minStakeTokens,
        uint256 _maxStakeTokens
    )
        external {
        IDOPool idoPool =
            new IDOPool(
                _stakeToken,
                _rewardToken,
                _startTimestamp,
                _closeTimestamp,
                _startClaimTimestamp,
                _minStakeTokens,
                _maxStakeTokens,
                xWoofForBasic,
                xWoofForPremium,
                xWoofForElite
            );
        idoPool.transferOwnership(msg.sender);
        _rewardToken.safeTransferFrom(
            msg.sender,
            address(idoPool),
            _maxStakeTokens
        );

        uint256 amountToLottery = _maxStakeTokens.mul(10000 - royalPercent.add(divinePercent)).div(10000);
        uint256 lotteryId = lotteryFactory.startLottery(
            address(idoPool),
            _rewardToken,
            amountToLottery,
            _startClaimTimestamp,
            basicMultiplier,
            premiumMultiplier,
            eliteMultiplier,
            0 // lottery fee from thereum
        );

        pool2Lottery[address(idoPool)] = lotteryId;

        emit IDOCreated(
            msg.sender,
            address(idoPool),
            _stakeToken,
            _rewardToken,
            _startTimestamp,
            _closeTimestamp,
            _startClaimTimestamp,
            _minStakeTokens,
            _maxStakeTokens,
            xWoofForBasic, xWoofForPremium, xWoofForElite);
    }
}