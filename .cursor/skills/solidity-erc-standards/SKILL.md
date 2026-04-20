---
name: solidity-erc-standards
description: ERC20, ERC721, ERC1155, and ERC4626 guidance for Solidity (.sol)—required APIs, SafeERC20, rounding, reentrancy in callbacks, vault inflation, testing notes. Use when implementing or reviewing token or vault .sol files, NFT contracts, or ERC compliance. Triggers on ERC20, ERC721, ERC1155, ERC4626, token, NFT, or vault Solidity code.
---

# ERC standards for Solidity (.sol)

## Scope

Use when writing or reviewing **token and vault Solidity**. Prefer OpenZeppelin or Solady implementations over hand-rolled core logic. After changes, run **sol-change-forge-verify** in Foundry repos.

## ERC20

- Required: `totalSupply`, `balanceOf`, `transfer`, `allowance`, `approve`, `transferFrom`.
- Use **`SafeERC20`** for external tokens; handle missing/false returns.
- **`approve` race** — prefer increase/decrease allowance, permit, or documented reset flow.
- Watch non-standard tokens (e.g. no return on `transfer`).

## ERC721

- Prefer **`safeTransferFrom`** when the recipient is a contract (receiver hook).
- **`onERC721Received` reentrancy** — CEI / `nonReentrant` as needed.
- Enumerable extensions: higher transfer gas; use only if needed.

## ERC1155

- Batch ops for gas; correct `balanceOfBatch`; implement receiver hooks safely.

## ERC4626

- Rounding favors the vault: deposit/mint round down shares; withdraw/redeem round up shares where applicable.
- **First-depositor inflation** — dead shares or established mitigation pattern.
- Test symmetry, rounding edges, and fee-on-transfer/rebasing if supported.

## Implementation choice

| | OpenZeppelin | Solady |
| --- | --- | --- |
| Tradeoff | Clarity, extensions | Gas-optimized primitives |

## Testing (Foundry)

- ERC20: transfers, allowances, zero and max amounts.
- ERC721: mint/transfer/approvals; receiver callback paths.
- ERC1155: batch paths and URIs.
- ERC4626: share math, rounding, inflation defenses.

## Reference

- [Interface snippets](references/erc-interfaces.md)

## Optional MCP

If `solidity-agent-toolkit` is configured, use ERC resources / vulnerability checks to cross-validate `.sol` implementations.
