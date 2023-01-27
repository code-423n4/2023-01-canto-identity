// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "solmate/tokens/ERC721.sol";

abstract contract CidSubprotocolNFT is ERC721 {
    bytes4 internal constant CID_SUBPROTOCOL_INTERFACE_ID = type(CidSubprotocolNFT).interfaceId;

    /// @notice Returns if a subprotocol NFT is still active. Subprotocol NFTs may be a pointer to a different entity (e.g., another NFT)
    /// and this entity may no longer exist or may no longer be owned by the owner of the subprotocol NFT, in which case false should be returned.
    /// @dev Has to revert if the given NFT ID does not exist
    /// @param _nftID Subprotocol NFT ID to query
    /// @return active True if the Subprotocol NFT should be considered active
    function isActive(uint256 _nftID) public virtual returns (bool active);

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == CID_SUBPROTOCOL_INTERFACE_ID || super.supportsInterface(interfaceId);
    }
}
