<h3 align="center">F3BlackJack</h3>

  <p align="center">
    A fair blackjack game with provable randomness using Chainlink VRF.
    <br />
  </p>

<p align="center">
  <img src="https://img.shields.io/badge/Solidity-e6e6e6?style=for-the-badge&logo=solidity&logoColor=black" alt="Solidity"/>
  <img src="https://camo.githubusercontent.com/8c47fd6bf4ac8eec4be8caefd7d56b8cdbff9de4985b76e3ff3ab1497d7363e8/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f466f756e6472792d677265793f7374796c653d666c6174266c6f676f3d646174613a696d6167652f706e673b6261736536342c6956424f5277304b47676f414141414e53556845556741414142514141414155434159414141434e6952304e414141456c456c45515652346e483156555568556152673939383459647a42706b7152305a3231307249455349585361624562634867796472704e52526a30306b57617a746a3055314d4f57304d4f49624433303049764c4d7142704d54475978646f71796f524e4455455342445777557550756743535373544d3775304f6a312f2b656664694d636d6e50322f66446437374434662f4f4236784361327572515a626c6c56494359477471616e4b31744c53344164674179414167797a4a615731734e712f756c543474774f4777346650697741474470374f77385656316437625661725257785743772f6b386d67736245786d30776d5a2b4c782b4d2f5872312f2f4363417353566d534a4830314d634c68734145416e45356e782b546b35422f78654a784f70354e39665832737171716978574c686e5474333648413447497646474931475533563164663550652f394431743765486b676b45757a6f3647425054343957576c6f713748613766756a5149546f6344753761745573336d38336936745772326f6b544a2f6a6978517565506e3236357a5053634468736b47555a652f6675625876382b44467633727970626469775161786274343652534954373975336a304e415162393236525656564f54342b5471765679767a38664430594443354e546b3679736248786c43524a2f354b536c41415552794b5254464e546b7741673774363953352f507837362b50713747794d6749392b2f667a394852555149514f336273454b4f6a6f333844734a43554a4144772b2f3042565657376f74486f387073336234797658723343784d514554435954544359544e453044414f546c3553475879304652464f7a5a7377646d73786b564652584c4e545531786d67302b6b4e76622b2f3341474163474269493739363957776367367572712b4f544a4539363764343962746d7a68395054305233574a52494b4251494442594a425455314e73614767674147477a32665465337435664165515a415777754c69347550336e79704f5431656d457747464265586f3761326c6f734c4379676f6145422f6633394d4a6c4d434956436b43514a42773865684e56716863666a51584e7a7331525355694b7458372b2b4445415a71717171334b465169414259554644414d32664f6b4351584678644a6b766676333264685953473958692b765862764732646e5a6a346f446751434c696f716f4b417148686f626f6444712f4d63374e7a556b6c4a535549426f4f7732577a59746d30626c7065587357624e476b784d544f44703036646f61327644344f41674e6d37634349764641704c516452336e7a7033447a70303738664c6c537851564665486475336341674970486a7836392f7a425558356b2b4d4442417439764e5938654f736275376d366c556967634f484b444c3557496d6b79484a7a39544759724563414c734d49506e363965735a54644d49674d2b6550554e58567864753337364e73724979754e3175584c70304357617a476350447733433558464256465766506e6b564e5451313850702b657a5759354d7a507a4f344466414142486a687a704a736c554b71566476486952342b506a624739765a79365849306b754c5330786d55785343454753395076394c4330747064466f5a47566c705361456f4d2f6e757749414b782f37713547526b6239436f5a42515656576350332b657a35382f4a306d6d30326b4f44673779776f554c6a4d5669544b6654744e7674584c74324c5464743271546e63726e6c736247784c49437653557166726c35484a424c68314e54556b6842434a386d4668515832392f6454565655574642547777594d48314857646c7939667071496f65694b52574a71666e3264316458576e4c4d7566377a4d41484431367447642b666e37465a7932627a59724b796b6f644141465156565639635846526b4e5465766e334c75626b357472533058506e6678484534484e384f44772b6e562f79616e70366d782b4f68782b503561494d51676d4e6a59332f5731745a2b74357273537747372b666a78342f37362b76726d3764753332776f4c433030416b45366e3338666a385a6d4844782f2b637550476a5238424a4c3859734374596451494d414c5971696c4b764b456f394150754874792b656748384133476646444a586d786d4d41414141415355564f524b3543594949253344266c696e6b3d6874747073253341253246253246626f6f6b2e676574666f756e6472792e7368253246" alt="Foundry"/>
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT"/>
</p>

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

* Add Gelato VRF as a backup oracle

# License

*Distributed under the MIT license.*

<p align="right">(<a href="#readme-top">back to top</a>)</p>

# Contact

*Flopcatcher* - flopcatcher.audit@gmail.com

<p align="right">(<a href="#readme-top">back to top</a>)</p>

# Disclaimer

*This codebase has not undergone a proper security review and is therefore not suitable for production.*


<p align="right">(<a href="#readme-top">back to top</a>)</p>
