// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "./SubprotocolRegistry.sol";

/// @title Canto Identity Protocol NFT
/// @notice CID NFTs are at the heart of the CID protocol. All key/values of subprotocols are associated with them.
contract CidNFT is ERC721, ERC721TokenReceiver {
    /*//////////////////////////////////////////////////////////////
                                 CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fee (in BPS) that is charged for every mint (as a percentage of the mint fee). Fixed at 10%.
    uint256 public constant CID_FEE_BPS = 1_000;

    /*//////////////////////////////////////////////////////////////
                                 ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice Wallet that receives CID fees
    address public immutable cidFeeWallet;

    /// @notice Reference to the NOTE TOKEN
    ERC20 public immutable note;

    /// @notice Reference to the subprotocol registry
    SubprotocolRegistry public immutable subprotocolRegistry;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Base URI of the NFT
    string public baseURI;

    /// @notice Array of uint256 values (NFT IDs) with additional position information NFT ID => (array pos. + 1)
    struct IndexedArray {
        uint256[] values;
        mapping(uint256 => uint256) positions;
    }

    /// @notice Data that is associated with a CID NFT -> subprotocol combination
    struct SubprotocolData {
        /// @notice Mapping for ordered type
        mapping(uint256 => uint256) ordered;
        /// @notice Value for primary type
        uint256 primary;
        /// @notice List for active type
        IndexedArray active;
    }

    /// @notice The different types of associations between CID NFTs and subprotocol NFTs
    enum AssociationType {
        /// @notice key => NFT mapping
        ORDERED,
        /// @notice Zero or one NFT
        PRIMARY,
        /// @notice List of NFTs
        ACTIVE
    }

    /// @notice Counter of the minted NFTs
    /// @dev Used to assign a new unique ID. The first ID that is assigned is 1, ID 0 is never minted.
    uint256 public numMinted;

    /// @notice Stores the references to subprotocol NFTs. Mapping nftID => subprotocol name => subprotocol data
    mapping(uint256 => mapping(string => SubprotocolData)) internal cidData;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event OrderedDataAdded(
        uint256 indexed cidNFTID,
        string indexed subprotocolName,
        uint256 indexed key,
        uint256 subprotocolNFTID
    );
    event PrimaryDataAdded(uint256 indexed cidNFTID, string indexed subprotocolName, uint256 subprotocolNFTID);
    event ActiveDataAdded(
        uint256 indexed cidNFTID,
        string indexed subprotocolName,
        uint256 subprotocolNFTID,
        uint256 arrayIndex
    );
    event OrderedDataRemoved(
        uint256 indexed cidNFTID,
        string indexed subprotocolName,
        uint256 indexed key,
        uint256 subprotocolNFTID
    );
    event PrimaryDataRemoved(uint256 indexed cidNFTID, string indexed subprotocolName, uint256 subprotocolNFTID);
    event ActiveDataRemoved(uint256 indexed cidNFTID, string indexed subprotocolName, uint256 subprotocolNFTID);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error TokenNotMinted(uint256 tokenID);
    error AddCallAfterMintingFailed(uint256 index);
    error SubprotocolDoesNotExist(string subprotocolName);
    error NFTIDZeroDisallowedForSubprotocols();
    error AssociationTypeNotSupportedForSubprotocol(AssociationType associationType, string subprotocolName);
    error NotAuthorizedForCIDNFT(address caller, uint256 cidNFTID, address cidNFTOwner);
    error NotAuthorizedForSubprotocolNFT(address caller, uint256 subprotocolNFTID);
    error ActiveArrayAlreadyContainsID(uint256 cidNFTID, string subprotocolName, uint256 nftIDToAdd);
    error OrderedValueNotSet(uint256 cidNFTID, string subprotocolName, uint256 key);
    error PrimaryValueNotSet(uint256 cidNFTID, string subprotocolName);
    error ActiveArrayDoesNotContainID(uint256 cidNFTID, string subprotocolName, uint256 nftIDToRemove);

    /// @notice Sets the name, symbol, baseURI, and the address of the auction factory
    /// @param _name Name of the NFT
    /// @param _symbol Symbol of the NFT
    /// @param _baseURI NFT base URI. {id}.json is appended to this URI
    /// @param _cidFeeWallet Address of the wallet that receives the fees
    /// @param _noteContract Address of the $NOTE contract
    /// @param _subprotocolRegistry Address of the subprotocol registry
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        address _cidFeeWallet,
        address _noteContract,
        address _subprotocolRegistry
    ) ERC721(_name, _symbol) {
        baseURI = _baseURI;
        cidFeeWallet = _cidFeeWallet;
        note = ERC20(_noteContract);
        subprotocolRegistry = SubprotocolRegistry(_subprotocolRegistry);
    }

    /// @notice Get the token URI for the provided ID
    /// @param _id ID to retrieve the URI for
    /// @return tokenURI The URI of the queried token (path to a JSON file)
    function tokenURI(uint256 _id) public view override returns (string memory) {
        if (ownerOf[_id] == address(0))
            // According to ERC721, this revert for non-existing tokens is required
            revert TokenNotMinted(_id);
        return string(abi.encodePacked(baseURI, _id, ".json"));
    }

    /// @notice Mint a new CID NFT
    /// @dev An address can mint multiple CID NFTs, but it can only set one as associated with it in the AddressRegistry
    /// @param _addList An optional list of encoded parameters for add to add subprotocol NFTs directly after minting.
    /// The parameters should not include the function selector itself, the function select for add is always prepended.
    function mint(bytes[] calldata _addList) external {
        _mint(msg.sender, ++numMinted); // We do not use _safeMint here on purpose. If a contract calls this method, he expects to get an NFT back
        bytes4 addSelector = this.add.selector;
        for (uint256 i = 0; i < _addList.length; ++i) {
            (
                bool success, /*bytes memory result*/

            ) = address(this).delegatecall(abi.encodePacked(addSelector, _addList[i]));
            if (!success) revert AddCallAfterMintingFailed(i);
        }
    }

    /// @notice Add a new entry for the given subprotocol to the provided CID NFT
    /// @param _cidNFTID ID of the CID NFT to add the data to
    /// @param _subprotocolName Name of the subprotocol where the data will be added. Has to exist.
    /// @param _key Key to set. This value is only relevant for the AssociationType ORDERED (where a mapping int => nft ID is stored)
    /// @param _nftIDToAdd The ID of the NFT to add
    /// @param _type Association type (see AssociationType struct) to use for this data
    function add(
        uint256 _cidNFTID,
        string calldata _subprotocolName,
        uint256 _key,
        uint256 _nftIDToAdd,
        AssociationType _type
    ) external {
        SubprotocolRegistry.SubprotocolData memory subprotocolData = subprotocolRegistry.getSubprotocol(
            _subprotocolName
        );
        address subprotocolOwner = subprotocolData.owner;
        if (subprotocolOwner == address(0)) revert SubprotocolDoesNotExist(_subprotocolName);
        address cidNFTOwner = ownerOf[_cidNFTID];
        if (
            cidNFTOwner != msg.sender &&
            getApproved[_cidNFTID] != msg.sender &&
            !isApprovedForAll[cidNFTOwner][msg.sender]
        ) revert NotAuthorizedForCIDNFT(msg.sender, _cidNFTID, cidNFTOwner);
        if (_nftIDToAdd == 0) revert NFTIDZeroDisallowedForSubprotocols(); // ID 0 is disallowed in subprotocols

        // The CID Protocol safeguards the NFTs of subprotocols. Note that these NFTs are usually pointers to other data / NFTs (e.g., to an image NFT for profile pictures)
        ERC721 nftToAdd = ERC721(subprotocolData.nftAddress);
        nftToAdd.safeTransferFrom(msg.sender, address(this), _nftIDToAdd);
        // Charge fee (subprotocol & CID fee) if configured
        uint96 subprotocolFee = subprotocolData.fee;
        if (subprotocolFee != 0) {
            uint256 cidFee = (subprotocolFee * CID_FEE_BPS) / 10_000;
            SafeTransferLib.safeTransferFrom(note, msg.sender, cidFeeWallet, cidFee);
            SafeTransferLib.safeTransferFrom(note, msg.sender, subprotocolOwner, subprotocolFee - cidFee);
        }
        if (_type == AssociationType.ORDERED) {
            if (!subprotocolData.ordered) revert AssociationTypeNotSupportedForSubprotocol(_type, _subprotocolName);
            if (cidData[_cidNFTID][_subprotocolName].ordered[_key] != 0) {
                // Remove to ensure that user gets NFT back
                remove(_cidNFTID, _subprotocolName, _key, 0, _type);
            }
            cidData[_cidNFTID][_subprotocolName].ordered[_key] = _nftIDToAdd;
            emit OrderedDataAdded(_cidNFTID, _subprotocolName, _key, _nftIDToAdd);
        } else if (_type == AssociationType.PRIMARY) {
            if (!subprotocolData.primary) revert AssociationTypeNotSupportedForSubprotocol(_type, _subprotocolName);
            if (cidData[_cidNFTID][_subprotocolName].primary != 0) {
                // Remove to ensure that user gets NFT back
                remove(_cidNFTID, _subprotocolName, 0, 0, _type);
            }
            cidData[_cidNFTID][_subprotocolName].primary = _nftIDToAdd;
            emit PrimaryDataAdded(_cidNFTID, _subprotocolName, _nftIDToAdd);
        } else if (_type == AssociationType.ACTIVE) {
            if (!subprotocolData.active) revert AssociationTypeNotSupportedForSubprotocol(_type, _subprotocolName);
            IndexedArray storage activeData = cidData[_cidNFTID][_subprotocolName].active;
            uint256 lengthBeforeAddition = activeData.values.length;
            if (lengthBeforeAddition == 0) {
                uint256[] memory nftIDsToAdd = new uint256[](1);
                nftIDsToAdd[0] = _nftIDToAdd;
                activeData.values = nftIDsToAdd;
                activeData.positions[_nftIDToAdd] = 1; // Array index + 1
            } else {
                // Check for duplicates
                if (activeData.positions[_nftIDToAdd] != 0)
                    revert ActiveArrayAlreadyContainsID(_cidNFTID, _subprotocolName, _nftIDToAdd);
                activeData.values.push(_nftIDToAdd);
                activeData.positions[_nftIDToAdd] = lengthBeforeAddition + 1;
            }
            emit ActiveDataAdded(_cidNFTID, _subprotocolName, _nftIDToAdd, lengthBeforeAddition);
        }
    }

    /// @notice Remove / unset a key for the given CID NFT and subprotocol
    /// @param _cidNFTID ID of the CID NFT to remove the data from
    /// @param _subprotocolName Name of the subprotocol where the data will be removed. Has to exist.
    /// @param _key Key to unset. This value is only relevant for the AssociationType ORDERED
    /// @param _nftIDToRemove The ID of the NFT to remove. Only needed for the AssociationType ACTIVE
    /// @param _type Association type (see AssociationType struct) to remove this data from
    function remove(
        uint256 _cidNFTID,
        string calldata _subprotocolName,
        uint256 _key,
        uint256 _nftIDToRemove,
        AssociationType _type
    ) public {
        SubprotocolRegistry.SubprotocolData memory subprotocolData = subprotocolRegistry.getSubprotocol(
            _subprotocolName
        );
        address subprotocolOwner = subprotocolData.owner;
        if (subprotocolOwner == address(0)) revert SubprotocolDoesNotExist(_subprotocolName);
        address cidNFTOwner = ownerOf[_cidNFTID];
        if (
            cidNFTOwner != msg.sender &&
            getApproved[_cidNFTID] != msg.sender &&
            !isApprovedForAll[cidNFTOwner][msg.sender]
        ) revert NotAuthorizedForCIDNFT(msg.sender, _cidNFTID, cidNFTOwner);

        ERC721 nftToRemove = ERC721(subprotocolData.nftAddress);
        if (_type == AssociationType.ORDERED) {
            // We do not have to check if ordered is supported by the subprotocol. If not, the value will not be unset (which is checked below)
            uint256 currNFTID = cidData[_cidNFTID][_subprotocolName].ordered[_key];
            if (currNFTID == 0)
                // This check is technically not necessary (because the NFT transfer would fail), but we include it to have more meaningful errors
                revert OrderedValueNotSet(_cidNFTID, _subprotocolName, _key);
            delete cidData[_cidNFTID][_subprotocolName].ordered[_key];
            nftToRemove.safeTransferFrom(address(this), msg.sender, currNFTID);
            emit OrderedDataRemoved(_cidNFTID, _subprotocolName, _key, _nftIDToRemove);
        } else if (_type == AssociationType.PRIMARY) {
            uint256 currNFTID = cidData[_cidNFTID][_subprotocolName].primary;
            if (currNFTID == 0) revert PrimaryValueNotSet(_cidNFTID, _subprotocolName);
            delete cidData[_cidNFTID][_subprotocolName].primary;
            nftToRemove.safeTransferFrom(address(this), msg.sender, currNFTID);
            emit PrimaryDataRemoved(_cidNFTID, _subprotocolName, _nftIDToRemove);
        } else if (_type == AssociationType.ACTIVE) {
            IndexedArray storage activeData = cidData[_cidNFTID][_subprotocolName].active;
            uint256 arrayPosition = activeData.positions[_nftIDToRemove]; // Index + 1, 0 if non-existant
            if (arrayPosition == 0) revert ActiveArrayDoesNotContainID(_cidNFTID, _subprotocolName, _nftIDToRemove);
            uint256 arrayLength = activeData.values.length;
            // Swap only necessary if not already the last element
            if (arrayPosition != arrayLength) {
                uint256 befSwapLastNFTID = activeData.values[arrayLength - 1];
                activeData.values[arrayPosition - 1] = befSwapLastNFTID;
                activeData.positions[befSwapLastNFTID] = arrayPosition;
            }
            activeData.values.pop();
            activeData.positions[_nftIDToRemove] = 0;
            nftToRemove.safeTransferFrom(address(this), msg.sender, _nftIDToRemove);
            emit ActiveDataRemoved(_cidNFTID, _subprotocolName, _nftIDToRemove);
        }
    }

    /// @notice Get the ordered data that is associated with a CID NFT / Subprotocol
    /// @param _cidNFTID ID of the CID NFT to query
    /// @param _subprotocolName Name of the subprotocol to query
    /// @param _key Key to query
    /// @return subprotocolNFTID The ID of the NFT at the queried key. 0 if it does not exist
    function getOrderedData(
        uint256 _cidNFTID,
        string calldata _subprotocolName,
        uint256 _key
    ) external view returns (uint256 subprotocolNFTID) {
        subprotocolNFTID = cidData[_cidNFTID][_subprotocolName].ordered[_key];
    }

    /// @notice Get the primary data that is associated with a CID NFT / Subprotocol
    /// @param _cidNFTID ID of the CID NFT to query
    /// @param _subprotocolName Name of the subprotocol to query
    /// @return subprotocolNFTID The ID of the primary NFT at the queried subprotocl / CID NFT. 0 if it does not exist
    function getPrimaryData(uint256 _cidNFTID, string calldata _subprotocolName)
        external
        view
        returns (uint256 subprotocolNFTID)
    {
        subprotocolNFTID = cidData[_cidNFTID][_subprotocolName].primary;
    }

    /// @notice Get the active data list that is associated with a CID NFT / Subprotocol
    /// @param _cidNFTID ID of the CID NFT to query
    /// @param _subprotocolName Name of the subprotocol to query
    /// @return subprotocolNFTIDs The ID of the primary NFT at the queried subprotocl / CID NFT. 0 if it does not exist
    function getActiveData(uint256 _cidNFTID, string calldata _subprotocolName)
        external
        view
        returns (uint256[] memory subprotocolNFTIDs)
    {
        subprotocolNFTIDs = cidData[_cidNFTID][_subprotocolName].active.values;
    }

    /// @notice Check if a provided NFT ID is included in the active data list that is associated with a CID NFT / Subprotocol
    /// @param _cidNFTID ID of the CID NFT to query
    /// @param _subprotocolName Name of the subprotocol to query
    /// @return nftIncluded True if the NFT ID is in the list
    function activeDataIncludesNFT(
        uint256 _cidNFTID,
        string calldata _subprotocolName,
        uint256 _nftIDToCheck
    ) external view returns (bool nftIncluded) {
        nftIncluded = cidData[_cidNFTID][_subprotocolName].active.positions[_nftIDToCheck] != 0;
    }

    function onERC721Received(
        address, /*operator*/
        address, /*from*/
        uint256, /*id*/
        bytes calldata /*data*/
    ) external pure returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}
