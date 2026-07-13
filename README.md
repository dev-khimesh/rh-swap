# rh-swap — a minimal AMM for Robinhood Chain

A small Uniswap-V2-style constant-product DEX so anyone can trade **tUSDC -> any coin**
(and coin -> coin routed through the tUSDC hub) on Robinhood Chain.

Built for **testnet first** (chain ID `46630`). The tokens here are clearly-labeled
**test** tokens (`tUSDC`, `tWBTC`, `tDOGE`) — they are *not* real USDC or any real asset.

## Contracts

| File | Role |
|------|------|
| `src/ERC20.sol` | Minimal ERC-20 + `MockERC20` (open faucet mint, testnet only) |
| `src/Pair.sol` | Constant-product pool (x*y=k), 0.30% fee, LP shares as ERC-20 |
| `src/Factory.sol` | Creates & indexes pairs; anyone can list any token |
| `src/Router.sol` | addLiquidity, getAmountsOut, swapExactTokensForTokens (multi-hop) |
| `script/Deploy.s.sol` | Deploys everything and seeds two pools |

## Test

```bash
forge test -vv
```

All five tests pass: direct swap, multi-hop swap via the USDC hub, slippage guard,
deadline guard, and the k-invariant.

## Deploy to Robinhood Chain testnet

1. Add the testnet to your wallet and grab gas from the faucet:
   - RPC: https://rpc.testnet.chain.robinhood.com  — Chain ID 46630 — gas token: ETH
   - Faucet: https://faucet.testnet.chain.robinhood.com
   - Explorer: https://explorer.testnet.chain.robinhood.com
2. Copy `.env.example` to `.env` and set `PRIVATE_KEY` to a **throwaway** testnet key.
3. Deploy:

```bash
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RH_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast
```

The script prints the Factory, Router, and token addresses. Save them.

## Verify contracts (Blockscout)

```bash
forge verify-contract <ADDRESS> src/Router.sol:Router \
  --chain-id 46630 \
  --rpc-url "$RH_RPC_URL" \
  --verifier blockscout \
  --verifier-url https://explorer.testnet.chain.robinhood.com/api/
```

## How anyone swaps USDC -> a coin

```solidity
// path = [tUSDC, tWBTC] for a direct swap; [coinA, tUSDC, coinB] to route via the hub
usdc.approve(router, amountIn);
uint256[] memory quote = router.getAmountsOut(amountIn, path);
uint256 minOut = quote[quote.length - 1] * 995 / 1000; // 0.5% slippage
router.swapExactTokensForTokens(amountIn, minOut, path, msg.sender, block.timestamp + 300);
```

## Going to mainnet

Only after you're satisfied on testnet. Switch RH_RPC_URL to
https://rpc.mainnet.chain.robinhood.com, chain ID 4663, verifier URL
https://robinhoodchain.blockscout.com/api/, and use **real** token addresses —
do **not** deploy MockERC20 (open-mint) or anything labeled to impersonate USDC
on mainnet. For a real product, Robinhood Chain already ships Uniswap as its main AMM.

## Important caveats

- This is educational/testnet-grade code. It has **not** been audited. Real AMMs
  need far more hardening (fee-on-transfer token handling, TWAP oracles, thorough
  fuzzing, reentrancy review beyond the basic lock, etc.).
- The MockERC20.mint is intentionally permissionless — appropriate for a testnet
  faucet, never for anything holding real value.
