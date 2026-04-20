---
name: solidity-adversarial-analysis
description: Threat modeling and attacker-perspective review of Solidity (.sol) contracts—flash loans, oracle manipulation, MEV, governance, reentrancy, access control, economic bugs, composability. Use when red-teaming .sol, exploit paths, attack scenarios, or pre-deploy DeFi risk analysis. Triggers on adversarial analysis, threat model, attack vector, or red team for Solidity.
---

# Solidity adversarial analysis (.sol)

## Scope

Applies to **Solidity contracts and tests** (`src/**/*.sol`, `test/**/*.sol`). Pair with **solidity-security-best-practices** for mitigations and **solidity-code-review** for audit-style reporting.

## Framework

| Step | Action | Question |
| ---- | ------ | -------- |
| 1 | Map assets | What can be stolen, bricked, or manipulated? |
| 2 | Entry points | Which `external`/`public` functions move value or state? |
| 3 | Adversary model | Flash loans, MEV, governance tokens, callbacks? |
| 4 | Sequences | Multi-tx / same-tx paths to profit or grief? |
| 5 | Invariants | What must always hold (balances, shares, roles)? |

## Categories (indicators → ask)

| Category | Signals in .sol |
| -------- | ---------------- |
| Reentrancy | External call before state finalization; shared state across functions |
| Flash loan | Spot/oracle price in one tx; liquidity or price as sole guard |
| Oracle | Single feed; no staleness/bounds; manipulable reserves |
| MEV | Unprotected swaps; predictable ordering via `block.*` |
| Governance | Vote without timelock; flash-mintable voting power |
| Access control | Initializer/proxy/admin surface; missing modifiers |
| Economic | Rounding, fees, rebasing/fee-on-transfer assumptions |
| Cross-contract | ERC777/ERC1155 hooks; untrusted token `transferFrom` |

## Workflow

1. Feature detection (oracles, DEX, lending, roles, upgrades).
2. Map features → categories above.
3. For each: preconditions → concrete call sequence → impact.
4. Check existing defenses (CEI, `ReentrancyGuard`, slippage, timelocks) and gaps.

## Optional MCP

If `solidity-agent-toolkit` is configured, use its adversarial / static-analysis tools as supporting evidence—not a substitute for reasoning over the actual `.sol` logic.
