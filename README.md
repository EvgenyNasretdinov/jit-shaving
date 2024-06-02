# JIT shaving

*=- When it's smooth, no JIT is used -=*

#### TLDR: JIT mitigation by using truncated liquidity oracles

## Description

With the help of truncated oracles for liquidity, we are able to mitigate the suspicious liquidity spikes, which usually are the essential part of the JIT attacs.

We were interested how the truncated oracle hooks could be helpful with the malicious price manipulation - https://blog.uniswap.org/uniswap-v4-truncated-oracle-hook

So we've came to the idea, that the similar oracle, but with the focus on the liquidity, could be helpful with JIT

## Set up

*requires [foundry](https://book.getfoundry.sh)*

```
forge install
forge test
```
