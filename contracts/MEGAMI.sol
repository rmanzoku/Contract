// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/interfaces/IERC2981.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import "./rarible/royalties/contracts/LibPart.sol";
import "./rarible/royalties/contracts/LibRoyaltiesV2.sol";
import "./rarible/royalties/contracts/RoyaltiesV2.sol";

contract MEGAMI is ERC721, Ownable, ReentrancyGuard, RoyaltiesV2 {
    using Strings for uint256;

    uint256 private _maxSupply = 10000;
    uint256 private _royalty = 1000;
    address private _saleContractAddr;

    uint256 public totalSupply = 0;

    string private constant _baseTokenURI = "ipfs://xxxxx/";

    // Royality management
    address payable public defaultRoyaltiesReceipientAddress;  // This will be set in the constructor
    uint96 public defaultPercentageBasisPoints = 300;  // 3%

    // Withdraw management
    struct feeReceiver { 
        address payable receiver;
        uint96 sharePercentageBasisPoints;
    }
    feeReceiver[] private _feeReceivers;

    constructor ()
    ERC721("MEGAMI", "MEGAMI")
    {
        defaultRoyaltiesReceipientAddress = payable(address(this));
    }

    function setSaleContract(address contractAddr)
        external
        onlyOwner
    {
        _saleContractAddr = contractAddr;
    }

    modifier onlyOwnerORSaleContract()
    {
        require(_saleContractAddr == _msgSender() || owner() == _msgSender(), "Ownable: caller is not the Owner or SaleContract");
        _;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        virtual
        override(ERC721)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev Since MEGAMI isn't minting tokens sequentially, this function scans all of minted tokens and returns unminted tokenIds
     */
    function getUnmintedTokenIds() public view returns (uint256[] memory) {
        uint256[] memory unmintedTokenIds = new uint256[](_maxSupply - totalSupply);
        uint256 unmintedCount = 0;
        for (uint256 i = 0; i < _maxSupply;) {
            if(!_exists(i)) {
                unmintedTokenIds[unmintedCount] = i;
                unchecked { ++unmintedCount; }
            }
            unchecked { ++i; }
        }
        return unmintedTokenIds;
    }

    function mint(uint256 _tokenId, address _address) public onlyOwnerORSaleContract nonReentrant { 
        require(totalSupply <= _maxSupply, "minting limit");
        
        _safeMint(_address, _tokenId);

        totalSupply += 1;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return string(abi.encodePacked(_baseTokenURI, tokenId.toString(), ".json"));
    }

    // Copied from ForgottenRunesWarriorsGuild. Thank you dotta ;)
    /**
     * @dev ERC20s should not be sent to this contract, but if someone
     * does, it's nice to be able to recover them
     * @param token IERC20 the token address
     * @param amount uint256 the amount to send
     */
    function forwardERC20s(IERC20 token, uint256 amount) public onlyOwner {
        require(address(msg.sender) != address(0));
        token.transfer(msg.sender, amount);
    }

    // Royality management
    /**
     * @dev set defaultRoyaltiesReceipientAddress
     * @param _defaultRoyaltiesReceipientAddress address New royality receipient address
     */
    function setDefaultRoyaltiesReceipientAddress(address payable _defaultRoyaltiesReceipientAddress) public onlyOwner {
        defaultRoyaltiesReceipientAddress = _defaultRoyaltiesReceipientAddress;
    }

    /**
     * @dev set defaultPercentageBasisPoints
     * @param _defaultPercentageBasisPoints uint96 New royality percentagy basis points
     */
    function setDefaultPercentageBasisPoints(uint96 _defaultPercentageBasisPoints) public onlyOwner {
        defaultPercentageBasisPoints = _defaultPercentageBasisPoints;
    }

    /**
     * @dev return royality for Rarible
     */
    function getRaribleV2Royalties(uint256) external view override returns (LibPart.Part[] memory) {
        LibPart.Part[] memory _royalties = new LibPart.Part[](1);
        _royalties[0].value = defaultPercentageBasisPoints;
        _royalties[0].account = defaultRoyaltiesReceipientAddress;
        return _royalties;
    }

    /**
     * @dev return royality in EIP-2981 standard
     * @param _salePrice uint256 sales price of the token royality is calculated
     */
    function royaltyInfo(uint256, uint256 _salePrice) external view returns (address receiver, uint256 royaltyAmount) {
        return (defaultRoyaltiesReceipientAddress, (_salePrice * defaultPercentageBasisPoints) / 10000);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        if (interfaceId == LibRoyaltiesV2._INTERFACE_ID_ROYALTIES) {
            return true;
        }
        if (interfaceId == type(IERC2981).interfaceId) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }
    
    // Disable renouncing ownership
    function renounceOwnership() public override onlyOwner {}     

    // Withdraw 
    receive() external payable {}
    fallback() external payable {}

    function setFeeReceivers(feeReceiver[] calldata receivers) external onlyOwner {
        uint256 receiversLength = receivers.length;
        require(receiversLength > 0, "at least one receiver is necessary");
        uint256 totalPercentageBasisPoints = 0;
        delete _feeReceivers;
        for(uint256 i = 0; i < receiversLength;) {
            require(receivers[i].receiver != address(0), "receiver address can't be null");
            require(receivers[i].sharePercentageBasisPoints != 0, "share percentage basis points can't be 0");
            _feeReceivers.push(feeReceiver(receivers[i].receiver, receivers[i].sharePercentageBasisPoints));

            totalPercentageBasisPoints += receivers[i].sharePercentageBasisPoints;

            unchecked { ++i; }
        }
        require(totalPercentageBasisPoints == 10000, "total share percentage basis point isn't 10000");
    }

    function withdraw() public onlyOwner {
        require(_feeReceivers.length != 0, "receivers haven't been specified yet");

        uint256 sendingAmount = address(this).balance;
        uint256 receiversLength = _feeReceivers.length;
        uint256 totalSent = 0;
        if(receiversLength > 1) {
            for(uint256 i = 1; i < receiversLength;) {
                uint256 transferAmount = (sendingAmount * _feeReceivers[i].sharePercentageBasisPoints) / 10000;
                totalSent += transferAmount;
                require(_feeReceivers[i].receiver.send(transferAmount), "transfer failed");

                unchecked { ++i; }
            }
        }

        // Remainder is sent to the first receiver
        require(_feeReceivers[0].receiver.send(sendingAmount - totalSent), "transfer failed");
    }

    /**
     @dev Emergency withdraw. Please use moveFund to megami for regular withdraw
     */
    function emergencyWithdraw() public onlyOwner {
        require(payable(owner()).send(address(this).balance));
    }
}
