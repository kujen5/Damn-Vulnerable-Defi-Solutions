

# Overview

Hello everyone! Hope you are doing fantastic!

This is Foued SAIDI (0xkujen), senior pentester and a wannabe Web3/Blockhain Security Researcher.

Today I am launching the [Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/) series created by [The Red Guild](https://theredguild.org/) where I will be explaining in depth each challenge, my approach to solving it and my solutions.

Hope you enjoy it and learn something new!

# 'Unstoppable' challenge
 
## Challenge Description

There’s a tokenized vault with a million DVT tokens deposited. It’s offering flash loans for free, until the grace period ends.

To catch any bugs before going 100% permissionless, the developers decided to run a live beta in testnet. There’s a monitoring contract to check liveness of the flashloan feature.

Starting with 10 DVT tokens in balance, show that it’s possible to halt the vault. It must stop offering flash loans.

[Link to the original challenge](https://www.damnvulnerabledefi.xyz/challenges/unstoppable/)

# Understanding the contracts

## Overview

We have 3 main contracts

### DamnValuableToken.sol

This is the definition contract of the Damn Valuable Token (DVT): an [ERC20()](https://ethereum.org/developers/docs/standards/tokens/erc-20/) token that will be the currency (token) in this project.

We can see that this token has 18 decimals 
```solidity
contract DamnValuableToken is ERC20 {
    constructor() ERC20("DamnValuableToken", "DVT", 18) {
        _mint(msg.sender, type(uint256).max);
    }
}
```

### UnstoppableVault.sol

This will be the [ERC4626](https://ethereum.org/developers/docs/standards/tokens/erc-4626) vault tha will be managing [flash loans](https://eips.ethereum.org/EIPS/eip-3156) flash loans through the `UnstoppableVault::flashLoan()` function:

1. Check if the amount is valid:

`if (amount == 0) revert InvalidAmount(0);`

2. Check if the token is valid:

`if (address(asset) != _token) revert UnsupportedCurrency();`

3. Check if the total shares (number of shares to release in place of assets) is equal to the total assets before:

`if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();`

4. Execute flash loan logic from transferring the assets and making sure proper fees are applied through the `UnstoppableVault::flashFee()` function.

The `UnstoppableVault.sol` contract has other functions but for the sake of this challenge we will not be explaining all of them. `UnstoppableVault::flashLoan()` is the most important one.

### UnstoppableMonitor.sol

This is the IERC3156 contract that will be used to monitor the flash loaning feature of the `UnstoppableVault` contract through functions such as:

1. `UnstoppableVault::onFlashLoan()` which is required by the IERC3156 standard and called after a flash-loan request to validate loan parameters, approve payments, etc. 

2. `UnstoppableVault::checkFlashLoan()` which checks if the vault can still perform flash loans in a correct way by ensuring the amount is higher than 0, tries to perform a flash loan and sees if it executes correctly.

## Point of Failure

At first, this contracts looks good. The objective of this challenge as per the description is to try and make the vault `stop offering flash loans`. 

Stopping a smart contract from performing a normal behaviour is normally due to Denial of Service (DoS) attacks. You can read more about it with a few example on [my github repo for Smart Contract Attacks related to OWASP SC10: Denial of Service (DoS)](https://github.com/kujen5/Smart_Contract_Attacks/tree/main/SC10_Denial-of-Service-(DoS)-Attacks).


Usually, DoS exploits occur on the level of assertions and checks inside functions that try to make sure no unintended behaviour is occuring when calling the function.

Looking at the [UnstoppableVault ](#UnstoppableVault.sol) contract, we explained w few assertion on top of the `UnstoppableVault::flashLoan()`. One important check is to see if the total shares (number of shares to release in place of assets) is equal to the total assets before:

`if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();`

This could represent a huge issue for us, for a couple of reasons:

1. This check is happening on the most important function of the contract which grants the flash loans.

2. This can be an issue if the contract somehow receives more tokens that it initially had, then does the comparison to what it initially had. That would break the check and would deny the contract from allowing the usage of that logic.

# Exploitation

Our main goal is to deny the contract from allowing flash loans. We can do so by sending 1 DVT token (or even `1 wei`) to the vault. That would result in the total assets actually held by the vault being more than the shares of total supply that exists.

In a more technical way, let's assume the vault hold `1 Million DVT tokens` (as in the challenge scenario).

The `totalSupply()` would be `1_000_000e18`.
The `totalAssets()` would be `10_000_000e18`.

After a random user sends `1 DVT token` the values would be as follows:

The `totalSupply()` would **STILL** be `1_000_000e18`.
The `totalAssets()` would **BECOME** `1_000_001e18`.

That way, the assertion happening inside the `UnstoppableVault::flashLoan()` :

`if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();` 

Would be:

`if (convertToShares(1_000_000e18) != 1_000_001e18) revert InvalidBalance();` 

Which will fail and return `InvalidBalance()` 

That way, we deny the vault from providing flash loans.

## Exploit test case

The test case would be very simple, a direct `1 DVT` transfer:

```solidity
function test_unstoppable() public checkSolvedByPlayer {
        console.log("Vault balance before transfer: ",vault.totalAssets());
        token.transfer(address(vault), 1e18);
        console.log("Vault balance after transfer: ",vault.totalAssets());

}
```

The output would be:

```solidity
$ forge test -vv
[⠊] Compiling...
[⠑] Compiling 1 files with Solc 0.8.25
[⠘] Solc 0.8.25 finished in 598.47ms
Compiler run successful!

Ran 2 tests for test/Unstoppable.t.sol:UnstoppableChallenge
[PASS] test_assertInitialState() (gas: 63383)
[PASS] test_unstoppable() (gas: 82388)
Logs:
  Vault balance before transfer:  1000000000000000000000000
  Vault balance after transfer:  1000001000000000000000000

Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 12.02ms (1.86ms CPU time)

Ran 1 test suite in 104.77ms (12.02ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```

And that way, both our tests pass and the `checkSolvedByPlayer()`  modifier that runs the `_isSolved()` function goes through. Marking the successful solve of the challenge.

# Conclusion

That was it for `Unstoppable` challenge from `Damn Vulnerable DeFi` series. See you next time~