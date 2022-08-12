// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../rarible/royalties/contracts/impl/RoyaltiesV2Impl.sol";
import "../rarible/royalties/contracts/LibRoyaltiesV2.sol";

contract WeAreAllTheSA is ERC721, ERC721Enumerable, RoyaltiesV2Impl {

    using Counters for Counters.Counter;

    address private constant _hdrnFlowAddress = address(0xF447BE386164dADfB5d1e7622613f289F17024D8);
    bytes4  private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
    uint96  private constant _waatsaRoyaltyBasis = 369; // Rarible V2 royalty basis
    string  private constant _hostname = "https://api.icosa.pro/";
    string  private constant _endpoint = "/waatsa/";

    Counters.Counter private _tokenIds;
    address          private _creator;

    constructor() ERC721("We Are All the SA", "WAATSA")
    {
        /* _creator is not an admin key. It is set at contsruction to be a link
           to the parent contract. In this case Hedron */
        _creator = msg.sender;
    }

    function _baseURI(
    )
        internal
        view
        virtual
        override
        returns (string memory)
    {
        string memory chainid = Strings.toString(block.chainid);
        return string(abi.encodePacked(_hostname, chainid, _endpoint));
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    )
        internal
        override(ERC721, ERC721Enumerable) 
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    // Internal NFT Marketplace Glue

    /** @dev Sets the Rarible V2 royalties on a specific token
     *  @param tokenId Unique ID of the HSI NFT token.
     */
    function _setRoyalties(
        uint256 tokenId
    )
        internal
    {
        LibPart.Part[] memory _royalties = new LibPart.Part[](1);
        _royalties[0].value = _waatsaRoyaltyBasis;
        _royalties[0].account = payable(_hdrnFlowAddress);
        _saveRoyalties(tokenId, _royalties);
    }

    function mintStakeNft (address staker)
        external
        returns (uint256)
    {
        require(msg.sender == _creator,
            "WAATSA: NOT ICSA");

        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        _setRoyalties(newTokenId);

        _mint(staker, newTokenId);
        return newTokenId;
    }

    function burnStakeNft (uint256 tokenId)
        external
    {
        require(msg.sender == _creator,
            "WAATSA: NOT ICSA");

        _burn(tokenId);
    }

    // External NFT Marketplace Glue

    /**
     * @dev Implements ERC2981 royalty functionality. We just read the royalty data from
     *      the Rarible V2 implementation. 
     * @param tokenId Unique ID of the HSI NFT token.
     * @param salePrice Price the HSI NFT token was sold for.
     * @return receiver address to send the royalties to as well as the royalty amount.
     */
    function royaltyInfo(
        uint256 tokenId,
        uint256 salePrice
    )
        external
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        LibPart.Part[] memory _royalties = royalties[tokenId];
        
        if (_royalties.length > 0) {
            return (_royalties[0].account, (salePrice * _royalties[0].value) / 10000);
        }

        return (address(0), 0);
    }

    /**
     * @dev returns _hdrnFlowAddress, needed for some NFT marketplaces. This is not
     *       an admin key.
     * @return _hdrnFlowAddress
     */
    function owner(
    )
        external
        pure
        returns (address) 
    {
        return _hdrnFlowAddress;
    }

    /**
     * @dev Adds Rarible V2 and ERC2981 interface support.
     * @param interfaceId Unique contract interface identifier.
     * @return True if the interface is supported, false if not.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        if (interfaceId == LibRoyaltiesV2._INTERFACE_ID_ROYALTIES) {
            return true;
        }

        if (interfaceId == _INTERFACE_ID_ERC2981) {
            return true;
        }

        return super.supportsInterface(interfaceId);
    }

}