---
name: solidity-foundry-development
description: Foundry workflow for Solidity (.sol)—forge build/test/script, fmt, lint, fuzz and invariants, fork tests, cheatcodes, profiles, deployment and debug. Use when editing test/*.sol or script/*.sol, configuring foundry.toml, or running forge/cast/anvil. Triggers on Foundry, forge test, cheatcodes, or Foundry-based .sol development.
---

# Foundry for Solidity (.sol)

## Scope

Applies to **Solidity contracts, tests, and scripts** in Foundry layouts (`src/`, `test/`, `script/`). Post-edit verification: **sol-change-forge-verify** (`forge fmt`, `forge test`, `forge lint`) for this repo.

## Setup

- `forge init` / `forge install author/repo`; remappings in `foundry.toml` or `remappings.txt`.
- Match solc version and optimizer settings to production targets.

## Tests (`*.t.sol`)

- Inherit `forge-std/Test.sol`; shared setup in `setUp()`.
- `test_*` normal; `testFuzz_*` fuzzed; prefer `vm.expectRevert` over `testFail_*` where possible.
- Fuzz: `vm.assume`, `bound`, narrow domains to real invariants.
- Invariants: target contracts/handlers for stateful properties.
- Forks: `vm.createFork`, `vm.selectFork`, `vm.rollFork` for pinned state.

## Cheatcodes (essentials)

| Cheatcode | Use |
| --------- | --- |
| `vm.prank` / `startPrank` | `msg.sender` for next / many calls |
| `vm.deal` | ETH balance |
| `vm.expectRevert` | Assert failure |
| `vm.expectEmit` | Event assertions |
| `vm.warp` / `vm.roll` | Time / block |
| `vm.label` | Readable traces |

## Scripts & deploy

- Dry-run: `forge script ... --rpc-url $RPC`
- Broadcast + verify: add `--broadcast --verify` and API keys as required.

## Debug

- Verbosity `-vv` … `-vvvvv` for traces; `forge debug` for single-tx; `console.log` via `forge-std/console.sol`.

## Profiles

Use `[profile.*]` in `foundry.toml` for IR builds, deterministic metadata, pinned blocks for CI.

## Reference

- [Foundry cheatsheet](references/foundry-cheatsheet.md)

## Optional MCP

If `solidity-agent-toolkit` is available, use compile/test/gas helpers alongside local `forge` commands.
