---
name: develop-secure-contracts
description: Integrates OpenZeppelin Contracts into Solidity (.sol) files via imports and minimal diffs—tokens (ERC20, ERC721, ERC1155), access control (Ownable, AccessControl), Pausable, ReentrancyGuard, governance, proxies. Use when editing or adding .sol contracts, extending OZ bases, or running OZ CLI pattern discovery. Triggers on OpenZeppelin, oz contracts, lib/openzeppelin-contracts, or secure component integration in Solidity.
---

# Develop secure Solidity contracts (OpenZeppelin)

## Scope

Use for **Solidity `.sol` files** (e.g. `src/`, `test/`, `script/`). Prefer library imports over pasted vendor code. After changing `.sol` in a Foundry repo, follow the project skill **sol-change-forge-verify** (`forge fmt`, `forge test`, `forge lint`).

## Before coding

1. **Read the repo** — `Glob` `**/*.sol`, open the target contract and its parents.
2. **Integrate, do not replace** — extend existing contracts unless the user asks for a rewrite.
3. **Library first** — search installed OZ under `node_modules/@openzeppelin/contracts/` or `lib/openzeppelin-contracts/` (Foundry). Never copy OZ source into user files; always import the package.

## Pattern discovery (Solidity)

1. List installed OZ paths; browse component directories (`token/`, `access/`, `utils/`, `governance/`, `proxy/`, `account/`).
2. Read the component `.sol`, NatSpec, and in-repo tests/examples.
3. Extract **minimal integration**: imports, inheritance order, storage, constructor/init, required overrides/modifiers/hooks.
4. Apply edits with small diffs; resolve inheritance conflicts before finishing.

## CLI reference (optional)

`npx @openzeppelin/contracts-cli --help` — generate baseline vs feature variant to temp files, `diff` them, apply the delta to the user contract (canonical wiring for imports and hooks).

## Solidity lookup

| Topic        | OZ repo / docs |
| ------------ | -------------- |
| Contracts    | https://github.com/OpenZeppelin/openzeppelin-contracts |
| Documentation | https://docs.openzeppelin.com/contracts |

**Version note:** override points differ by OZ version—always confirm `virtual`/hooks in the **installed** source, not from memory.

For Cairo/Stylus/Stellar stacks, use OpenZeppelin docs and repos for those ecosystems alongside this Solidity-focused skill.
