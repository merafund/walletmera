---
name: solidity-style-guide-order
description: Reorders and lays out Solidity files per the official Solidity Style Guide (pragma/imports, contract member order, function visibility order). Use when editing or reviewing .sol files, refactoring contract layout, aligning with style-guide conventions, or when the user asks for Solidity ordering or style-guide structure.
---

# Solidity Style Guide: declaration order

Follow the **official Solidity Style Guide** layout so readers can scan contracts predictably. Canonical reference: [Order of Layout](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-layout) and [Order of Functions](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-functions).

If project conventions conflict, **prefer repository consistency** when the user or existing code clearly diverges.

## File-level order (top of `.sol`)

1. Pragma statements  
2. Import statements  
3. `event` declarations (file-level, if any)  
4. `error` declarations (file-level, if any)  
5. `interface` definitions  
6. `library` definitions  
7. `contract` definitions  

Imports belong **after** pragma and **before** contracts (do not place imports between contracts).

## Inside each `contract`, `library`, or `interface`

1. Type declarations (`struct`, `enum`, etc.)  
2. State variables  
3. Events  
4. Errors  
5. Modifiers  
6. Functions  

**Note:** The guide allows declaring types closer to their use when that improves clarity; default to the list above unless a local exception is obvious.

## Function order (within the functions section)

Group by **visibility / role**, in this order:

1. `constructor`  
2. `receive()` (if present) — before `fallback`  
3. `fallback()` (if present)  
4. `external` functions  
5. `public` functions  
6. `internal` functions  
7. `private` functions  

**Within each visibility group:** put non-`view` / non-`pure` functions first, then `view`, then **`pure` last** (per style guide).

### Practical sorting rules

- Treat **`public` override of external interface** as `public` in the `public` block.  
- **`function() external` getters** from `public` state variables are still state variables in layout; do not mix them into the function section.  
- For **interfaces**: only signatures allowed; keep order consistent with implementing contracts when practical (often: events/errors if any, then functions by the same visibility order).

## When applying this skill

- **New code**: write members in this order from the start.  
- **Refactors / reviews**: suggest or perform moves that restore this order without changing behavior.  
- **Large files**: reorder in focused PRs or section-by-section to keep diffs reviewable; preserve git history sensibly (move blocks, avoid drive-by renames).

## Quick checklist

```
File:
- [ ] pragma → imports → events/errors (if file-level) → interfaces → libraries → contracts

Contract body:
- [ ] types → state vars → events → errors → modifiers → functions

Functions:
- [ ] constructor → receive → fallback → external → public → internal → private
- [ ] within each group: non-view/pure → view → pure
```
