# Canto Identity Protocol contest details
- Total Prize Pool: $36,500 worth of CANTO
  - HM awards: $25,500 worth of CANTO
  - QA report awards: $3,000 worth of CANTO 
  - Gas report awards: $1,500 worth of CANTO
  - Judge + presort awards: $6,000 worth of CANTO
  - Scout awards: $500 USDC 
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2023-01-canto-identity-protocol-contest/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts January 31, 2023 20:00 UTC
- Ends February 3, 2023 20:00 UTC

## Automated Findings / Publicly Known Issues

Automated findings output for the contest can be found [here](https://gist.github.com/Picodes/a6ca8ab593a9d1fbfc322815bec08069) within an hour of contest opening.

*Note for C4 wardens: Anything included in the automated findings output is considered a publicly known issue and is ineligible for awards.*

The following list contains some deliberate design decisions/known edge cases for **Canto Identity Protocol (CID)**:
- Front-running of `SubprotocolRegistry.register` calls: In theory, someone can front-run a call to `SubprotocolRegistry.register` with the same name, causing the original call to fail. There is a registration fee (100 $NOTE) and the damage is very limited (original registration call fails, user can just re-register under a different name), so this attack is not deemed feasible.
- String confusions: Subprotocols are identified by a string and there are multiple ways to encode the same human-readable string. It is the responsibility of the developer that integrates with CID to ensure that he queries the correct string.
- The ID 0 is disallowed on purpose in subprotocols. Subprotocols will be specifically developed for CID, so this is an interface that developers must adhere to and does not limit CID in any way.
- Usage of `_mint` instead of `_safeMint`: Because we always mint to `msg.sender`, any smart contract that calls `mint` expects to get a NFT back. Therefore, this check can be saved there.
- EIP165 checks for subprotocol NFTs: We check if a registered subprotocol NFT supports the `SubprotocolNFT` interface to prevent mistakes by the user. Of course, this does not guarantee in any way that a subprotocol NFT is non-malicious or really implements the interface. Because CID is a permissionless protocol, this has to be checked by the user when interacting with a particular subprotocol NFT.
- Transferring CID NFTs that are still referenced in the address registry: CID NFTs are transferrable on purpose and a user can transfer his CID NFT while it is still registered to his address if he wants to do so.
- Gas optimizations: Some of the checks that are performed are technically not necessary, because the contract would revert in some other place without the check. However, explicitness and clear errors are preferred in these cases over the (small) gas savings

## Overview

**[Code Walkthrough Video](https://www.youtube.com/watch?v=k10DKImulZs)**

Canto Identity Protocol (CID) is a permissionless protocol that reinvents the concept of on-chain identity. With CID, the power to control one's on-chain identity is returned to users.
Within Canto Identity Protocol, ERC721 NFTs called cidNFTs represent individual on-chain identities. Users can mint CID NFTs for free by calling the `mint` method on CidNFT.sol.
Users must register a CID NFT as their canonical on-chain identity with the `AddressRegistry`.

### Canto Identity NFTs (`CidNFT.sol`)
Canto Identity NFTs (CID NFTs) represent individual on-chain identities. Through nested mappings, they point to subprotocolNFTs representing individual identity traits.

Users can add pointers to subprotocol NFTs to their CID NFTs by calling the `add` function on `CidNFT`. There are three different association types (ordered, primary, active) that can be used to model different types of associations between the CID NFT and subprotocol NFTs (depending on if this was allowed when registering the subprotocol). They can remove pointers to subprotocolNFTs from their cidNFTs by calling the `remove` function on `CidNFT` with the same inputs.

### Address Registry (`AddressRegistry.sol`)
Users associate a CID NFT with their address in the address registry. They can always remove the registration and register a new CID NFT.

### Subprotocol Registry (`SubprotocolRegistry.sol`)
Subprotocols must be registered with `SubprotocolRegistry` for a one-time fee in order to be used within Canto Identity Protocol. When registering, a user defines the allowed association types and an optional fee that is charged when adding the subprotocol to a CID NFT. Note that the association types are not mutually exclusive. In the usual case, most users will define one association types, but this is not restricted for the greatest flexibility.

### Subprotocols (out-of-scope)
The core Canto Identity Protocol has no notion of identity traits, such as display name. Instead, it provides a standardized interface (`CidSubprotocolNFT`) for granular, trait-specific identity protocols called Subprotocols.

Subprotocol creation is permissionless. However, they must be registered with `SubprotocolRegistry` for a one-time fee in order to be used within Canto Identity Protocol.

Note that subprotocols itself are not part of this contest.

## Scope

### Scope Table

| Contract | SLOC | Purpose | Libraries used |  
| ----------- | ----------- | ----------- | ----------- |
| [src/CidNFT.sol](https://github.com/code-423n4/2023-01-canto-identity/blob/main/src/CidNFT.sol) | 231 | The Canto Identity Protocol NFT. The NFTs of different subprotocols are associated with a CID NFT. There are different types for this association and it can be configured when registering a subprotocol which types are allowed. | [`solmate/*`](https://github.com/transmissions11/solmate) |
| [src/SubprotocolRegistry.sol](https://github.com/code-423n4/2023-01-canto-identity/blob/main/src/SubprotocolRegistry.sol) | 61 | Users have to register a subprotocol in the registry such that it can be added to a CID NFT. Typically, this will be done by the creator of a subprotocol, but this is no hard requirement. | [`solmate/*`](https://github.com/transmissions11/solmate) |
| [src/AddressRegistry.sol](https://github.com/code-423n4/2023-01-canto-identity/blob/main/src/AddressRegistry.sol) | 28 | Allows users to register their CID NFT and associate it with their address. | [`solmate/*`](https://github.com/transmissions11/solmate) |

### Out of Scope

| Contract | SLOC | Purpose | Libraries used |  
| ----------- | ----------- | ----------- | ----------- |
| [src/CidSubprotocolNFT.sol](https://github.com/code-423n4/2023-01-canto-identity/blob/main/src/CidSubprotocolNFT.sol) | 28 | This abstract contract will be the base for subprotocol NFTs that developers can use to build new subprotocols. Subprotocols are not part of this contest and this interface may be changed slightly. The file is still included for the sake of completeness. | [`solmate/*`](https://github.com/transmissions11/solmate) |

Files under `test/` are also out of scope

## Tests

After cloning the repo, run the following to install the dependencies under `lib/`:
```bash
forge install
```

The following command is sufficient to run the whole test suite:
```bash
forge test
forge test --match-path src/test/Vulnerabilities.sol --verbosity -vv 
```

To generate a gas report:
```bash
forge test --gas-report
```

All-in-one command:
```bash
rm -rf 2023-01-canto-identity || true && git clone --recurse-submodules https://github.com/code-423n4/2023-01-canto-identity.git && cd 2023-01-canto-identity && foundryup && forge test --gas-report
```

To run slither:
```bash
slither . --compile-force-framework foundry
```

## Scoping Details 
```
- If you have a public code repo, please share it here:  
- How many contracts are in scope?: 3
- Total SLoC for these contracts?: 320
- How many external imports are there?: 3 
- How many separate interfaces and struct definitions are there for the contracts within scope?: 1  
- Does most of your code generally use composition or inheritance?: Inheritance
- How many external calls?: 8
- What is the overall line coverage percentage provided by your tests?: 100%
- Is there a need to understand a separate part of the codebase / get context in order to audit this part of the protocol?: No, completely new protocol without any dependencies
- Does it use an oracle?: No
- Does the token conform to the ERC20 standard?: No token
- Are there any novel or unique curve logic or mathematical models?: No
- Does it use a timelock function?: No
- Is it an NFT?: Yes
- Does it have an AMM?: No  
- Is it a fork of a popular project?: No  
- Does it use rollups?: No
- Is it multi-chain?: No
- Does it use a side-chain?: No
```
