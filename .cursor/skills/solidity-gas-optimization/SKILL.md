---
name: solidity-gas-optimization
description: Gas-focused patterns for Solidity (.sol)—storage packing, custom errors, immutables, calldata, unchecked loop increments, short-circuit conditions, transient storage (TSTORE), clones, Solady. Use when optimizing hot .sol paths, contract size, or storage layout without breaking safety. Triggers on gas optimization, bytecode size, or EVM efficiency in Solidity.
---

# Solidity gas optimization (.sol)

## Scope

Tune **Solidity sources** only where profiling or size limits justify it. Do not trade obvious safety for gas without review; cross-check with **solidity-security-best-practices** and **solidity-code-review**.

## High impact

- **Storage packing** — co-locate sub-256-bit fields in the same 32-byte slot; avoid splitting pairs with a full slot between.
- **Custom errors** — prefer `revert Errors.Foo()` (and `require(cond, Errors.Foo())` where used) over long strings; see also **solidity-require-custom-errors**.
- **`constant` / `immutable`** — compile-time vs constructor-set; avoid redundant SLOADs.
- **`calldata` on external functions** — read-only array/struct params should be `calldata`, not `memory`.
- **`unchecked`** — safe for provable loop counters and similar; avoid broad unchecked external math.

## Medium impact

- Cache **array lengths** and repeated storage reads in locals inside loops.
- Default to **`uint256`** for scratch math; smaller ints for packing only.
- **`bytes32` vs `string`** for short fixed labels.
- **Order `&&` / `||`** — cheaper / likelier-fail checks first.
- Prefer **`external` over `public`** when not called internally.

## Advanced

- **Yul/assembly** — only with clear invariants and comments; isolate and test heavily.
- **Solady** — consider for hot paths when audit surface is acceptable.
- **EIP-1167 clones** — many identical logic instances from one implementation.
- **Transient storage (0.8.24+)** — single-tx scratch instead of permanent slots where appropriate.

## Checklist (quick)

1. Packed storage where possible  
2. Custom errors for reverts  
3. `constant`/`immutable` applied  
4. `calldata` parameters  
5. Loop `unchecked` where safe  
6. Cached lengths / storage  
7. Minimized redundant SSTORE  
8. Contract size under 24 KiB  

## Optional MCP

If tooling exposes gas snapshots or storage layout views, use them to validate before/after on real `forge test` scenarios.
