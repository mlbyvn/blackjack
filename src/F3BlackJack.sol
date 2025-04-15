// SPDX-License-Identifier: MIT

/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////
   /$$$$$$$$ /$$$$$$        /$$$$$$$  /$$                     /$$          /$$$$$                     /$$      
  | $$_____//$$__  $$      | $$__  $$| $$                    | $$         |__  $$                    | $$      
  | $$     |__/  \ $$      | $$  \ $$| $$  /$$$$$$   /$$$$$$$| $$   /$$      | $$  /$$$$$$   /$$$$$$$| $$   /$$
  | $$$$$     /$$$$$/      | $$$$$$$ | $$ |____  $$ /$$_____/| $$  /$$/      | $$ |____  $$ /$$_____/| $$  /$$/
  | $$__/    |___  $$      | $$__  $$| $$  /$$$$$$$| $$      | $$$$$$/  /$$  | $$  /$$$$$$$| $$      | $$$$$$/ 
  | $$      /$$  \ $$      | $$  \ $$| $$ /$$__  $$| $$      | $$_  $$ | $$  | $$ /$$__  $$| $$      | $$_  $$ 
  | $$     |  $$$$$$/      | $$$$$$$/| $$|  $$$$$$$|  $$$$$$$| $$ \  $$|  $$$$$$/|  $$$$$$$|  $$$$$$$| $$ \  $$
  |__/      \______/       |_______/ |__/ \_______/ \_______/|__/  \__/ \______/  \_______/ \_______/|__/  \__/
/*//////////////////////////////////////////////////////////////////////////////////////////////////////////////                                                                                                             

/**
 * @title F3 BlackJack
 * @author Flopcatcher
 * @notice Blackjack with provable randomness using Chainlink VRF and Automation.
 */                      
/*//////////////////////////////////////////////////////////////
                             INFOS
//////////////////////////////////////////////////////////////*/
/*
* 1. Standard blackjack rules with split, double down and insurance.
* 2. Minimal deposit amount is set in the constructor and can be changed by the
*    contract owner.
* 3. Instead of using ETH directly, user gets minted equal amount of ERC20 compatible
*    F3Token as an ecosystem token that could be used in other games.
* 4. Dealer gets only one initial card drawn. Althought he must draw two cards and flip only one, 
*    drawing two cards at once opens an opportunity for cheating: even though the second card would 
*    not be displayed to the user, it's value could be read from the blockchain, providing
*    unfare advantage. The second dealer's card is actually drawn after the user stands
*    or busts.
*////////////////////////////////////////////////////////////////

pragma solidity ^0.8.22;

import {F3Token} from "./F3Token.sol";
import {IF3Token} from "../src/interfaces/IF3Token.sol";
import {VRFConsumerBaseV2Plus} from "lib/chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "lib/chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract F3BlackJack is  VRFConsumerBaseV2Plus{

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error F3BlackJack__LessThanMinimalDeposit();
    error F3BlackJack__CannotStartWhileGameActive();
    error F3BlackJack__WithdrawalFailed();
    error F3BlackJack__NothingToWithdraw();
    error F3BlackJack__UnsafeToWithdrawHouseEdge();
    error F3BlackJack__LessThanMinimalBet(uint256 minimalBet);
    error F3BlackJack__RequestAlreadyFulfilled(uint256 requestId);
    error F3BlackJack__RequestIdNotFound(uint256 requestId);

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    struct Lobby {

        uint256 LobbyId;
        address Player;
        
        uint256 CurrentDep;
        uint256 OriginalBalance;
        uint256 SplitCard;
        uint256 GamesPlayed;

        uint256 PlayerBet;
        uint256 InsuranceBet;
        uint256 PlayerCard1;
        uint256 PlayerCard2;
        uint256 PlayerNewCard;
        uint256 PlayerCardTotal;
        uint256 PlayerSplitTotal;

        uint256 DealerCard1;
        uint256 DealerCard2;
        uint256 DealerNewCard;
        uint256 DealerCardTotal;

        bool CanDoubleDown;
        bool CanInsure;
        bool CanSplit;
        bool IsSplitting;
        bool IsSoftHand;

        bool IsRoundInProgress;
        
        uint256 InitialRequestId;
        uint256 RequestSecondDealerCard;
        uint256 AdditionalRequest1;
        uint256 AdditionalRequest2;
        uint256 AdditionalRequest3;
        uint256 AdditionalRequest4;
    }

    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        uint256[] randomWords;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256[] public requestIds;

    uint16 private constant REQUEST_CONFIRMATIONS = 3;

    address private immutable i_f3token;

    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    
    uint256 private s_minimalDeposit;
    uint256 private s_houseEdgeAmount;
    uint256 private s_lastLobbyId = 0; 
    uint256 private s_minimalBet;
    uint256 private s_lastRequestId;

    mapping(address => bool) private s_currentlyInGame;
    mapping(address => Lobby) private s_userToCurrentLobby;
    mapping(uint256 => RequestStatus) private s_requests;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Deposited(address indexed player, uint256 indexed amount);
    event Withdrawn(address indexed player, uint256 indexed amount);
    event LobbyCreated(uint256 indexed lobbyId);
    event Win(uint256 indexed amount, uint256 indexed lobbyId);
    event Loss(uint256 indexed amount, uint256 indexed lobbyId);
    event RequestSent(uint256 indexed requestId, uint32 indexed numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event Draw(uint256 indexed value);
    event Stand(uint256 indexed totalValue);
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier notInGame() {
        if(s_currentlyInGame[msg.sender]){
            revert F3BlackJack__CannotStartWhileGameActive();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                         CONSTRUCTOR & RECEIVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @param _token Address of deployed F3Token
     * @param _startingMinDep Set the starting minimal deposit amount in wei
     */
    constructor(
        address _token,  
        address _vrfCoordinator, 
        uint256 _startingMinDep,
        bytes32 _gasLane,
        uint256 _subscriptionId,
        uint32 _callbackGasLimit) 
    VRFConsumerBaseV2Plus(_vrfCoordinator){
        i_f3token = _token;
        s_minimalDeposit =  _startingMinDep;
        i_keyHash = _gasLane;
        i_subscriptionId = _subscriptionId;
        i_callbackGasLimit = _callbackGasLimit;
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @param _amount Amount of wei to deposit
     * @dev User deposits wei and gets equal amount of
     *       F3Tokens minted. These tokens are than used to 
     *       make bets. 
     */
    function deposit(uint256 _amount) external payable notInGame {
        if (_amount < s_minimalDeposit) {
            revert F3BlackJack__LessThanMinimalDeposit();
        }
        IF3Token(i_f3token).mint(msg.sender, msg.value);
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @param _amount Amount of tokens to burn and wei to withdraw
     * @dev Cannot withdraw while in game
     * @dev Cannot withdraw more than current balance
     * @dev After withdrawal emit an event
     */
    function withdraw(uint256 _amount) external notInGame {
        if (getBalance(msg.sender) == 0) {
            revert F3BlackJack__NothingToWithdraw();
        }
        if (_amount >= getBalance(msg.sender)) {
            _amount = getBalance(msg.sender);
        }
        IF3Token(i_f3token).burn(msg.sender, _amount);
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert F3BlackJack__WithdrawalFailed();
        }
        emit Withdrawn(msg.sender, _amount);
    }

    /**
     * @dev Starts the new game. Creates a lobby and draws first three cards:
     * two for the user, one for the dealer
     * @param _bet Bet amount
     */
    function startGame(uint256 _bet) external notInGame {
        if (_bet < s_minimalBet) {
            revert F3BlackJack__LessThanMinimalBet(s_minimalBet);
        }
        if (_bet > getBalance(msg.sender)) {
            _bet = getBalance(msg.sender);
        }
        // Set the lock
        s_currentlyInGame[msg.sender] = true;

        // Create a lobby
        Lobby memory lobby = _createLobby(_bet);

        lobby.InitialRequestId = _requestRandomWords(3);


    }

    /**
     * @dev Withdraws profit from house edge if there is enough ETH in the contract
     * @param _to Receiver address
     * @param _amount Amount to withdraw
     */
    function withdrawHouseEdge(address _to, uint256 _amount) external onlyOwner {
        
    }

    /**
     * @dev Change the minimal bet amount
     * @param _amount New minimal bet amount
     */
    function setMinimalBet(uint256 _amount) external onlyOwner {
        s_minimalBet = _amount;
    }

    function split() external {}

    function doubleDown() external {}

    /*//////////////////////////////////////////////////////////////
                            GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Returns minimal deposit amount in wei 
     */
    function getMinimalDepositAmount() external view returns(uint256){
        return s_minimalDeposit;
    }

    /**
     * @dev Returns the amount of house edge profit
     */
    function getHouseEdgeAmount() external view returns(uint256) {
        return s_houseEdgeAmount;
    }

    function getBalance(address _user) public view returns(uint256) {
        return IF3Token(i_f3token).balanceOf(_user);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Request random seeds from Chainlink VRF that are used in
     *      Fisher-Yates to derive a card
     * @param _numWords Number of seeds 
     * @return requestId Request ID
     */
    function _requestRandomWords(uint32 _numWords) internal returns(uint256 requestId) {
            requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: _numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: false
                    })
                )
            })
        );
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });
        requestIds.push(requestId);
        s_lastRequestId = requestId;
        emit RequestSent(requestId, _numWords);
        return requestId;
    }

    /**
     * @dev Creates a lobby for a single user
     * @param _bet User bet
     */
    function _createLobby(uint256 _bet) internal returns(Lobby memory) {
        // Create lobby
        Lobby memory lobby;
        lobby.LobbyId = s_lastLobbyId;
        lobby.CurrentDep = IF3Token(i_f3token).balanceOf(msg.sender);
        lobby.Player = msg.sender;
        lobby.PlayerBet = _bet;
        
        // Update the current lobby
        s_userToCurrentLobby[msg.sender] = lobby;

        // Increment lobbyId
        s_lastLobbyId += 1;

        emit LobbyCreated(s_lastLobbyId);
        return lobby;
    }


    /**
     * @dev Currently mock implementation
     * @param _requestId mock 
     * @param _randomWords mock 
     */
    function fulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords) internal override {
        if (!s_requests[_requestId].exists) {
            revert F3BlackJack__RequestIdNotFound(_requestId);
        }
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        emit RequestFulfilled(_requestId, _randomWords);
    }

    /**
     * @dev Draw three initial cards: first and third for user, second for dealer
     * @param lobby Current lobby
     * @return cards Three initial cards
     */
    function _initialDraw(Lobby memory lobby) internal returns(uint32[] memory cards){}

    /**
     * @dev Draw a card
     * @param lobby Current lobby
     * @return card Card value
     */
    function _draw(Lobby memory lobby) internal returns(uint32 card) {}

    /*//////////////////////////////////////////////////////////////
                           PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

}