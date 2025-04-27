// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {VRFCoordinatorV2_5Mock} from "lib/chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {F3BlackJack} from "../src/F3BlackJack.sol";
import {DeployF3BlackJack} from "../script/DeployF3BlackJack.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";


contract BlackJackTest is Test {

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    F3BlackJack public blackjack;
    HelperConfig public helperConfig; 

    address private player = makeAddr("player");
    address private zeroBalancePlayer = makeAddr("zero");
    address private newOwner = makeAddr("owner");

    uint256 public minimalBet = 1e10;

    // Chainlink parameters
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;

    uint256[] public randomWords;
    uint256[] public randomWordsDoubleDown;
    uint256[] public randomWordsDraw;
    uint256[] public randomWordsStand;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Withdrawn(address indexed player, uint256 indexed amount);
    event GameStarted(address indexed player, uint256 indexed lobbyId);
    event RequestFulfilled(uint256 indexed requestId);
    event Win(uint256 indexed amount, address indexed user, uint256[] cardsUser, uint256[] cardsDealer);
    event Loss(uint256 indexed amount, address indexed user, uint256[] cardsUser, uint256[] cardsDelaer);
    event Tie(address indexed user, uint256[] userCards, uint256[] dealerCards);
    event Drawn(address indexed user, uint256 indexed value);
    event DrawRequested(uint256 indexed requestId);
    event InsuranceWon(address indexed user, uint256 indexed amount);
    event InsuranceLost(address indexed user, uint256 indexed amount);
    event Stand(address indexed user, uint256 indexed totalValue);
    event MinimalBetSet(uint256 newMinimalBet);

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        DeployF3BlackJack deployer = new DeployF3BlackJack();
        (blackjack, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;

        // Label addresses
        vm.deal(player, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Simplified copy of _retrieveCardFromSeed from F3BlackJack
     */
    function _retrieveCardFromSeed(
        uint256 _seed, 
        uint256 _cardTotal
        ) internal pure returns(uint256, uint256) {
        uint256 index = _seed % 52 + 1;
        uint256 rank = index % 13 + 1;
        if (rank == 11 || rank == 12 || rank == 13) {
            return (10, rank);
        } else if (rank == 1 && _cardTotal >= 11){
            return (1, rank);
        } else if (rank == 1 && _cardTotal < 11) {
            return (11, rank);
        } else {
            return (rank, rank);
        }
    } 

    /**
     * Binds a value to a certain congruence class as follows:
     * ((x mod 52) + 1) mod 13 = [congruence class] mod 13
     * @param x Input seed
     * @param target Target congruence class
     */
    function bindToMod52Shift1Mod13(uint256 x, uint256 target) internal pure returns (uint256) {
        uint256 required = (target + 13 - 1) % 13;

        uint256[4] memory validYs;
        uint256 count = 0;
        for (uint256 candidate = required; candidate < 52; candidate += 13) {
            validYs[count++] = candidate;
        }

        uint256 yIndex = x % count;
        uint256 y = validYs[yIndex];
        uint256 k = x / 52;

        return k * 52 + y;
    }

    /**
     * Deposits the amount and calls startGame pranking the user
     * @param amount Amount to deposit
     * @param user Address of the player
     */
    function fund(uint256 amount, address user) public {
        // deposit 
        vm.startPrank(user);
        blackjack.deposit{value: amount}();
        vm.stopPrank();
    }

    function depositAndStartGame(uint256 amount, address user) public {
        vm.startPrank(user);
        blackjack.deposit{value: amount}();

        blackjack.startGame(amount / 4);
        vm.stopPrank();
    }

    function addRandomWords(uint256 word) public {
        randomWords.push(word);
    }

    function setDoubleDownAndInsurance(uint256 first, uint256 second, uint256 third) public {
        first = bindToMod52Shift1Mod13(first,3);
        second = bindToMod52Shift1Mod13(second,0);
        third = bindToMod52Shift1Mod13(third,4);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);
    }

    function setDoubleDownDealerLoss(uint256 first, uint256 second, uint256 third) public {
        first = bindToMod52Shift1Mod13(first,3);
        second = bindToMod52Shift1Mod13(second,3);
        third = bindToMod52Shift1Mod13(third,4);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);
    }

    function setInsurance(uint256 first, uint256 second, uint256 third) public {
        first = bindToMod52Shift1Mod13(first,6);
        second = bindToMod52Shift1Mod13(second,0);
        third = bindToMod52Shift1Mod13(third,6);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);
    }

    function ordinarySetup(uint256 first, uint256 second, uint256 third) public {
        first = bindToMod52Shift1Mod13(first,5);
        second = bindToMod52Shift1Mod13(second,1);
        third = bindToMod52Shift1Mod13(third,5);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);
    }

    function gameLost(uint256 drawCard, uint256 additionalCard, uint256 standSeed) public {
        drawCard = bound(drawCard, 1, 1000);
        additionalCard = bound(additionalCard, 1, 1000);
        standSeed = bound(standSeed, 1, 1000);
        depositAndStartGame(1e18, player);
        
        uint256 first;
        uint256 second;
        uint256 third;
        first = bindToMod52Shift1Mod13(first,7);
        second = bindToMod52Shift1Mod13(second,0);
        third = bindToMod52Shift1Mod13(third,6);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.startPrank(player);
        blackjack.draw();
        vm.stopPrank();

        drawCard = bindToMod52Shift1Mod13(drawCard, 0);
        additionalCard = bindToMod52Shift1Mod13(additionalCard, 11);
        randomWordsDraw.push(drawCard);
        randomWordsDraw.push(additionalCard);

        F3BlackJack.Lobby memory lobbyBefore = blackjack.getUsersCurrentLobby(player);
        uint256 lastRequestId = lobbyBefore.LastRequestId;

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsDraw
        );

        vm.prank(player);
        blackjack.stand();

        F3BlackJack.Lobby memory lobbyAfter = blackjack.getUsersCurrentLobby(player);

        standSeed = bindToMod52Shift1Mod13(standSeed, 10);
        randomWordsStand.push(standSeed);

        lastRequestId = lobbyAfter.LastRequestId;

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsStand
        );
    }


    /*//////////////////////////////////////////////////////////////
                      DEPOSITS AND WITHDRAWS TESTS
    //////////////////////////////////////////////////////////////*/    

    function testDepositWorks(uint256 amount) public {
        amount = bound(amount, blackjack.getMinimalDepositAmount(), 1e18);
        vm.prank(player);
        blackjack.deposit{value: amount}();
        assertEq(amount, blackjack.getBalance(player));
    }

    function testDepositInsufficientReverts(uint256 amount) public {
        amount = bound(amount, 0, blackjack.getMinimalDepositAmount());
        vm.startPrank(player);
        vm.expectRevert();
        blackjack.deposit{value: minimalBet / 2}();
        vm.stopPrank();
    }

    function testCannotDepositWhilePaused() public {
        address owner = blackjack.owner();
        vm.prank(owner);
        blackjack.pause();

        vm.expectRevert(F3BlackJack.F3BlackJack__ContractIsPaused.selector);

        fund(1e18, player);
    }

    function testCannotDepositWhileInGame() public {
        fund(1e18, player);
        vm.startPrank(player);
        blackjack.startGame(1e15);

        vm.expectRevert(F3BlackJack.F3BlackJack__CannotStartOrDepositWhileGameActive.selector);
        fund(1e18, player);
    }

    function testDepositandWithdraw(uint256 amount) public {
        amount = bound(amount, blackjack.getMinimalDepositAmount(), 1e18);
        vm.startPrank(player);
        blackjack.deposit{value: amount}();
        vm.expectEmit(true, true, false, false, address(blackjack));
        emit Withdrawn(player, amount);

        blackjack.withdraw(amount);
        vm.stopPrank();
        assertEq(blackjack.getBalance(player), 0);
    }

    function testWithdrawRevertsWithZeroBalance() public {
        vm.prank(player);
        vm.expectRevert(F3BlackJack.F3BlackJack__NothingToWithdraw.selector);
        blackjack.withdraw(0);
    }

    function testCannotWithdrawWhileInGame() public {
        fund(1e18, player);
        vm.startPrank(player);

        blackjack.startGame(1e15);

        vm.expectRevert(F3BlackJack.F3BlackJack__CannotStartOrDepositWhileGameActive.selector);
        blackjack.withdraw(1e15);

    }

    function testWithdrawMaximalBalance(uint256 amount) public {
        vm.startPrank(player);
        uint256 balance = 1e17;
        blackjack.deposit{value: balance}();
        amount = bound(amount, balance + 1, type(uint256).max);

        vm.expectEmit(true, true, false, false, address(blackjack));
        emit Withdrawn(player, balance);

        blackjack.withdraw(amount);
        vm.stopPrank();
        assertEq(blackjack.getBalance(player), 0);
    }

    function testWithdrawHouseEdgeWorks() public {
        gameLost(201,202,203);

        depositAndStartGame(1e12, player);

        vm.prank(blackjack.owner());
        blackjack.transferOwnership(newOwner);

        vm.prank(newOwner);
        blackjack.acceptOwnership();

        vm.prank(newOwner);
        blackjack.withdrawHouseEdge(newOwner, 1e10);
    }

    function testUnsafeHouseEdgeWithdrawalReverts() public {
        gameLost(201,202,203);

        depositAndStartGame(3e18, player);

        vm.prank(blackjack.owner());
        blackjack.transferOwnership(newOwner);

        vm.prank(newOwner);
        blackjack.acceptOwnership();

        vm.prank(newOwner);
        vm.expectRevert(F3BlackJack.F3BlackJack__UnsafeHouseEdgeWithdrawal.selector);
        blackjack.withdrawHouseEdge(newOwner, 3e18);
    }

    function testWithdrawAllFunds() public {
        gameLost(201,202,203);

        vm.prank(blackjack.owner());
        blackjack.transferOwnership(newOwner);

        vm.startPrank(newOwner);
        blackjack.acceptOwnership();
        blackjack.pause();
        vm.expectEmit(true,true,false,false,address(blackjack));
        emit Withdrawn(newOwner, address(blackjack).balance);

        blackjack.withdrawAllFunds(newOwner);
    }

    function testCannotWithdrawAllWhileActiveLobbies() public {
        gameLost(201,202,203);

        depositAndStartGame(3e18, player);

        vm.prank(blackjack.owner());
        blackjack.transferOwnership(newOwner);

        vm.startPrank(newOwner);
        blackjack.acceptOwnership();
        blackjack.pause();
        vm.expectRevert(F3BlackJack.F3BlackJack__CannotWithdrawAllWhileOpenAndLiveLobby.selector);

        blackjack.withdrawAllFunds(newOwner);
    }

    function testCannotWithdrawAllWhileContractUnlocked() public {
        gameLost(201,202,203);

        vm.prank(blackjack.owner());
        blackjack.transferOwnership(newOwner);

        vm.startPrank(newOwner);
        blackjack.acceptOwnership();

        vm.expectRevert(F3BlackJack.F3BlackJack__CannotWithdrawAllWhileOpenAndLiveLobby.selector);

        blackjack.withdrawAllFunds(newOwner);
    }

    function testPause() public {
        address owner = blackjack.owner();
        vm.prank(owner);
        blackjack.pause();

        assertEq(true, blackjack.getPauseStatus());
    }

    function testUnpause() public {
        address owner = blackjack.owner();
        vm.startPrank(owner);
        blackjack.pause();
        blackjack.unpause();
        vm.stopPrank();

        assertEq(false, blackjack.getPauseStatus());
    }

    function testSetMinimalBet() public {
        address owner = blackjack.owner();
        vm.prank(owner);
        vm.expectEmit(true, false, false, false, address(blackjack));
        emit MinimalBetSet(1e14);
        blackjack.setMinimalBet(1e14);
    }

    /*//////////////////////////////////////////////////////////////
                            DRAW LOGIC TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * One way to test if the card rank is recieved correctly is
     * to bound seed values to the the following format:
     * ((value mod 52) + 1) mod 13 = [congruence class] mod 13
     * This is done with a helper function bindToMod52Shift1Mod13
     * So we can restrict the random seed so it always produces the card with
     * the desired rank. 
     * @param seed Random seed
     */


    function testRetrieveCardFromSeedReturnsRightTens(uint256 seed, uint256 class) public pure {
        // Test only tens and face cards here
        class = bound(class, 9, 12);
        seed = bound(seed, 0, 1e30);
        seed = bindToMod52Shift1Mod13(seed, class);

        uint256 expectedValue = 10;
        uint256 expectedRank = class + 1;

        (uint256 value, uint256 rank) = _retrieveCardFromSeed(seed, 11 /*Not important here*/);
        assertEq(value, expectedValue);
        assertEq(rank, expectedRank);
    }

    function testRetrieveCardFromSeedReturnsRightNumbers(uint256 seed, uint256 class) public pure {
        // Test only number card except tens here
        class = bound(class, 1, 9);
        seed = bound(seed, 0, 1e30);
        seed = bindToMod52Shift1Mod13(seed, class);

        uint256 expectedRank = class + 1;

        (uint256 value, uint256 rank) = _retrieveCardFromSeed(seed, 11 /*Not important here*/);
        assertEq(value, rank);
        assertEq(rank, expectedRank);
    }

    function testRetrieveCardFromSeedReturnsSoftAce(uint256 seed) public pure {
        // Test only number card except tens here
        uint256 class = 0;
        seed = bound(seed, 0, 1e30);
        seed = bindToMod52Shift1Mod13(seed, class);

        uint256 expectedRank = class + 1;
        uint256 expectedValue = 11;

        (uint256 value, uint256 rank) = _retrieveCardFromSeed(seed, 10);
        assertEq(value, expectedValue);
        assertEq(rank, expectedRank);
    }

    function testRetrieveCardFromSeedReturnsHardAce(uint256 seed) public pure {
        // Test only number card except tens here
        uint256 class = 0;
        seed = bound(seed, 0, 1e30);
        seed = bindToMod52Shift1Mod13(seed, class);

        uint256 expectedRank = class + 1;
        uint256 expectedValue = 1;

        (uint256 value, uint256 rank) = _retrieveCardFromSeed(seed, 11);
        assertEq(value, expectedValue);
        assertEq(rank, expectedRank);    
    }


    function testBindToMod52Shift1Mod13(uint256 x, uint256 class) public pure {
        class = bound(class, 0, 12);
        x = bound(x, 0, 1e30);
        uint256 value = bindToMod52Shift1Mod13(x, class);

        assertEq(((value % 52) + 1) % 13, class);
    }


    
    /*//////////////////////////////////////////////////////////////
                              LOBBY TESTS
    //////////////////////////////////////////////////////////////*/

    function testStartGame() public {
        fund(1e18, player);
        vm.startPrank(player);
        vm.expectEmit(true, true, false, false, address(blackjack));
        emit GameStarted(player, 0);
        
        blackjack.startGame(1e16);
    }

    function testStartGameBetCheckWorks() public {
        fund(1e18, player);
        vm.startPrank(player);
        vm.expectEmit(true, true, false, false, address(blackjack));
        emit GameStarted(player, 0);
        
        blackjack.startGame(1e20);
    }

    function testCannotCreateSecondLobby() public {
        fund(1e18, player);
        vm.startPrank(player);

        blackjack.startGame(1e16);
        vm.expectRevert(F3BlackJack.F3BlackJack__CannotStartOrDepositWhileGameActive.selector);
        blackjack.startGame(1e16);
    }

    function testCannotStartBelowMinimalBet() public {
        fund(1e18, player);

        vm.prank(blackjack.owner());
        blackjack.setMinimalBet(1e5);

        vm.startPrank(player);
        vm.expectRevert();
        blackjack.startGame(1e5-1);
    }

    function testCannotCreateLobbyWhilePaused() public {
        address owner = blackjack.owner();
        fund(1e18, player);
        vm.prank(owner);
        blackjack.pause();

        vm.startPrank(player);
        vm.expectRevert(F3BlackJack.F3BlackJack__ContractIsPaused.selector);

        blackjack.startGame(1e16);

    }

    function testFulfillRandomWordsInitialDraw() public {
        depositAndStartGame(1e18, player);

        uint256 requestId = blackjack.requestIds(0);
        vm.expectEmit(true, false, false, false, address(blackjack));
        emit RequestFulfilled(1);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );
    }

    function testInsuranceAndDoubleDownSetCorrectly() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        F3BlackJack.Lobby memory lobby = blackjack.getUsersCurrentLobby(player);
        assertEq(lobby.CanInsure, true);
        assertEq(lobby.CanDoubleDown, true);
    }

    function testCannotDoubleDownIfFalse() public {
        depositAndStartGame(1e18, player);
        ordinarySetup(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.prank(player);
        vm.expectRevert(F3BlackJack.F3BlackJack__CannotDoubleDown.selector);
        blackjack.doubleDown();
    }

    function testCannotDoubleDownIfInsured() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.prank(player);
        blackjack.insurance(1e10);

        vm.expectRevert(F3BlackJack.F3BlackJack__CannotDoubleDownAfterInsurance.selector);
        vm.prank(player);
        blackjack.doubleDown();
    }

    function testCannotDoubleDownWithoutLobby() public {
        vm.expectRevert(F3BlackJack.F3BlackJack__LobbyNotCreated.selector);
        vm.prank(player);
        blackjack.doubleDown();
    }

    function testCannotDoubleDownIfNotUsersTurn() public {
        depositAndStartGame(1e18, player);

        vm.expectRevert(F3BlackJack.F3BlackJack__PleaseWaitCardsAreDrawn.selector);
        vm.prank(player);
        blackjack.doubleDown();
    }

    function testCannotInsureWhileDoubleDown() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.prank(player);
        blackjack.doubleDown();

        vm.prank(player);
        vm.expectRevert(F3BlackJack.F3BlackJack__PleaseWaitCardsAreDrawn.selector);
        blackjack.insurance(1e5);

    }

    function testCannotInsureMoreThanHalf() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.prank(player);
        vm.expectRevert(F3BlackJack.F3BlackJack__CanInsureUpToHalfTHeOriginalBet.selector);
        blackjack.insurance(2e17);
    }

    function testCannotInsureInsufficientBalance() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.prank(player);
        vm.expectRevert(F3BlackJack.F3BlackJack__InsufficientBalance.selector);
        blackjack.insurance(2e30);
    }

    function testCannotInsureIfDealerCardIsNotAnAce() public {
        depositAndStartGame(1e18, player);
        
        uint256 first = 17;
        uint256 second = 18;
        uint256 third = 19;
        first = bindToMod52Shift1Mod13(first,10);
        second = bindToMod52Shift1Mod13(second, 2);
        third = bindToMod52Shift1Mod13(third,11);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.startPrank(player);
        vm.expectRevert(F3BlackJack.F3BlackJack__CannotInsure.selector);
        blackjack.insurance(1e10);
    }

    function testFulfillRandomWordsDoubleDownWin() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        uint256 first = bindToMod52Shift1Mod13(123123, 4);
        uint256 second = bindToMod52Shift1Mod13(123123, 2);
        randomWordsDoubleDown.push(first);
        randomWordsDoubleDown.push(second);


        vm.prank(player);
        blackjack.doubleDown();

        F3BlackJack.Lobby memory lobbyBefore = blackjack.getUsersCurrentLobby(player);
        uint256 lastRequestId = lobbyBefore.LastRequestId;

        vm.expectEmit(false, false, false, false, address(blackjack));
        // Random event parameters, important is that it's emitted 
        emit Win(1e18, player,lobbyBefore.PlayerDrawnCards, lobbyBefore.DealerDrawnCards);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsDoubleDown
        );
    }

    function testFulfillRandomWordsDoubleDownWinWhenDealerBusts() public {
        depositAndStartGame(1e18, player);
        setDoubleDownDealerLoss(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        uint256 first = bindToMod52Shift1Mod13(123123, 4);
        uint256 second = bindToMod52Shift1Mod13(123124, 4);
        randomWordsDoubleDown.push(first);
        randomWordsDoubleDown.push(second);


        vm.prank(player);
        blackjack.doubleDown();

        F3BlackJack.Lobby memory lobbyBefore = blackjack.getUsersCurrentLobby(player);
        uint256 lastRequestId = lobbyBefore.LastRequestId;

        vm.expectEmit(false, false, false, false, address(blackjack));
        // Random event parameters, important is that it's emitted 
        emit Win(1e18, player,lobbyBefore.PlayerDrawnCards, lobbyBefore.DealerDrawnCards);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsDoubleDown
        );
    }

    function testFulfillRandomWordsDoubleDownLossDealerBlackJack() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        uint256 first = bindToMod52Shift1Mod13(123123, 4);
        uint256 second = bindToMod52Shift1Mod13(123124, 10);
        randomWordsDoubleDown.push(first);
        randomWordsDoubleDown.push(second);


        vm.prank(player);
        blackjack.doubleDown();

        F3BlackJack.Lobby memory lobbyBefore = blackjack.getUsersCurrentLobby(player);
        uint256 lastRequestId = lobbyBefore.LastRequestId;

        vm.expectEmit(false, false, false, false, address(blackjack));
        // Random event parameters, important is that it's emitted 
        emit Loss(1e18, player,lobbyBefore.PlayerDrawnCards, lobbyBefore.DealerDrawnCards);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsDoubleDown
        );
    }

    function testFulfillRandomWordsDoubleDownLossTotalPoints() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        uint256 first = bindToMod52Shift1Mod13(123123, 4);
        uint256 second = bindToMod52Shift1Mod13(123124, 8);
        randomWordsDoubleDown.push(first);
        randomWordsDoubleDown.push(second);


        vm.prank(player);
        blackjack.doubleDown();

        F3BlackJack.Lobby memory lobbyBefore = blackjack.getUsersCurrentLobby(player);
        uint256 lastRequestId = lobbyBefore.LastRequestId;

        vm.expectEmit(false, false, false, false, address(blackjack));
        // Random event parameters, important is that it's emitted 
        emit Loss(1e18, player,lobbyBefore.PlayerDrawnCards, lobbyBefore.DealerDrawnCards);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsDoubleDown
        );
    }

    function testFulfillRandomWordsDoubleDownWinTotalPoints() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        uint256 first = bindToMod52Shift1Mod13(123123, 10);
        uint256 second = bindToMod52Shift1Mod13(123124, 4);
        randomWordsDoubleDown.push(first);
        randomWordsDoubleDown.push(second);


        vm.prank(player);
        blackjack.doubleDown();

        F3BlackJack.Lobby memory lobbyBefore = blackjack.getUsersCurrentLobby(player);
        uint256 lastRequestId = lobbyBefore.LastRequestId;

        vm.expectEmit(false, false, false, false, address(blackjack));
        // Random event parameters, important is that it's emitted 
        emit Win(1e18, player,lobbyBefore.PlayerDrawnCards, lobbyBefore.DealerDrawnCards);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsDoubleDown
        );
    }

    function testFulfillRandomWordsDoubleDownTie() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        uint256 first = bindToMod52Shift1Mod13(123123, 0);
        uint256 second = bindToMod52Shift1Mod13(123124, 8);
        randomWordsDoubleDown.push(first);
        randomWordsDoubleDown.push(second);


        vm.prank(player);
        blackjack.doubleDown();

        F3BlackJack.Lobby memory lobbyBefore = blackjack.getUsersCurrentLobby(player);
        uint256 lastRequestId = lobbyBefore.LastRequestId;

        vm.expectEmit(false, false, false, false, address(blackjack));
        // Random event parameters, important is that it's emitted 
        emit Tie(player,lobbyBefore.PlayerDrawnCards, lobbyBefore.DealerDrawnCards);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsDoubleDown
        );
    }

    function testCanDraw() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        uint256 first = bindToMod52Shift1Mod13(123123, 0);
        uint256 second = bindToMod52Shift1Mod13(123124, 8);
        randomWordsDoubleDown.push(first);
        randomWordsDoubleDown.push(second);

        vm.expectEmit(true,false,false,false, address(blackjack));
        emit DrawRequested(2);

        vm.prank(player);
        blackjack.draw();
    }

    function testCannotDrawIfNotPlayersTurn() public {
        depositAndStartGame(1e18, player);

        vm.prank(player);
        vm.expectRevert(F3BlackJack.F3BlackJack__PleaseWaitCardsAreDrawn.selector);
        blackjack.draw();
    }

    function testCannotDrawWithNoLobby() public {
        vm.prank(player);
        vm.expectRevert(F3BlackJack.F3BlackJack__LobbyNotCreated.selector);
        blackjack.draw();        
    }

    function testCardIsDrawnCorrectly(uint256 drawCard, uint256 additionalCard) public {
        drawCard = bound(drawCard, 1, 1000);
        additionalCard = bound(additionalCard, 1, 1000);
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1000,1001);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.prank(player);
        blackjack.draw();

        F3BlackJack.Lobby memory lobbyBefore = blackjack.getUsersCurrentLobby(player);
        uint256 lastRequestId = lobbyBefore.LastRequestId;

        console2.log("Lobby player", lobbyBefore.Player);

        drawCard = bindToMod52Shift1Mod13(drawCard, 6);
        additionalCard = bindToMod52Shift1Mod13(additionalCard, 5);
        randomWordsDraw.push(drawCard);
        randomWordsDraw.push(additionalCard);

        vm.expectEmit(true, false, false, false, address(blackjack));
        emit Drawn(player, 9);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsDraw
        );

    }

    function testDrawMoreThanTwentyOneAndWinInsurance(uint256 drawCard, uint256 additionalCard) public {
        drawCard = bound(drawCard, 1, 1000);
        additionalCard = bound(additionalCard, 1, 1000);
        depositAndStartGame(1e18, player);

        uint256 first;
        uint256 second;
        uint256 third;
        first = bindToMod52Shift1Mod13(first,10);
        second = bindToMod52Shift1Mod13(second,0);
        third = bindToMod52Shift1Mod13(third,10);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.startPrank(player);
        blackjack.insurance(1e10);
        blackjack.draw();
        vm.stopPrank();

        F3BlackJack.Lobby memory lobbyBefore = blackjack.getUsersCurrentLobby(player);
        uint256 lastRequestId = lobbyBefore.LastRequestId;

        drawCard = bindToMod52Shift1Mod13(drawCard, 3);
        additionalCard = bindToMod52Shift1Mod13(additionalCard, 11);
        randomWordsDraw.push(drawCard);
        randomWordsDraw.push(additionalCard);

        vm.expectEmit(true, true, false, false, address(blackjack));
        emit InsuranceWon(player, 2e10);
        vm.expectEmit(false, true, false, false, address(blackjack));
        emit Loss(1e18, player,lobbyBefore.PlayerDrawnCards, lobbyBefore.DealerDrawnCards);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsDraw
        );

    }

    function testDrawMoreThanTwentyOneAndLooseInsurance(uint256 drawCard, uint256 additionalCard) public {
        drawCard = bound(drawCard, 1, 1000);
        additionalCard = bound(additionalCard, 1, 1000);
        depositAndStartGame(1e18, player);

        uint256 first;
        uint256 second;
        uint256 third;
        first = bindToMod52Shift1Mod13(first,10);
        second = bindToMod52Shift1Mod13(second,0);
        third = bindToMod52Shift1Mod13(third,10);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.startPrank(player);
        blackjack.insurance(1e10);
        blackjack.draw();
        vm.stopPrank();

        F3BlackJack.Lobby memory lobbyBefore = blackjack.getUsersCurrentLobby(player);
        uint256 lastRequestId = lobbyBefore.LastRequestId;

        drawCard = bindToMod52Shift1Mod13(drawCard, 3);
        additionalCard = bindToMod52Shift1Mod13(additionalCard, 5);
        randomWordsDraw.push(drawCard);
        randomWordsDraw.push(additionalCard);

        vm.expectEmit(true, true, false, false, address(blackjack));
        emit InsuranceLost(player, 1e10);
        vm.expectEmit(false, true, false, false, address(blackjack));
        emit Loss(1e18, player,lobbyBefore.PlayerDrawnCards, lobbyBefore.DealerDrawnCards);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsDraw
        );
    }

    function testStandWorks() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1001,1002);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        F3BlackJack.Lobby memory lobby = blackjack.getUsersCurrentLobby(player);
        vm.expectEmit(true,true,false,false, address(blackjack));
        emit Stand(player, lobby.PlayerCardTotal);

        vm.prank(player);
        blackjack.stand();
    }

    function testCannotDrawAfterStand() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1001,1002);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.prank(player);
        blackjack.stand();

        vm.expectRevert(F3BlackJack.F3BlackJack__PleaseWaitCardsAreDrawn.selector);
        vm.prank(player);
        blackjack.draw();
    }

    function testCannotInsurefterStand() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1001,1002);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.prank(player);
        blackjack.stand();

        vm.expectRevert(F3BlackJack.F3BlackJack__PleaseWaitCardsAreDrawn.selector);
        vm.prank(player);
        blackjack.insurance(1e10);
    }

    function testCannotDoubleDownAfterStand() public {
        depositAndStartGame(1e18, player);
        setDoubleDownAndInsurance(1000,1001,1002);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.prank(player);
        blackjack.stand();

        vm.expectRevert(F3BlackJack.F3BlackJack__PleaseWaitCardsAreDrawn.selector);
        vm.prank(player);
        blackjack.doubleDown();
    }

    function testCannotStandIfNotYourTurn() public {
        depositAndStartGame(1e18, player);

        vm.prank(player);
        vm.expectRevert(F3BlackJack.F3BlackJack__PleaseWaitCardsAreDrawn.selector);
        blackjack.stand();
    }

    function testCannotStandIfNoLobby() public {
        vm.prank(player);
        vm.expectRevert(F3BlackJack.F3BlackJack__LobbyNotCreated.selector);
        blackjack.stand();      
    }


    function testFulfillRandomWordsStandInsuranceWin(uint256 drawCard, uint256 additionalCard, uint256 standSeed) public {
        drawCard = bound(drawCard, 1, 1000);
        additionalCard = bound(additionalCard, 1, 1000);
        standSeed = bound(standSeed, 1, 1000);
        depositAndStartGame(1e18, player);
        
        uint256 first;
        uint256 second;
        uint256 third;
        first = bindToMod52Shift1Mod13(first,7);
        second = bindToMod52Shift1Mod13(second,0);
        third = bindToMod52Shift1Mod13(third,6);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.startPrank(player);
        blackjack.insurance(1e10);
        blackjack.draw();
        vm.stopPrank();

        drawCard = bindToMod52Shift1Mod13(drawCard, 0);
        additionalCard = bindToMod52Shift1Mod13(additionalCard, 11);
        randomWordsDraw.push(drawCard);
        randomWordsDraw.push(additionalCard);

        F3BlackJack.Lobby memory lobbyBefore = blackjack.getUsersCurrentLobby(player);
        uint256 lastRequestId = lobbyBefore.LastRequestId;

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsDraw
        );

        vm.prank(player);
        blackjack.stand();

        F3BlackJack.Lobby memory lobbyAfter = blackjack.getUsersCurrentLobby(player);

        standSeed = bindToMod52Shift1Mod13(standSeed, 10);
        randomWordsStand.push(standSeed);

        lastRequestId = lobbyAfter.LastRequestId;

        vm.expectEmit(true, true, false, false, address(blackjack));
        emit InsuranceWon(player, 2e10);
        vm.expectEmit(false, true, false, false, address(blackjack));
        emit Loss(1e18, player,lobbyBefore.PlayerDrawnCards, lobbyBefore.DealerDrawnCards);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsStand
        );
    }

    function testFulfillRandomWordsStandInsuranceLoss(uint256 drawCard, uint256 additionalCard, uint256 standSeed) public {
        drawCard = bound(drawCard, 1, 1000);
        additionalCard = bound(additionalCard, 1, 1000);
        standSeed = bound(standSeed, 1, 1000);
        depositAndStartGame(1e18, player);
        
        uint256 first;
        uint256 second;
        uint256 third;
        first = bindToMod52Shift1Mod13(first,7);
        second = bindToMod52Shift1Mod13(second,0);
        third = bindToMod52Shift1Mod13(third,6);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.startPrank(player);
        blackjack.insurance(1e10);
        blackjack.draw();
        vm.stopPrank();

        drawCard = bindToMod52Shift1Mod13(drawCard, 0);
        additionalCard = bindToMod52Shift1Mod13(additionalCard, 11);
        randomWordsDraw.push(drawCard);
        randomWordsDraw.push(additionalCard);

        F3BlackJack.Lobby memory lobbyBefore = blackjack.getUsersCurrentLobby(player);
        uint256 lastRequestId = lobbyBefore.LastRequestId;

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsDraw
        );

        vm.prank(player);
        blackjack.stand();

        F3BlackJack.Lobby memory lobbyAfter = blackjack.getUsersCurrentLobby(player);

        standSeed = bindToMod52Shift1Mod13(standSeed, 5);
        randomWordsStand.push(standSeed);

        lastRequestId = lobbyAfter.LastRequestId;

        vm.expectEmit(true, true, false, false, address(blackjack));
        emit InsuranceLost(player, 1e10);
        vm.expectEmit(false, true, false, false, address(blackjack));
        emit Loss(1e18, player,lobbyBefore.PlayerDrawnCards, lobbyBefore.DealerDrawnCards);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsStand
        );
    }

    function testFulfillRandomWordsStandInsuranceLossPlayerBlackjack(uint256 drawCard, uint256 additionalCard, uint256 standSeed) public {
        drawCard = bound(drawCard, 1, 1000);
        additionalCard = bound(additionalCard, 1, 1000);
        standSeed = bound(standSeed, 1, 1000);
        depositAndStartGame(1e18, player);
        
        uint256 first = 17;
        uint256 second = 18;
        uint256 third = 19;
        first = bindToMod52Shift1Mod13(first,0);
        second = bindToMod52Shift1Mod13(second,0);
        third = bindToMod52Shift1Mod13(third,10);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.startPrank(player);
        blackjack.insurance(1e10);
        blackjack.stand();
        vm.stopPrank();

        F3BlackJack.Lobby memory lobbyAfter = blackjack.getUsersCurrentLobby(player);

        standSeed = bindToMod52Shift1Mod13(standSeed, 5);
        randomWordsStand.push(standSeed);

        uint256 lastRequestId = lobbyAfter.LastRequestId;

        vm.expectEmit(true, true, false, false, address(blackjack));
        emit InsuranceLost(player, 1e10);
        vm.expectEmit(false, true, false, false, address(blackjack));
        emit Win(1e18, player,lobbyAfter.PlayerDrawnCards, lobbyAfter.DealerDrawnCards);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsStand
        );
    }

    function testFulfillRandomWordsStandInsuranceWinDraw21(uint256 drawCard, uint256 additionalCard, uint256 standSeed) public {
        drawCard = bound(drawCard, 1, 1000);
        additionalCard = bound(additionalCard, 1, 1000);
        standSeed = bound(standSeed, 1, 1000);
        depositAndStartGame(1e18, player);
        
        uint256 first = 17;
        uint256 second = 18;
        uint256 third = 19;
        first = bindToMod52Shift1Mod13(first,0);
        second = bindToMod52Shift1Mod13(second,0);
        third = bindToMod52Shift1Mod13(third,10);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.startPrank(player);
        blackjack.insurance(1e10);
        blackjack.stand();
        vm.stopPrank();

        F3BlackJack.Lobby memory lobbyAfter = blackjack.getUsersCurrentLobby(player);

        standSeed = bindToMod52Shift1Mod13(standSeed, 11);
        randomWordsStand.push(standSeed);

        uint256 lastRequestId = lobbyAfter.LastRequestId;

        vm.expectEmit(true, true, false, false, address(blackjack));
        emit InsuranceWon(player, 2e10);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsStand
        );
    }

    function testFulfillRandomWordsStandDealerCardsCalculatedRight(uint256 drawCard, uint256 additionalCard, uint256 standSeed) public {
        drawCard = bound(drawCard, 1, 1000);
        additionalCard = bound(additionalCard, 1, 1000);
        standSeed = bound(standSeed, 1, 1000);
        depositAndStartGame(1e18, player);
        
        uint256 first = 17;
        uint256 second = 18;
        uint256 third = 19;
        first = bindToMod52Shift1Mod13(first,10);
        second = bindToMod52Shift1Mod13(second,4);
        third = bindToMod52Shift1Mod13(third,10);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.startPrank(player);
        blackjack.stand();
        vm.stopPrank();

        F3BlackJack.Lobby memory lobbyAfter = blackjack.getUsersCurrentLobby(player);

        standSeed = bindToMod52Shift1Mod13(standSeed, 5);
        randomWordsStand.push(standSeed);

        uint256 lastRequestId = lobbyAfter.LastRequestId;

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsStand
        );
    }

    function testFulfillRandomWordsStandDealerBustInsuranceLoss(uint256 drawCard, uint256 additionalCard, uint256 standSeed) public {
        drawCard = bound(drawCard, 1, 1000);
        additionalCard = bound(additionalCard, 1, 1000);
        standSeed = bound(standSeed, 1, 1000);
        depositAndStartGame(1e18, player);
        
        uint256 first = 17;
        uint256 second = 18;
        uint256 third = 19;
        first = bindToMod52Shift1Mod13(first,0);
        second = bindToMod52Shift1Mod13(second,0);
        third = bindToMod52Shift1Mod13(third,10);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.startPrank(player);
        blackjack.insurance(1e10);
        blackjack.stand();
        vm.stopPrank();

        F3BlackJack.Lobby memory lobbyAfter = blackjack.getUsersCurrentLobby(player);

        standSeed = bindToMod52Shift1Mod13(standSeed, 1);
        randomWordsStand.push(standSeed);

        uint256 lastRequestId = lobbyAfter.LastRequestId;

        vm.expectEmit(true, true, false, false, address(blackjack));
        emit InsuranceLost(player, 1e10);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsStand
        );
    }

    function testFulfillRandomWordsStandTieInsuranceLost(uint256 drawCard, uint256 additionalCard, uint256 standSeed) public {
        drawCard = bound(drawCard, 1, 1000);
        additionalCard = bound(additionalCard, 1, 1000);
        standSeed = bound(standSeed, 1, 1000);
        depositAndStartGame(1e18, player);
        
        uint256 first = 17;
        uint256 second = 18;
        uint256 third = 19;
        first = bindToMod52Shift1Mod13(first,10);
        second = bindToMod52Shift1Mod13(second, 0);
        third = bindToMod52Shift1Mod13(third,11);
        randomWords.push(first);
        randomWords.push(second);
        randomWords.push(third);

        uint256 requestId = blackjack.requestIds(0);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            requestId, 
            address(blackjack), 
            randomWords
        );

        vm.startPrank(player);
        blackjack.insurance(1e10);
        blackjack.stand();
        vm.stopPrank();

        F3BlackJack.Lobby memory lobbyAfter = blackjack.getUsersCurrentLobby(player);

        standSeed = bindToMod52Shift1Mod13(standSeed, 8);
        randomWordsStand.push(standSeed);

        uint256 lastRequestId = lobbyAfter.LastRequestId;

        vm.expectEmit(true, true, false, false, address(blackjack));
        emit InsuranceLost(player, 1e10);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWordsWithOverride(
            lastRequestId, 
            address(blackjack), 
            randomWordsStand
        );
    }

    /*//////////////////////////////////////////////////////////////
                         GETTER FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testGetMinimalDepositAmount() public view{
        blackjack.getMinimalDepositAmount();
    }

    function testGetBalance(address user) public view{
        blackjack.getBalance(user);
    }

    function testGetPauseStatus() public view {
        blackjack.getPauseStatus();
    }

    function testGetMinimalBet() public view {
        blackjack.getMinimalBet();
    }

    function testGetUsersCurrentLobby(address user) public view {
        blackjack.getUsersCurrentLobby(user);
    }
}