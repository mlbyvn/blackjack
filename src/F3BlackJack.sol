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
 * @notice Blackjack with provable randomness using Chainlink VRF.
 */                      
/*//////////////////////////////////////////////////////////////
                             INFOS
//////////////////////////////////////////////////////////////*/
/*
* 1. Standard blackjack rules with double down and insurance. Splitting is not allowed.
* 2. If a player has an opportunity to insure and double down, he can choose only one. 
* 3. Minimal deposit amount is set in the constructor and can be changed by the
*    contract owner.
* 4. Dealer gets only one initial card drawn. Althought he must draw two cards and flip only one, 
*    drawing two cards at once opens an opportunity for cheating: even though the second card would 
*    not be displayed to the user, it's value could be read from the blockchain, providing
*    unfare advantage. The second dealer's card is actually drawn after the user stands
*    or busts, this does not alter the unconditional probabilities of dealer's blackjack outcome.
* 5. An insurance bet is normally processed right away: if the second dealer card is a 10-value,
*    it is shown right away and the round is then played, otherwise the insurance bet is lost and
*    the play continues. We cant actually request the second dealer card and "do not flip it", as it
*    will be still written in the blockchain state and thus visible. That's why the insurance is
*    processed after the user busts.
*////////////////////////////////////////////////////////////////

pragma solidity ^0.8.22;

import {VRFConsumerBaseV2Plus} from "lib/chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "lib/chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract F3BlackJack is  VRFConsumerBaseV2Plus{

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error F3BlackJack__LessThanMinimalDeposit();
    error F3BlackJack__CannotStartOrDepositWhileGameActive();
    error F3BlackJack__WithdrawalFailed();
    error F3BlackJack__NothingToWithdraw();
    error F3BlackJack__LessThanMinimalBet(uint256 minimalBet);
    error F3BlackJack__RequestIdNotFound(uint256 requestId);
    error F3BlackJack__PleaseWaitCardsAreDrawn();
    error F3BlackJack__CannotDoubleDown();
    error F3BlackJack__CannotInsure();
    error F3BlackJack__InsufficientBalance();
    error F3BlackJack__CanInsureUpToHalfTHeOriginalBet();
    error F3BlackJack__CannotDoubleDownAfterInsurance();
    error F3BlackJack__LobbyNotCreated();
    error F3BlackJack__UnsafeHouseEdgeWithdrawal();
    error F3BlackJack__CannotWithdrawAllWhileOpenAndLiveLobby();
    error F3BlackJack__ContractIsPaused();
    error F3BlackJack__InvalidRecipient();

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    struct Lobby {

        uint256 LobbyId;
        address Player;

        uint256 PlayerBet;
        uint256 InsuranceBet;

        uint256[] PlayerDrawnCards;
        uint256 PlayerCardTotal;
        bool PlayerBusts;
        bool PlayerStands;

        uint256[] DealerDrawnCards;
        uint256 DealerCardTotal;

        bool CanDoubleDown;
        bool CanInsure;
        bool IsInsuring;
        bool IsDoubleDown;
        
        uint256 InitialRequestId;
        uint256 LastRequestId;
    }

    struct RequestStatus {
        bool fulfilled;
        bool exists;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256[] public requestIds;

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint256 private constant DECK_SIZE = 52;
    uint256 private constant PAYOUT_NUM = 3;
    uint256 private constant PAYOUT_DENUM = 2;
    uint256 private constant A = 1;
    uint256 private constant J = 11;
    uint256 private constant Q = 12;
    uint256 private constant K = 13;

    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    
    uint256 private immutable s_minimalDeposit;
    uint256 private s_lastLobbyId = 0; 
    uint256 private s_minimalBet;
    uint256 private s_lockedForPayout;

    bool private s_blackJackPaused;

    mapping(address => bool) private s_currentlyInGame;
    mapping(uint256 => Lobby) private s_requestIdToLobby;
    mapping(uint256 => RequestStatus) private s_requests;
    mapping(address => bool) private s_isUsersTurn;
    mapping(address => uint256) private s_balances;
    mapping(address => Lobby) private s_userToCurrentLobby;

    mapping(address => mapping(uint256 => bool)) private s_drawnCards;
    mapping(address => uint256[]) private s_usedIndices;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Deposited(address indexed player, uint256 indexed amount);
    event Withdrawn(address indexed player, uint256 indexed amount);
    event LobbyCreated(uint256 indexed lobbyId);
    event GameStarted(address indexed player, uint256 indexed lobbyId);
    event Win(uint256 indexed amount, address indexed user, uint256[] cardsUser, uint256[] cardsDealer);
    event Loss(uint256 indexed amount, address indexed user, uint256[] cardsUser, uint256[] cardsDelaer);
    event Tie(address indexed user, uint256[] userCards, uint256[] dealerCards);
    event RequestSent(uint256 indexed requestId, uint32 indexed numWords);
    event RequestFulfilled(uint256 indexed requestId);
    event Drawn(address indexed user, uint256 indexed value);
    event Stand(address indexed user, uint256 indexed totalValue);
    event InitialCards(uint256[3] initialCards);
    event DoubleDown(uint256 newTotalBet, uint256 requestId);
    event DrawRequested(uint256 indexed requestId);
    event Insurance(uint256 sideBet);
    event InsuranceWon(address indexed user, uint256 indexed amount);
    event InsuranceLost(address indexed user, uint256 indexed amount);
    event ContractPaused();
    event ContractUnpaused();
    event MinimalBetSet(uint256 newMinimalBet);

    // Debug events for tests

    // event Test__LobbyParams(uint256 cardstotal, bool canInsure, bool canDOubledown);
    // event Test__DoubleDownBranch();
    // event Test__StandBranch();
    // event Test__InitialRequestBranch();
    // event Test__GeneralCaseBranch();
    // event Test__CurrentState(uint256[] userCards, uint256[] dealerCards, uint256 userTotal, uint256 dealerTotal);
    // event Test__Player(address player);
    // event Test__Checkpoint();
    // event Test__HouseEdgeParams(uint256 balance, uint256 amount, uint256 locked);
    // event Test__LockedForPayout(uint256 lockedForPayout);


    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier notInGame() {
        if(s_currentlyInGame[msg.sender]){
            revert F3BlackJack__CannotStartOrDepositWhileGameActive();
        }
        _;
    }

    modifier isUsersTurn() {
        if(!s_isUsersTurn[msg.sender]) {
            revert F3BlackJack__PleaseWaitCardsAreDrawn();
        }
        _;
    }

    modifier lobbyExists() {
        if (!s_currentlyInGame[msg.sender]) {
            revert F3BlackJack__LobbyNotCreated();
        }
        _;
    }

    modifier isNotPaused() {
        if (s_blackJackPaused) {
            revert F3BlackJack__ContractIsPaused();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                         CONSTRUCTOR & RECEIVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @param _startingMinDep Set the starting minimal deposit amount in wei
     */
    constructor(
        address _vrfCoordinator, 
        uint256 _startingMinDep,
        bytes32 _gasLane,
        uint256 _subscriptionId,
        uint32 _callbackGasLimit) 
    VRFConsumerBaseV2Plus(_vrfCoordinator){
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
     * @dev User deposits wei and gets equal amount of
     *       F3Tokens minted. These tokens are than used to 
     *       make bets. 
     */
    function deposit() external payable isNotPaused notInGame {
        if (msg.value < s_minimalDeposit) {
            revert F3BlackJack__LessThanMinimalDeposit();
        }
        s_balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @param _amount Amount of tokens to burn and wei to withdraw
     * @dev Cannot withdraw while in game
     * @dev Cannot withdraw more than current balance
     * @dev After withdrawal emit an event
     */
    function withdraw(uint256 _amount) external notInGame {
        if (msg.sender == address(0)){
            revert  F3BlackJack__InvalidRecipient();
        }
        if (getBalance(msg.sender) == 0) {
            revert F3BlackJack__NothingToWithdraw();
        }
        if (_amount >= getBalance(msg.sender)) {
            _amount = getBalance(msg.sender);
        }
        s_balances[msg.sender] -= _amount;
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
    function startGame(uint256 _bet) external isNotPaused notInGame {
        if (_bet < s_minimalBet) {
            revert F3BlackJack__LessThanMinimalBet(s_minimalBet);
        }
        if (_bet > getBalance(msg.sender)) {
            _bet = getBalance(msg.sender);
        }
        // Set the lock
        s_currentlyInGame[msg.sender] = true;

        // Create a lobby
        Lobby storage lobby = _createLobby(_bet, msg.sender);

        uint256 requestId = _requestRandomWords(3);

        lobby.InitialRequestId = requestId;
        s_requestIdToLobby[requestId] = lobby; 

        address player = lobby.Player;

        s_isUsersTurn[player] = false;

        s_lockedForPayout += (_bet * PAYOUT_NUM) / PAYOUT_DENUM;
        // emit Test__LockedForPayout(s_lockedForPayout);
        emit GameStarted(player, lobby.LobbyId);
    }

    /**
     * @dev Withdraws profit from house edge if there is enough ETH in the contract.
     * in order to keep payouts safe and sound the owner must always keep the amount of eth
     * that covers payouts in all live lobbies + 10%
     * @param _to Receiver address
     * @param _amount Amount to withdraw
     */
    function withdrawHouseEdge(address _to, uint256 _amount) external onlyOwner {
        // emit Test__HouseEdgeParams(address(this).balance, _amount, s_lockedForPayout);

        if (_amount > address(this).balance - (s_lockedForPayout * 110) / 100) {
            revert F3BlackJack__UnsafeHouseEdgeWithdrawal();
        }
        (bool success, ) = payable(_to).call{value: _amount}("");
        if (!success) {
            revert F3BlackJack__WithdrawalFailed();
        }
        emit Withdrawn(_to, _amount);
    }

    /**
     * @dev Called to withdraw all eth from the contract, e.g. in case
     * of migration to another one. Can only be called if the contract is paused
     * and all live lobbies have recieved payouts.
     * @param _to Recipient address
     */
    function withdrawAllFunds(address _to) external onlyOwner {
        if (!(s_blackJackPaused && s_lockedForPayout == 0)){
            revert F3BlackJack__CannotWithdrawAllWhileOpenAndLiveLobby();
        }
        uint256 amount = address(this).balance;
        (bool success, ) = payable(_to).call{value: amount}("");
        if (!success) {
            revert F3BlackJack__WithdrawalFailed();
        }
        emit Withdrawn(_to, amount);

    }

    /**
     * @dev Pauses the contract. Users can no longer create new lobbies
     * or deposit, can only withdraw.
     */
    function pause() external onlyOwner {
        s_blackJackPaused = true;
        emit ContractPaused();
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() external onlyOwner {
        s_blackJackPaused = false;
        emit ContractUnpaused();
    }

    /**
     * @dev Change the minimal bet amount
     * @param _amount New minimal bet amount
     */
    function setMinimalBet(uint256 _amount) external onlyOwner {
        s_minimalBet = _amount;
        emit MinimalBetSet(_amount);
    }

    /**
     * @dev User can double down if the total value of first two
     * cards is 9, 10 or 11. Only one card is then drawn
     */
    function doubleDown() external lobbyExists isUsersTurn {
        // Check if can double down
        Lobby storage lobby = s_userToCurrentLobby[msg.sender];
        if (!lobby.CanDoubleDown) {
            revert F3BlackJack__CannotDoubleDown();
        }
        if (lobby.IsInsuring) {
            revert F3BlackJack__CannotDoubleDownAfterInsurance();
        }

        // Update the bet amount
        lobby.PlayerBet += lobby.PlayerBet;
        s_lockedForPayout += (lobby.PlayerBet * PAYOUT_NUM) / PAYOUT_DENUM;

        // Request 2 seeds:
        // 1. User last card
        // 2. Seed from which all the dealer cards are derived
        // 3. Maximum number of cards
        //    the dealer can draw before hitting 17 is 9:
        //    2 + 2 + 2 + 2 + 3 + 3 + Ace + Ace + Ace
        //    As the first dealer card is already drawn, 
        //    we need to do 8 card calculations for the dealer in worst case
        //    and 1 word for the player's card (9 in total)
        
        uint256 requestId = _requestRandomWords(2);
        lobby.LastRequestId = requestId;

        // update the mapping with users turn
        lobby.IsDoubleDown = true;
        lobby.CanDoubleDown = false;
        lobby.CanInsure = false;
        s_isUsersTurn[msg.sender] = false;
        s_requestIdToLobby[requestId] = lobby;

        emit DoubleDown(lobby.PlayerBet, requestId);
    }

    /**
     * @dev User can isure if the first dealer's card is an ace,
     * i.e. make a side bet of up to half the original bet that 
     * the dealer face-down card is a ten-card
     * @param _bet Side bet 
     */
    function insurance(uint256 _bet) external lobbyExists isUsersTurn {
        Lobby storage lobby = s_userToCurrentLobby[msg.sender];
        if (!lobby.CanInsure) {
            revert F3BlackJack__CannotInsure();
        }
        if (getBalance(msg.sender) - lobby.PlayerBet < _bet) {
            revert F3BlackJack__InsufficientBalance();
        }
        if (lobby.PlayerBet - _bet < _bet) {
            revert F3BlackJack__CanInsureUpToHalfTHeOriginalBet();
        }

        lobby.InsuranceBet = _bet;
        lobby.CanInsure = false;
        lobby.IsInsuring = true;
        s_lockedForPayout += _bet * 2;

        emit Insurance(_bet);
    }

    /**
     * @dev 
     */
    function draw() external lobbyExists isUsersTurn {
        Lobby storage lobby = s_userToCurrentLobby[msg.sender];

        // Here we request 2 random words to cover a specific
        // edge case: the user busts while having an insurance bet.
        // As the insurance bet cannot be processed right after it is placed
        // (see INFOS 7.), the dealer's second card is derived from the
        // second seed in order to avoid additional requests. Otherwise
        // it is not used
        uint256 requestId = _requestRandomWords(2);
        lobby.LastRequestId = requestId;

        lobby.CanInsure = false;
        lobby.CanDoubleDown = false;
        s_isUsersTurn[msg.sender] = false;
        s_requestIdToLobby[requestId] = lobby;

        // emit Test__Player(lobby.Player);
        emit DrawRequested(requestId);
    }

    /**
     * @dev Player calls stand if he does not want to draw any more
     * cards and is not busted yet.
     * @dev We need to request only one word, from which all cards will be derived
     */
    function stand() external lobbyExists isUsersTurn {
        Lobby storage lobby = s_userToCurrentLobby[msg.sender];
        lobby.PlayerStands = true;

        uint256 requestId = _requestRandomWords(1);
        lobby.LastRequestId = requestId;


        s_isUsersTurn[msg.sender] = false;
        s_requestIdToLobby[requestId] = lobby;

        emit Stand(msg.sender, lobby.PlayerCardTotal);
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Returns minimal deposit amount in wei 
     */
    function getMinimalDepositAmount() external view returns(uint256){
        return s_minimalDeposit;
    }

    function getBalance(address _user) public view returns(uint256) {
        return s_balances[_user];
    }

    function getPauseStatus() external view returns(bool) {
        return s_blackJackPaused;
    }

    function getMinimalBet() external view returns(uint256) {
        return s_minimalBet;
    }

    function getUsersCurrentLobby(address user) external view returns(Lobby memory) {
        return s_userToCurrentLobby[user];
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
            exists: true,
            fulfilled: false
        });
        requestIds.push(requestId);
        emit RequestSent(requestId, _numWords);
        return requestId;
    }

    /**
     * @dev Creates a lobby for a single user
     * @param _bet User bet
     */
    function _createLobby(uint256 _bet, address _player) internal returns(Lobby storage) {
        // Create lobby
        Lobby storage lobby = s_userToCurrentLobby[_player];
        lobby.LobbyId = s_lastLobbyId;
        lobby.Player = _player;
        lobby.PlayerBet = _bet;
        lobby.PlayerCardTotal = 0;
        lobby.DealerCardTotal = 0;
        
        // Update the current lobby
        s_userToCurrentLobby[msg.sender] = lobby;

        // Increment lobbyId
        s_lastLobbyId += 1;

        emit LobbyCreated(s_lastLobbyId);
        return lobby;
    }


    /**
     * @dev 
     * @param _requestId Request Id 
     * @param _randomWords Array with random seeds: 
     * 1. 3 seeds if initial request
     * 2. 1 seed if simple draw or double down
     * 3.
     */
    function fulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords) internal override {
        if (!s_requests[_requestId].exists) {
            revert F3BlackJack__RequestIdNotFound(_requestId);
        }
        s_requests[_requestId].fulfilled = true;

        Lobby storage lobby = s_requestIdToLobby[_requestId];

        // emit Test__Player(lobby.Player);

        // 1. Initial draw

        if (_requestId == lobby.InitialRequestId) {
            // emit Test__InitialRequestBranch();

            (uint256 value1, ) = _retrieveCardFromSeed(_randomWords[0], lobby.Player, lobby.PlayerCardTotal);
            (uint256 valueDeal, uint256 rankDeal) = _retrieveCardFromSeed(_randomWords[1], lobby.Player, lobby.DealerCardTotal);
            (uint256 value2, ) = _retrieveCardFromSeed(_randomWords[2], lobby.Player, lobby.PlayerCardTotal);

            lobby.DealerDrawnCards.push(valueDeal);
            lobby.PlayerDrawnCards.push(value1);
            lobby.PlayerDrawnCards.push(value2);

            lobby.PlayerCardTotal = value1 + value2;
            lobby.DealerCardTotal = valueDeal;

            if ((getBalance(lobby.Player) > 2 * lobby.PlayerBet) && (lobby.PlayerCardTotal == 9 || lobby.PlayerCardTotal == 10 || lobby.PlayerCardTotal == 11)) {
                lobby.CanDoubleDown = true;
            }

            if (rankDeal == 1) {
                lobby.CanInsure = true;
            }

            s_isUsersTurn[lobby.Player] = true;
            s_userToCurrentLobby[lobby.Player] = lobby;

            emit InitialCards([value1, valueDeal, value2]);
            // emit Test__CurrentState(lobby.PlayerDrawnCards, lobby.DealerDrawnCards, lobby.PlayerCardTotal, lobby.DealerCardTotal);
            // emit Test__LobbyParams(lobby.PlayerCardTotal, lobby.CanDoubleDown, lobby.CanInsure);

        } else if (lobby.PlayerStands) {
            // emit Test__StandBranch();

            (uint256 secondDealerCard, ) = _retrieveCardFromSeed(_randomWords[0], lobby.Player, lobby.DealerCardTotal);
            lobby.DealerCardTotal += secondDealerCard;
            lobby.DealerDrawnCards.push(secondDealerCard);


            while (lobby.DealerCardTotal < 17) {
                (uint256 next, ) = _retrieveCardFromSeed(_randomWords[0], lobby.Player, lobby.DealerCardTotal);
                lobby.DealerDrawnCards.push(next);
                lobby.DealerCardTotal += next;
            }

            if (lobby.DealerCardTotal == 21) {
                if (lobby.IsInsuring) {
                    _winInsurance(lobby.Player);
                }
                _loose(lobby);
            } else if (lobby.DealerCardTotal > 21) {
                if (lobby.IsInsuring) {
                    _looseInsurance(lobby.Player);
                }
                _win(lobby);
            } else if (lobby.PlayerCardTotal > lobby.DealerCardTotal) {
                if (lobby.IsInsuring) {
                    _looseInsurance(lobby.Player);
                }
                _win(lobby);
            } else if (lobby.PlayerCardTotal == lobby.DealerCardTotal) {
                if (lobby.IsInsuring) {
                    _looseInsurance(lobby.Player);
                }
                address player = lobby.Player;
                uint256[] memory playerCards = lobby.PlayerDrawnCards;
                uint256[] memory dealerCards = lobby.DealerDrawnCards; 

                _clear(lobby.Player, lobby.InitialRequestId);

                emit Tie(player, playerCards, dealerCards);
            } else if (lobby.PlayerCardTotal < lobby.DealerCardTotal) {
                if (lobby.IsInsuring) {
                    _looseInsurance(lobby.Player);
                }                
                _loose(lobby);
            }

        } else if (lobby.IsDoubleDown) {
            // emit Test__DoubleDownBranch();

            // emit Test__CurrentState(lobby.PlayerDrawnCards, lobby.DealerDrawnCards, lobby.PlayerCardTotal, lobby.DealerCardTotal);

            (uint256 userValue, ) = _retrieveCardFromSeed(_randomWords[0], lobby.Player, lobby.PlayerCardTotal);
            (uint256 dealerValue, ) = _retrieveCardFromSeed(_randomWords[1], lobby.Player, lobby.DealerCardTotal);

            lobby.PlayerDrawnCards.push(userValue);
            lobby.PlayerCardTotal += userValue;
            lobby.DealerDrawnCards.push(dealerValue);
            lobby.DealerCardTotal += dealerValue;

            // emit Test__CurrentState(lobby.PlayerDrawnCards, lobby.DealerDrawnCards, lobby.PlayerCardTotal, lobby.DealerCardTotal);

            // Returns different cards due to hashing in _retrieveCardFromSeed
            while (lobby.DealerCardTotal < 17) {
                (uint256 next, ) = _retrieveCardFromSeed(_randomWords[1], lobby.Player, lobby.DealerCardTotal);
                lobby.DealerDrawnCards.push(next);
                lobby.DealerCardTotal += next;
            }

            // emit Test__CurrentState(lobby.PlayerDrawnCards, lobby.DealerDrawnCards, lobby.PlayerCardTotal, lobby.DealerCardTotal);

            if (lobby.DealerCardTotal == 21) {
                _loose(lobby);
            } else if (lobby.DealerCardTotal > 21) {
                _win(lobby);
            } else if (lobby.PlayerCardTotal > lobby.DealerCardTotal) {
                _win(lobby);
            } else if (lobby.PlayerCardTotal == lobby.DealerCardTotal) {
                address player = lobby.Player;
                uint256[] memory playerCards = lobby.PlayerDrawnCards;
                uint256[] memory dealerCards = lobby.DealerDrawnCards;
                _clear(lobby.Player, lobby.InitialRequestId);
                emit Tie(player, playerCards, dealerCards);
            } else {
                _loose(lobby);
            }

        } else { // General case
            // emit Test__GeneralCaseBranch();

            (uint256 playerCard,) = _retrieveCardFromSeed(_randomWords[0], lobby.Player, lobby.PlayerCardTotal);
            lobby.PlayerDrawnCards.push(playerCard);
            lobby.PlayerCardTotal += playerCard;
            address player = lobby.Player;

            // emit Test__CurrentState(lobby.PlayerDrawnCards, lobby.DealerDrawnCards, lobby.PlayerCardTotal, lobby.DealerCardTotal);

            if (lobby.PlayerCardTotal > 21) {
                if (lobby.IsInsuring) {
                    (uint256 secondDealerCard, ) = _retrieveCardFromSeed(_randomWords[1], lobby.Player, lobby.DealerCardTotal);
                    lobby.DealerDrawnCards.push(secondDealerCard);
                    if (secondDealerCard == 10) {
                        _winInsurance(player);
                    } else {
                        _looseInsurance(player);
                    }
                }
                _loose(lobby);
            } else {
                s_isUsersTurn[player] = true;
                emit Drawn(player, playerCard);
            }
        }
        emit RequestFulfilled(_requestId);
    }

    /**
     * @dev Calculates the card index. If the card is already drawn, hash the index and try again
     * @param _seed Random seed from Chainlink VRF
     */
    function _retrieveCardFromSeed(
        uint256 _seed, 
        address _user, 
        uint256 _cardTotal
        ) internal returns(uint256, uint256) {
        uint256 index = _seed % DECK_SIZE + 1;
        while (s_drawnCards[_user][index]){
            index = uint256(keccak256(abi.encode(index))) % DECK_SIZE + 1;
        }
        s_drawnCards[_user][index] = true;
        s_usedIndices[_user].push(index);
        uint256 rank = index % 13 + 1;
        if (rank == J || rank == Q || rank == K) {
            return (10, rank);
        } else if (rank == A && _cardTotal >= 11){
            return (1, rank);
        } else if (rank == A && _cardTotal < 11) {
            return (11, rank);
        } else {
            return (rank, rank);
        }
    } 

    /**
     * @dev Called if the user looses
     * @param lobby Current lobby
     */
    function _loose(Lobby memory lobby) internal returns(bool){
        // save the important stats to local variables
        uint256 bet = lobby.PlayerBet;
        uint256 initialRequestId = lobby.InitialRequestId;
        address user = lobby.Player;
        uint256[] memory cardsUser = lobby.PlayerDrawnCards;
        uint256[] memory cardsDealer = lobby.DealerDrawnCards;

        // clear the storage with _clear
        _clear(user, initialRequestId);

        // update all mappings
        s_balances[user] -= bet;

        // emit an event
        emit Loss(bet, user, cardsUser, cardsDealer);

        return true;
    }

    /**
     * @dev Clears the lobby and allows the user to start a new game
     * @param user Player address
     * @param initialRequestId Request ID used in lobby creation
     */
    function _clear(address user, uint256 initialRequestId) internal returns(bool){
        uint256[] memory indices = s_usedIndices[user];
        s_lockedForPayout -= (s_userToCurrentLobby[user].PlayerBet * PAYOUT_NUM) / PAYOUT_DENUM;
        delete s_requestIdToLobby[initialRequestId];
        delete s_userToCurrentLobby[user];
        for (uint256 i; i < indices.length; i++){
            delete s_drawnCards[user][i];
        }
        delete s_usedIndices[user];
        s_currentlyInGame[user] = false;
        s_isUsersTurn[user] = false;

        return true;
    }

    /**
     * @dev Called if the user wins
     * @param lobby Current lobby
     */
    function _win(Lobby memory lobby) internal returns(bool){
        address user = lobby.Player;
        uint256 bet = lobby.PlayerBet;
        uint256 initialRequestId = lobby.InitialRequestId;
        uint256[] memory playerCards = lobby.PlayerDrawnCards;
        uint256[] memory dealerCards = lobby.DealerDrawnCards;

        _clear(user, initialRequestId);

        uint256 winAmount = (bet * PAYOUT_NUM) / PAYOUT_DENUM;
        s_balances[user] += winAmount;

        emit Win(winAmount,user,playerCards, dealerCards);
        return true;
    }

    /**
     * @dev Is called if player wins insurance bet.
     * @param user Player address
     */
    function _winInsurance(address user) internal {
        Lobby memory lobby = s_userToCurrentLobby[user];
        uint256 bet = lobby.InsuranceBet;
        uint256 win = bet * 2;

        s_balances[user] += win;
        s_lockedForPayout -= win;
        emit InsuranceWon(user, win);
    }

    /**
     * @dev Is called if player looses insurance bet.
     * @param user Player address
     */
    function _looseInsurance(address user) internal {
        Lobby memory lobby = s_userToCurrentLobby[user];
        uint256 bet = lobby.InsuranceBet;

        s_balances[user] -= bet;
        s_lockedForPayout -= bet * 2;
        emit InsuranceLost(user, bet);
    }
}