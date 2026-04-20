---
name: solidity-require-custom-errors
description: Prefer require(bool, customError) with user-defined errors in Solidity instead of string revert reasons. Use when writing or editing .sol files, adding guards, or refactoring reverts; triggers on require, revert messages, or custom errors.
---

# Solidity: require and custom errors

## When to apply

Use this pattern in project contracts (`src/**/*.sol`) when adding validation, access checks, or invariants.

## Language support (current Solidity)

From **Solidity 0.8.26** onward, `require` accepts a **custom error** as the second argument:

```solidity
error Unauthorized(address caller);
require(msg.sender == owner, Unauthorized(msg.sender));
```

This project uses **Solidity 0.8.34** (`foundry.toml`) with **`via_ir = true`**, which uses the IR pipeline where this feature is supported.

**Legacy codegen note:** Custom errors in `require` need the IR-based pipeline. If a contract is ever compiled without IR, use `if (!condition) revert CustomError(...);` instead.

## Preferred style

1. **Declare errors** at contract or file scope (group related errors; match existing project naming).
2. **Use** `require(condition, ErrorName(...args))` for simple boolean guards where the team uses `require`.
3. **Avoid** `require(condition, "string reason")` for new code—strings increase bytecode and are less structured than custom errors.

## Evaluation caveat

Arguments to the custom error in `require(cond, Err(f()))` are **evaluated even when `cond` is true**. If building error data is expensive or has side effects, prefer:

```solidity
if (!condition) revert Err(...);
```

## Tests

After changing `.sol` files, follow the project Foundry workflow (format, test, lint) from the repo’s post-Solidity skill if present.
