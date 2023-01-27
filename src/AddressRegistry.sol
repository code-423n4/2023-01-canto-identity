// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "solmate/tokens/ERC721.sol";

/// @title Address Registry
/// @notice Allows users to register their CID NFT
contract AddressRegistry {
    /*//////////////////////////////////////////////////////////////
                                 ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the CID NFT
    address public immutable cidNFT;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Stores the mappings of users to their CID NFT
    mapping(address => uint256) private cidNFTs;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CIDNFTAdded(address indexed user, uint256 indexed cidNFTID);
    event CIDNFTRemoved(address indexed user, uint256 indexed cidNFTID);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error NFTNotOwnedByUser(uint256 cidNFTID, address caller);
    error NoCIDNFTRegisteredForUser(address caller);

    /// @param _cidNFT Address of the CID NFT contract
    constructor(address _cidNFT) {
        cidNFT = _cidNFT;
    }

    /// @notice Register a CID NFT to the address of the caller. NFT has to be owned by the caller
    /// @dev Will overwrite existing registration if any exists
    function register(uint256 _cidNFTID) external {
        if (ERC721(cidNFT).ownerOf(_cidNFTID) != msg.sender)
            // We only guarantee that a CID NFT is owned by the user at the time of registration
            // ownerOf reverts if non-existing ID is provided
            revert NFTNotOwnedByUser(_cidNFTID, msg.sender);
        cidNFTs[msg.sender] = _cidNFTID;
        emit CIDNFTAdded(msg.sender, _cidNFTID);
    }

    /// @notice Remove the current registration of the caller
    function remove() external {
        uint256 cidNFTID = cidNFTs[msg.sender];
        if (cidNFTID == 0) revert NoCIDNFTRegisteredForUser(msg.sender);
        delete cidNFTs[msg.sender];
        emit CIDNFTRemoved(msg.sender, cidNFTID);
    }

    /// @notice Get the CID NFT ID that is registered for the provided user
    /// @param _user Address to query
    /// @return cidNFTID The registered CID NFT ID. 0 when no CID NFT is registered for the given address
    function getCID(address _user) external view returns (uint256 cidNFTID) {
        cidNFTID = cidNFTs[_user];
    }
}
