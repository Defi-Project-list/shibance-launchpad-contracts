// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import './interfaces/Pausable.sol';
import './interfaces/IMasterChef.sol';
import './libraries/SafeMath7.sol';

contract IDOVault is Ownable, Pausable, SafeMath7 {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  struct UserInfo {
    uint256 shares; // number of shares for a user
    uint256 xWOOF; // xWOOF balance value
    uint256 lastDepositedTime; // keeps track of deposited time for potential penalty
    uint256 cakeAtLastUserAction; // keeps track of cake deposited at the last user action
    uint256 lastUserActionTime; // keeps track of the last user action time
    uint256 lockTime; // start locking time
    uint256 unlockTime; // end time to be available to unstake
  }

  IERC20 public immutable token; // WOOF token
  IERC20 public immutable receiptToken; // DoggyPound token

  IMasterBoi public immutable masterBoi;

  address[] public users;
  mapping(address => UserInfo) public userInfo; // todo, it must be false

  uint256 public totalShares;
  address public admin;
  address public treasury;
  address public developer;

  uint256 public constant MAX_LOCK_PERIOD = 2 * 365 days; // 2 years

  uint256 public unstakeFee = 100; // 1%
  
  event Stake(address indexed user, uint256 amount, uint256 shares, uint256 lastDepositedTime, uint256 lockTime, uint256 unlockTime);
  event Unstake(address indexed user, uint256 amount, uint256 shares, uint256 leftShares);
  event Restake(address indexed user, uint256 unlockTime);
  event Pause();
  event Unpause();

  modifier onlyAdmin() {
    require(msg.sender == admin, "Admin is required");
    _;
  }

  modifier onlyDeveloper() {
    require(msg.sender == developer, "Developer is required");
    _;
  }

  modifier notContract() {
    require(!_isContract(msg.sender), "Contract not allowed");
    require(msg.sender == tx.origin, "Proxy contract not allowed");
    _;
  }
  
  constructor (IERC20 _token,
      IERC20 _receiptToken,
      IMasterBoi _masterBoi,
      address _admin,
      address _treasury) {
    token = _token;
    receiptToken = _receiptToken;
    masterBoi = _masterBoi;
    admin = _admin;
    treasury = _treasury;

    IERC20(_token).safeApprove(address(_masterBoi), type(uint128).max);
  }

  /**
   * @notice Stake tokens into IDOVault
   * @param _amount: number of tokens to stake (in WOOF)
   * @param _period: locking period
   */
  function stake(uint256 _amount, uint256 _period) external whenNotPaused notContract {
    require(_amount > 0, "Nothing to deposit");

    UserInfo storage user = userInfo[msg.sender];

    require(user.lockTime <= user.unlockTime, "Error in locking time");
    if (user.unlockTime > block.timestamp) {
      require(block.timestamp + _period > user.unlockTime, "Too short locking period from now");
    }

    uint256 pool = balanceOf();
    token.safeTransferFrom(msg.sender, address(this), _amount);

    uint256 currentShares = 0;
    if (totalShares != 0) {
      currentShares = (_amount.mul(totalShares)).div(pool);
    } else {
      currentShares = _amount;
    }

    if (user.shares < 1) { // first stake
      users.push(msg.sender);
    }

    user.shares = user.shares.add(currentShares);
    user.lastDepositedTime = block.timestamp;

    totalShares = totalShares.add(currentShares);

    user.cakeAtLastUserAction = user.shares.mul(balanceOf()).div(totalShares);
    user.lastUserActionTime = block.timestamp;

    if (user.unlockTime < block.timestamp) { // newly staking
      user.lockTime = block.timestamp;
    }
    user.unlockTime = block.timestamp + _period;

    // Calculate xWOOF balance
    // xWOOF = WOOF x Bonus Multiplier, Bonus Multiplier = min(1.0224^Weeks locked, 10)
    // Weeks locked is a continuous number, calculated as unstake date minus current date, divided by 52
    // refer: https://github.com/abdk-consulting/abdk-libraries-solidity
    uint256 weeksLocks = (user.unlockTime - user.lockTime) / (1 days) / 52;
    user.xWOOF = pow7(user.shares, weeksLocks);

    _earn();

    emit Stake(msg.sender, _amount, currentShares, block.timestamp, user.lockTime, user.unlockTime);
  }

  function unstakeAll() external notContract {
    require(userInfo[msg.sender].unlockTime < block.timestamp, "Not available for locked staking");
    this.unstake(userInfo[msg.sender].shares);
  }

  /**
   * @notice Unstake tokens from IDOVault
   * @param _shares: number of shares to withdraw
   */
  function unstake(uint256 _shares) external notContract {
    UserInfo storage user = userInfo[msg.sender];
    require(_shares > 0, "Nothing to withdaw");
    require(_shares <= user.shares, "Withdraw amount exceeds balance");
    require(user.unlockTime < block.timestamp, "Not available for locked staking");

    uint256 currentAmount = (balanceOf().mul(_shares)).div(totalShares);
    user.shares = user.shares.sub(_shares);
    totalShares = totalShares.sub(_shares);

    uint256 bal = available();
    if (bal < currentAmount) {
      uint256 balWithdraw = currentAmount.sub(bal);
      IMasterBoi(masterBoi).leaveStaking(balWithdraw);
      uint256 balAfter = available();
      uint256 diff = balAfter.sub(bal);
      if (diff < balWithdraw) {
        currentAmount = bal.add(diff);
      }
    }

    if (unstakeFee > 0) {
      uint256 currentWithdrawFee = currentAmount.mul(unstakeFee).div(10000);
      token.safeTransfer(treasury, currentWithdrawFee);
      currentAmount = currentAmount.sub(currentWithdrawFee);
    }

    if (user.shares > 0) {
      user.cakeAtLastUserAction = user.shares.mul(balanceOf()).div(totalShares);
    } else { // withdraw all
      user.cakeAtLastUserAction = 0;
    }

    user.lastUserActionTime = block.timestamp;

    token.safeTransfer(msg.sender, currentAmount);

    emit Unstake(msg.sender, currentAmount, _shares, user.shares);
  }

  /**
   * @notice Restake without new amount of tokens
   * @param _period: locking period
   */
  function restake(uint256 _period) external notContract whenNotPaused {
    UserInfo storage user = userInfo[msg.sender];
    require(user.shares > 0, "Empty shares");
    require(block.timestamp + _period > user.unlockTime, "Too short locking period from now");

    user.unlockTime = block.timestamp + _period;

    emit Restake(msg.sender, user.unlockTime);
  }

  /**
   * @notice Withdraw from developer to vault
   * @dev EMERGENCY ONLY, only callable by developer
   */
  function emergencyWithdraw() external onlyDeveloper {
    IMasterBoi(masterBoi).emergencyWithdraw(0);
  }

  /**
   * @notice Triggers stopped state
   * @dev Only possible when contract not paused.
   */
  function pause() external onlyAdmin whenNotPaused {
    _pause();
    emit Pause();
  }

  /**
   * @notice Returns to normal state
   * @dev Only possible when contract is paused.
   */
  function unpause() external onlyAdmin whenPaused {
    _unpause();
    emit Unpause();
  }

  /**
   * @notice Sets admin address
   * @dev Only callable by the contract owner.
   */
  function setAdmin(address _admin) external onlyOwner {
    require(_admin != address(0), "Cannot zero address");
    admin = _admin;
  }

  /**
   * @notice Sets treasury address
   * @dev Only callable by the contract owner.
   */
  function setTreasury(address _treasury) external onlyOwner {
    require(_treasury != address(0), "Cannot be zero address");
    treasury = _treasury;
  }

  /**
   * @notice Sets developer address
   * @dev Only callable by the contract owner.
   */
  function setDeveloper(address _dev) external onlyOwner {
    require(_dev != address(0), "Cannot be zero address");
    developer = _dev;
  }

  /**
   * @notice Sets unstaking fee
   * @dev Only callable by the contract admin
   */
  function setUnstakeFee(uint256 _fee) external onlyAdmin {
    unstakeFee = _fee;
  }

  function getStakeAmount() public view returns (uint256) {
    UserInfo storage user = userInfo[msg.sender];
    // uint256 pricePerFullShare = totalShares == 0 ? 1e18 : balanceOf().mul(1e18).div(totalShares);
    return user.shares * getPricePerFullShare();
  }

  /**
   * @notice Calculate the price per shares
   */
  function getPricePerFullShare() public view returns (uint256) {
    return totalShares == 0 ? 1e18 : balanceOf().mul(1e18).div(totalShares);
  }

  /**
    * @notice Custom logic for how much the vault allows to be borrowed
    * @dev The contract puts 100% of the tokens to work.
    */
  function available() public view returns (uint256) {
    return token.balanceOf(address(this));
  }

  /**
    * @notice Calculates the total underlying tokens
    * @dev It includes tokens held by the contract and held in MasterChef
    */
  function balanceOf() public view returns (uint256) {
    (uint256 amount, ) = IMasterBoi(masterBoi).userInfo(0, address(this));
    return token.balanceOf(address(this)).add(amount);
  }

  /**
    * @notice Deposits tokens into MasterChef to earn staking rewards
    */
  function _earn() internal {
    uint256 bal = available();
    if (bal > 0) {
      IMasterBoi(masterBoi).enterStaking(bal);
    }
  }

  function getUsers() public view returns (address[] memory) {
    return users;
  }

  function getUserInfo(address _user) public view returns (
    uint256 shares,
    uint256 xWOOF,
    uint256 lastDepositedTime,
    uint256 cakeAtLastUserAction,
    uint256 lastUserActionTime,
    uint256 lockTime,
    uint256 unlockTime
  ) {
    return (
      userInfo[_user].shares,
      userInfo[_user].xWOOF,
      userInfo[_user].lastDepositedTime,
      userInfo[_user].cakeAtLastUserAction,
      userInfo[_user].lastUserActionTime,
      userInfo[_user].lockTime,
      userInfo[_user].unlockTime
    );
  }

  /**
    * @notice Checks if address is a contract
    * @dev It prevents contract from being targetted
    */
  function _isContract(address addr) internal view returns (bool) {
    uint256 size;
    assembly {
      size := extcodesize(addr)
    }
    return size > 0;
  }
}