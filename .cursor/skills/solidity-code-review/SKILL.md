---
name: solidity-code-review
description: Structured security and quality review for Solidity (.sol)—scope, manual review, static analysis hooks, SCWE-style findings, severity labels, NatSpec and style. Use when auditing .sol, PR review on contracts, vulnerability assessment, or pre-merge Solidity checklist. Triggers on code review, audit, or security assessment of Solidity sources.
---

# Solidity code review (.sol)

## Scope

Targets **Solidity source and tests** in the repo. Run the project toolchain (e.g. Foundry: `forge build`, `forge test`) before signing off; after edits, use **sol-change-forge-verify** when applicable.

## Pre-review

- [ ] Project builds; tests pass (note any skipped fork tests).
- [ ] Dependencies pinned; OZ/third-party versions known.
- [ ] NatSpec/spec aligns with behavior in `.sol`.
- [ ] Audit scope: which contracts and functions are in scope.

## Method

1. **Architecture** — inheritance graph, external calls, trust boundaries.
2. **Critical paths** — fund movement, auth, upgrades, oracle/DEX.
3. **Automation** — Slither, Aderyn, Solhint where available.
4. **Patterns** — reentrancy, access control, oracle/slippage, unsafe ERC20.
5. **Integration** — cross-contract assumptions, edge cases (zeros, max uint).

## Severity

| Level | Meaning |
| ----- | ------- |
| Critical | Direct loss of funds, permanent lock, total compromise |
| High | Realistic exploit or major integrity break |
| Medium | Limited impact or narrow preconditions |
| Low | Best practices, hygiene, gas without safety tradeoff |

## Focus areas (`.sol`)

- Access control and initializers; never `tx.origin` for auth.
- CEI ordering; guarded external calls; checked low-level calls.
- `SafeERC20` for unknown tokens; return values handled.
- Upgrade/proxy storage layout and admin separation.
- Events on meaningful state changes; accurate NatSpec.

## Finding template

### [SEVERITY] Title

**ID**: SCWE-XXX (if known)  
**Location**: `Contract.sol:L42`  
**Description**: What is wrong and how it triggers.  
**Impact**: User/protocol effect.  
**Remediation**: Concrete `.sol` or design change.

## References

- [Audit checklist](references/audit-checklist.md)
- [Solidity style guide](references/solidity-style-guide.md)

## Optional MCP

If `solidity-agent-toolkit` is available, use its static analysis, pattern match, and SCWE lookup tools to complement manual review.
