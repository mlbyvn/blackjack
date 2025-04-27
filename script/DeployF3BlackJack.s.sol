// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {F3BlackJack} from "../src/F3BlackJack.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "../script/Interactions.s.sol";

contract DeployF3BlackJack is Script {
    function run() public {
        deployContract();
    }

    function deployContract() public returns (F3BlackJack, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        // local -> deploy mocks, get local config
        // sepolia -> get the sepolia config
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        if (config.subscriptionId == 0) {
            //create a chainlink vrf subscription
            CreateSubscription createSubscription = new CreateSubscription();
            (config.subscriptionId, config.vrfCoordinator) = createSubscription
                .createSubscription(config.vrfCoordinator, config.account);

            //fund it
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                config.vrfCoordinator,
                config.subscriptionId,
                config.link,
                config.account
            );
        }

        vm.startBroadcast(config.account);
        F3BlackJack blackjack = new F3BlackJack(
            config.vrfCoordinator,
            1e12,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();
        // Dont need to broadcast, its already in AddConsumer
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            address(blackjack),
            config.vrfCoordinator,
            config.subscriptionId,
            config.account
        );
        return (blackjack, helperConfig);
    }
}