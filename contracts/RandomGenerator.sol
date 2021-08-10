// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "./interfaces/IRandomNumberGenerator.sol";

contract RandomNumberGenerator is VRFConsumerBase, IRandomNumberGenerator, Ownable {

    bytes32 public keyHash;
    bytes32 public latestRequestId;
    uint256 public randomResult;
    uint256 public fee;

    event RequestRandomness(
        bytes32 indexed requestId,
        bytes32 keyHash
    );
    event RequestRandomnessFulfilled(
        bytes32 indexed requestId,
        uint256 randomness
    );

    /**
     * Constructor inherits VRFConsumerBase
     * 
     * Network: Binance testnet
     * Chainlink VRF Coordinator address: 0xa555fC018435bef5A13C6c6870a9d4C11DEC329C
     * LINK token address:                0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06
     * Key Hash: 0xcaf3c3727e033261d383b315559476f48034c13b18f8cafed4d871abe5049186
     */
    constructor(address _vrfCoordinator, address _linkToken) VRFConsumerBase(_vrfCoordinator, _linkToken) {
        keyHash = 0xcaf3c3727e033261d383b315559476f48034c13b18f8cafed4d871abe5049186; // on bsc testnet
        fee = 0.1 * 10 ** 18; // 0.1 LINK
    }

    /** 
     * @notice Requests randomness
     */
    function getRandomNumber() external override {
        require(LINK.balanceOf(address(this)) > fee, "Not enough LINK - fill contract with faucet");
        latestRequestId = requestRandomness(keyHash, fee);
        emit RequestRandomness(latestRequestId, keyHash);
    }

    /**
     * @notice Change the fee
     * @param _fee: new fee (in LINK)
     */
    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    /**
     * @notice Change the keyHash
     * @param _keyHash: new keyHash
     */
    function setKeyHash(bytes32 _keyHash) external onlyOwner {
        keyHash = _keyHash;
    }

    /**
     * @notice View random result
     */
    function viewRandomResult() external view override returns (uint256) {
        return randomResult;
    }

    /**
     * @notice View random result
     */
    function viewRandomResult32() external view override returns (uint32) {
        return uint32(1000000 + (randomResult % 1000000));
    }
    
    /**
     * @notice Callback function used by ChainLink's VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        require(latestRequestId == requestId, "Wrong requestId");
        randomResult = randomness;

        emit RequestRandomnessFulfilled(requestId, randomness);
    }
}