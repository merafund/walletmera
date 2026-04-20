---
name: solidity-security-best-practices
description: Secure Solidity (.sol) development—CEI, reentrancy guards, access control, SafeERC20, input validation, upgrades, signatures, oracles/slippage, DeFi assumptions. Use when writing new .sol, hardening existing contracts, or mapping OWASP/SCSVS-style controls. Triggers on Solidity security, ReentrancyGuard, CEI, SafeERC20, or vulnerability prevention in .sol files.
---

# Solidity security best practices (.sol)

## Scope

Guidance for **authoring and reviewing Solidity**. Combine with **solidity-code-review** and **solidity-adversarial-analysis**; after edits in this repo use **sol-change-forge-verify**.

## Core principles

| Principle | Verify in `.sol` |
| --------- | ------------------ |
| CEI | Checks → state → external calls |
| Least privilege | Each role/function minimal authority |
| Defense in depth | CEI + guards + token safety where needed |
| Fail-safe defaults | Sensitive paths closed unless explicitly allowed |
| Complete mediation | No bypass routes to privileged effects |

## Per-function questions

1. Who can call it? (`msg.sender` / roles; not `tx.origin`)
2. Are inputs bounded (addresses, lengths, amounts)?
3. Where is state finalized before externals?
4. Are externals trusted? Returns checked? ERC20 safe?
5. Reentrancy / callbacks possible?
6. Are critical changes logged with events?

## SCSVS-oriented passes

- **ARCH** — proxies: admin vs logic, storage gaps, initializer discipline, trusted `delegatecall` targets only.
- **CODE** — explicit visibility, fixed pragma, no dead/shadowed state, correct data locations.
- **AUTH** — modifiers on state changers; one-shot initializers; timelocks/multisig for high risk ops.
- **COMM** — CEI / `ReentrancyGuard`; pull payments where push risks griefing; call results handled.
- **CRYPTO** — no naive on-chain randomness; EIP-712 domain separation; safe hashing (`abi.encode` vs packed); validate `ecrecover` output.
- **DEFI** — slippage, oracle manipulation resistance, flash-loan sensitivity, fee-on-transfer/rebase, internal accounting vs raw balances.
- **BLOCK** — minimize critical dependence on `block.timestamp` / ordering; anti-grief for loops over user data.
- **GOV** — timelocks, flash-loan vote protections, execution safety.

## Pattern priority

- **Critical** — CEI, reentrancy protection on risky externals, access control, safe token transfers.
- **High** — input validation (custom errors), upgrade/initializer safety, pausable/circuit breakers when appropriate.
- **Medium** — replay-safe signatures, events, randomness sources off-chain or VRF.

## Reference

- [OWASP Smart Contract Top 10 (2026)](references/owasp-scwe-top10.md)

## Optional MCP

If `solidity-agent-toolkit` is configured, use SCWE search, static analyzers, and remediation helpers as supplements to reading the `.sol` sources.
