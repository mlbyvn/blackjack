<h3 align="center">F3BlackJack</h3>

  <p align="center">
    A fair blackjack game with provable randomness using Chainlink VRF.
    <br />
  </p>

<p align="center">
  <img src="https://img.shields.io/badge/Solidity-e6e6e6?style=for-the-badge&logo=solidity&logoColor=black" alt="Solidity"/>
  <img src="https://img.shields.io/badge/Foundry-grey?style=flat&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAElElEQVR4nH1VUUhUaRg9984YdzBpkqR0Z210rIESIXSabEbcHgydrpNRRj00kWaztj0U1MOW0MOIbD300IvLMqBpMTGYxdoqyoRNDUESBDWwUuPugCSSsTM7u0Oj1/+efdiMcmnP2/fDd77D4f/OB6xCa2urQZbllVICYGtqanK1tLS4AdgAyAAgyzJaW1sNq/ulT4twOGw4fPiwAGDp7Ow8VV1d7bVarRWxWCw/k8mgsbExm0wmZ+Lx+M/Xr1//CcAsSVmSJH01McLhsAEAnE5nx+Tk5B/xeJxOp5N9fX2sqqqixWLhnTt36HA4GIvFGI1GU3V1df5Pe/9D1t7eHkgkEuzo6GBPT49WWloq7Ha7fujQITocDu7atUs3m83i6tWr2okTJ/jixQuePn265zPScDhskGUZe/fubXv8+DFv3rypbdiwQaxbt46RSIT79u3j0NAQb926RVVVOT4+TqvVyvz8fD0YDC5NTk6ysbHxlCRJ/5KSlAAURyKRTFNTkwAg7t69S5/Px76+Pq7GyMgI9+/fz9HRUQIQO3bsEKOjo38DsJCUJADw+/0BVVW7otHo8ps3b4yvXr3CxMQETCYTTCYTNE0DAOTl5SGXy0FRFOzZswdmsxkVFRXLNTU1xmg0+kNvb+/3AGAcGBiI7969Wwcg6urq+OTJE967d49btmzh9PT0R3WJRIKBQIDBYJBTU1NsaGggAGGz2fTe3t5fAeQZAWwuLi4uP3nypOT1emEwGFBeXo7a2losLCygoaEB/f39MJlMCIVCkCQJBw8ehNVqhcfjQXNzs1RSUiKtX7++DEAZqqqq3KFQiABYUFDAM2fOkCQXFxdJkvfv32dhYSG9Xi+vXbvG2dnZj4oDgQCLioqoKAqHhobodDq/Mc7NzUklJSUIBoOw2WzYtm0blpeXsWbNGkxMTODp06doa2vD4OAgNm7cCIvFApLQdR3nzp3Dzp078fLlSxQVFeHdu3cAgIpHjx69/zBUX5k+MDBAt9vNY8eOsbu7m6lUigcOHKDL5WImkyHJz9TGYrEcALsMIPn69esZTdMIgM+ePUNXVxdu376NsrIyuN1uXLp0CWazGcPDw3C5XFBVFWfPnkVNTQ18Pp+ezWY5MzPzO4DfAABHjhzpJslUKqVdvHiR4+PjbG9vZy6XI0kuLS0xmUxSCEGS9Pv9LC0tpdFoZGVlpSaEoM/nuwIAKx/7q5GRkb9CoZBQVVWcP3+ez58/J0mm02kODg7ywoULjMViTKfTtNvtXLt2LTdt2qTncrnlsbGxLICvSUqfrl5HJBLh1NTUkhBCJ8mFhQX29/dTVVUWFBTwwYMH1HWdly9fpqIoeiKRWJqfn2d1dXWnLMuf7zMAHD16tGd+fn7FZy2bzYrKykodAAFQVVV9cXFRkNTevn3Lubk5trS0XPnfxHE4HN8ODw+nV/yanp6mx+Ohx+P5aIMQgmNjY3/W1tZ+t5rsSwG7+fjx4/76+vrm7du32woLC00AkE6n38fj8ZmHDx/+cuPGjR8BJL8YsCtYdQIMALYqilKvKEo9APuHty+egH8A3GfFDJXmxmMAAAAASUVORK5CYII%3D&link=https%3A%2F%2Fbook.getfoundry.sh%2F)
![MIT](https://img.shields.io/badge/license-MIT-blue" alt="Foundry"/>
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT"/>
</p>





<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>




# About The Project

## Project Description

This project is a solidity implementation of the blackjack game with (almost) standard ruleset. 
The dealer logic is implemented inside the `fulfillRandomWords` function which is called by Chainlink VRF after a user finishes his turn, wether it 
is a game start, double down or a simple draw. Such approach allows to both automate the dealer's play and provide provable random card generation that 
cannot be exploited in MEV or by the players. In each user turn a certain number of random seeds is requested *on demand* depending on the chosen play.
That means requested random seeds are used *only* inside the single `fulfillRandomWords` function call, thus providing user no information about the cards
that could be drawn in the future. 

Even on fastest L2 solutions like Arbitrum, Chainlink VRF needs 15-30 seconds to respond. Unfortunately this is the price for transparent solidity gambling experience a user must pay.
Though Solana implementation (which is the state-of-the-art of IGaming) would be much more user-friendlier and cheaper, the mere purpose or this project is to pick up a hard challenge and showcase the developer skills.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Ruleset

* [The ruleset](https://bicyclecards.com/how-to-play/blackjack) is mostly standard. 
* 52 card deck
* *Double Down*:
    * If the total value of user's fist two cards is 9, 10 or 11, he can double the original bet
    * Then, dealer gives the player only one card
* *Insurance*:
    * When the dealer's face-up card is an ace, player may make a side bet of up to half the original bet that the dealer's face-down card is a ten-card, and thus a blackjack for the house
    * Insurance payout rate is 3:2
    * A player cannot double down and call insurance simultaneously 
    * Player can only make insurance bet right after the first dealer card is revealed. If the player chooses to draw another card, he can no longe make an insurance bet
* *Splitting*:
    * The main game logic is implemented inside a large `fulfillRandomWords` function as it's the only function that Chainlink VRF can call to provide random words
    * Therefore it is *gas-heavy*
    * In order to reduce gas demand, the splitting functionality *is not implemented*
* *House Edge*:
    * If both player and dealer bust, dealer wins


<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Project Overview
* Scripts:
    * DeployF3BlackJack: Deploy script, currently supports Sepolia Mainnet and local Anvil
    * HelperConfig: provides network configuration
    * Interactions.s.sol: helps managing the subscription
* Contracts:
    * F3BlackJack: the main contract
* *nLines*: 836
* *nSLOC*: 487

## Tests and Security Overview

* Test coverage:
    * Check the lcov.info file in /stats_and_reports

| File                    | % Lines          | % Statements     | % Branches     | % Funcs         |
|-------------------------|------------------|------------------|----------------|-----------------|
| src/F3BlackJack.sol     | 97.97% (289/295) | 97.97% (289/295) | 91.94% (57/62) | 100.00% (31/31) |

* *Static code analysis*: 
    * [Slither](https://github.com/crytic/slither): shows pottential reentrancies in fulfillRandomWords, but Chainlink is a trusted party
    * [Aderyn](https://github.com/Cyfrin/aderyn): no significant issues
* *Dynamic code analysis*:
    * 66 unit and stateless fuzz tests
    * Test coverage:
    * Check the lcov.info file in /stats_and_reports

| File                    | % Lines          | % Statements     | % Branches     | % Funcs         |
|-------------------------|------------------|------------------|----------------|-----------------|
| src/F3BlackJack.sol     | 97.97% (289/295) | 97.97% (289/295) | 91.94% (57/62) | 100.00% (31/31) |

* *Manual review*:
    * Check any previously spotted bugs in gambling contracts on [Solodit](https://solodit.cyfrin.io)



<p align="right">(<a href="#readme-top">back to top</a>)</p>


<!-- GETTING STARTED -->
# Getting Started

## Prerequisites

* [Foundry](https://book.getfoundry.sh)
* [Chainlink contracts](https://github.com/smartcontractkit/chainlink)
    ```bash
    forge install smartcontractkit/chainlink --no-commit
    ```
* [Solmate contracts](https://github.com/transmissions11/solmate)
    ```bash
    forge install transmissions11/solmate --no-commit
    ```
* [Openzeppelin contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
    ```bash
    forge install openzeppelin/openzeppelin-contracts --no-commit
    ```
* [Cyfrin's foundry-devops](https://github.com/Cyfrin/foundry-devops)
    ```bash
    forge install cyfrin/foundry-devops --no-commit
    ```


## Setup

1. Clone the repo
2. Create a [VRF subscription](https://docs.chain.link/vrf/v2-5/subscription/create-manage)
3. Fund the subscription
4. Adjust the HelperConfig.s.sol
5. Add another chain config (if needed) and deploy

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRIBUTING -->
## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".
Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>

# To Do

* Deployment and fork tests on Arbitrum Sepolia (link on arbiscan coming soon)

# License

*Distributed under the MIT license.*

<p align="right">(<a href="#readme-top">back to top</a>)</p>

# Contact

*Flopcatcher* - flopcatcher.audit@gmail.com

<p align="right">(<a href="#readme-top">back to top</a>)</p>

# Disclaimer

*This codebase has not undergone a proper security review and is therefore not suitable for production.*


<p align="right">(<a href="#readme-top">back to top</a>)</p>
