# Icosa

Icosa is a collection of Ethereum / PulseChain smart contracts that build upon the Hedron smart contract to provide additional functionality. For more information visit https://icosa.pro


Icosa is deployed at the following Ethereum / PulseChain addresses.

    Icosa.sol                  -> TBD
    WeAreAllTheSA.sol          -> TBD


The following smart contracts are **UNLICENSED, All rights are reserved**. 

    ./contracts/Icosa.sol
    ./contracts/auxiliary/WeAreAllTheSA.sol


The following smart contracts are **MIT Licensed**. 

    ./contracts/interfaces/HEX.sol
    ./contracts/uniswap/FullMath.sol
    ./contracts/interfaces/Hedron.sol
    ./contracts/declarations/Internal.sol
    ./contracts/declarations/External.sol
    ./contracts/interfaces/HEXStakeInstance.sol
    ./contracts/interfaces/HEXStakeInstanceManager.sol
    ./contracts/rarible/royalties/contracts/LibPart.sol
    ./contracts/rarible/royalties/contracts/RoyaltiesV2.sol
    ./contracts/rarible/royalties/contracts/LibRoyaltiesV2.sol
    ./contracts/rarible/royalties/contracts/impl/RoyaltiesV2Impl.sol
    ./contracts/rarible/royalties/contracts/impl/AbstractRoyalties.sol

The following smart contracts are **GPL V2+ Licensed**. 

    ./contracts/uniswap/TickMath.sol



This repository provided for auditing, research, and interfacing purposes only. Copying any **UNLICENSED** smart contract is strictly prohibited.


## Contracts of Interest

**Icsoa.sol** - ERC20 contract responsible for staking Hedron (HDRN), Icosa(ICSA), and HSI Buy-Backs.

**WeAreAllTheSA.sol** ERC721 contract responsible for minting "We Are All the SA" NFT's.

## Documentation / ABI

Documentation and ABI can be generated automatically by cloning this repository, installing all required HardHat dependencies, and compiling the contracts.

    git clone https://https://github.com/SeminaTempus/Icosa.git
    cd Icosa
    npm install
    npx hardhat compile

Documentation and ABI can be found in the `./docs` and `./abi` directories respectively after a successful compilation.

## Tests

Tests can be run by executing...

    npx hardhat test
