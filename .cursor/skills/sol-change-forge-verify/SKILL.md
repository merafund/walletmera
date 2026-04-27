---
name: sol-change-forge-verify
description: After editing Solidity (.sol) files in a Foundry repo, runs forge fmt, forge test, and forge lint from the project root and addresses failures before continuing. Use when modifying contracts, tests, or interfaces under src/ or test/, after any .sol change, or when the user wants the post-Solidity Foundry check workflow.
---

# Solidity change: Foundry verify pipeline

## When to apply

Run this workflow **after each change** (or coherent batch of edits) that touches one or more `*.sol` files in this repository.

## Instructions

1. **Working directory**: Run all commands from the repository root (where `foundry.toml` lives).

2. **Execute in this order** (do not skip steps unless the user explicitly narrows scope):
   - `forge fmt`
   - `forge test`
   - `forge lint`

3. **If `forge fmt` reformats files**: Treat that as part of the change set. Re-run `forge test` and `forge lint` if needed so results reflect the formatted tree.

4. **On failure**:
   - Read the reported errors, fix the Solidity or config issue, then re-run the full sequence from step 2.
   - Do not mark the task complete while any of the three commands still fail.

5. **Scope**: If only non-Solidity files changed (e.g. markdown, scripts), this skill does not require the pipeline unless the user asks for it.

## Examples

- Edited `src/MyContract.sol` → run `forge fmt`, then `forge test`, then `forge lint`.
- Renamed an error in `src/interfaces/IMy.sol` and updated tests → same pipeline after saving.

## Notes

- Prefer requesting **network** permissions only if tests or tooling need outbound access (e.g. fork tests); otherwise run with defaults.
- Keep fixes minimal and aligned with existing project patterns.
