//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./MEGAMI.sol";

contract MEGAMI_Sale is Ownable {
    using ECDSA for bytes32;

    //DA active variable
    bool public DA_ACTIVE = false; 

    //Starting DA time (seconds). To convert into readable time https://www.unixtimestamp.com/
    uint256 public DA_STARTING_TIMESTAMP;
    uint256 public DA_LENGTH = 48 * 60 * 60; // DA finishes after 48 hours
    uint256 public DA_ENDING_TIMESTAMP;

    // Starting price of DA
    uint256 public DA_STARTING_PRICE_ORIGIN    = 10 ether;
    uint256 public DA_STARTING_PRICE_ALTER     = 5 ether;
    uint256 public DA_STARTING_PRICE_GENERATED = 0.2 ether;

    // Lowest price of DA
    uint256 public DA_ENDING_PRICE = 0.08 ether;

    // Decrease amount every frequency. (Reaches the lowest price after 24 hours)
    uint256 public DA_DECREMENT_ORIGIN    = 0.21 ether; 
    uint256 public DA_DECREMENT_ALTER     = 0.1025 ether;
    uint256 public DA_DECREMENT_GENERATED = 0.0025 ether;

    // Decrement price every 1800 seconds (30 minutes).
    uint256 public DA_DECREMENT_FREQUENCY = 30 * 60;

    // Wave management
    uint256 public TOTAL_WAVE = 10;
    uint256 public TOTAL_SUPPLY = 10000;
    uint256 public WAVE_TIME_INTERVAL = 60 * 60 * 1; // Relese new wave every 1 hour
    uint256 private SUPPLY_PER_WAVE = TOTAL_SUPPLY / TOTAL_WAVE;

    MEGAMI public MEGAMI_TOKEN;

    //ML signer for verification
    address private mlSigner;

    mapping(address => bool) public userToHasMintedPublicML;

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    constructor(address MEGAMIContractAddress){
        MEGAMI_TOKEN = MEGAMI(payable(MEGAMIContractAddress));
    }

    function currentPrice(uint256 tokenId) public view returns (uint256) {
        uint256 currentTimestamp = block.timestamp;
        uint256 wave = getWave(tokenId);
        uint256 waveDAStartedTimestamp = DA_STARTING_TIMESTAMP + (WAVE_TIME_INTERVAL * wave);

        require(
            currentTimestamp >= waveDAStartedTimestamp,
            "DA has not started!"
        );

        //Seconds since we started
        uint256 timeSinceStart = currentTimestamp - waveDAStartedTimestamp;

        //How many decrements should've happened since that time
        uint256 decrementsSinceStart = timeSinceStart / DA_DECREMENT_FREQUENCY;

        //How much eth to remove
        uint256 totalDecrement = decrementsSinceStart * DA_DECREMENT_GENERATED;

        //If how much we want to reduce is greater or equal to the range, return the lowest value
        if (totalDecrement >= DA_STARTING_PRICE_GENERATED - DA_ENDING_PRICE) {
            return DA_ENDING_PRICE;
        }

        //If not, return the starting price minus the decrement.
        return DA_STARTING_PRICE_GENERATED - totalDecrement;
    }

    function getWave(uint256 tokenId) public view returns (uint256) {
        return tokenId / SUPPLY_PER_WAVE;
    }

    function mintDA(bytes calldata signature, uint256 tokenId) public payable callerIsUser {
        require(DA_ACTIVE == true, "DA isnt active");
        
        //Require DA started
        require(
            block.timestamp >= DA_STARTING_TIMESTAMP,
            "DA has not started!"
        );

        require(block.timestamp <= DA_ENDING_TIMESTAMP, "DA is finished");

        uint256 _currentPrice = currentPrice(tokenId);

        require(msg.value >= _currentPrice, "Did not send enough eth.");

        require(
            !userToHasMintedPublicML[msg.sender],
            "Can only mint once during public ML!"
        );

        
        require(
            mlSigner ==
                keccak256(
                    abi.encodePacked(
                        "\x19Ethereum Signed Message:\n32",
                        bytes32(uint256(uint160(msg.sender)))
                    )
                ).recover(signature),
            "Signer address mismatch."
        );

        // WAVE Requires
        require(tokenId <= TOTAL_SUPPLY, "total mint limit");
        require(getWave(tokenId) <= (block.timestamp - DA_STARTING_TIMESTAMP) / WAVE_TIME_INTERVAL, "wave mint yet");

        userToHasMintedPublicML[msg.sender] = true;

        MEGAMI_TOKEN.mint(tokenId, msg.sender);
    }

    function setStart(uint256 startTime) public onlyOwner {
        DA_STARTING_TIMESTAMP = startTime;
        DA_ENDING_TIMESTAMP = DA_STARTING_TIMESTAMP + DA_LENGTH;
    }

    //VARIABLES THAT NEED TO BE SET BEFORE MINT(pls remove comment when uploading to mainet)
    function setSigners(address signer) external onlyOwner {
        mlSigner = signer;
    }

    function setDutchActionActive(bool daActive) public onlyOwner {
        DA_ACTIVE = daActive;
    }
}
