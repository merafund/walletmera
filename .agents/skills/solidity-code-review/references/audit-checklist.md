# Smart Contract Audit Checklist

This checklist is organized by OWASP SCSVS (Smart Contract Security Verification Standard) categories and includes cross-references to SCWE (Smart Contract Weakness Enumeration) IDs.

## Architecture & Design (SCSVS-ARCH)

- **Proxy Pattern**: Proxy pattern implemented correctly with proper admin separation (SCWE-053).
- **Storage Gaps**: Storage gaps included in base contracts for upgradeability to prevent collisions.
- **Circular Dependencies**: No circular dependencies between contracts.
- **Surface Area**: Minimal contract surface area (only necessary public/external functions).
- **Logic Initialization**: Logic contract cannot be initialized by anyone other than the proxy (SCWE-053).
- **Trusted Delegatecall**: Use of `delegatecall` only to trusted, immutable contracts (SCWE-035).
- **Contract Size**: Contract size is within the 24KB limit (EIP-170).

> **Automate with:** `run_slither`, `run_aderyn`, `match_vulnerability_patterns`

## Code Quality (SCSVS-CODE)

- **Explicit Visibility**: All functions have explicit visibility (SCWE-128).
- **Fixed Pragma**: No floating pragma; specific compiler version used (SCWE-058).
- **Deprecated Functions**: No deprecated functions like `throw`, `constant` (for functions), or `suicide` (SCWE-061).
- **Custom Errors**: Custom errors used instead of long revert strings for gas efficiency.
- **Unused Code**: No unused variables, functions, or imports (SCWE-129).
- **State Mutability**: Proper use of `constant` and `immutable` for non-changing state variables.
- **Variable Shadowing**: No shadowing of state variables or inherited variables (SCWE-111).
- **Data Location**: Correct use of `memory`, `storage`, and `calldata` to avoid unnecessary copies.
- **Naming Conventions**: Adherence to Solidity style guide (CapWords for contracts, mixedCase for functions).
- **Function Ordering**: Functions ordered by visibility then mutability per Solidity style guide (SCWE-128).

> **Automate with:** `check_style`, `run_solhint`, `validate_natspec`, `format_code`

## Authorization (SCSVS-AUTH)

- **Access Control**: Access control (e.g., `onlyOwner`, `hasRole`) on all state-changing functions (SCWE-048).
- **Origin Authentication**: No `tx.origin` used for authentication (SCWE-018).
- **Initializer Protection**: Initializers are protected and cannot be re-called (SCWE-053).
- **Privileged Roles**: Critical functions require multi-sig or timelock for execution.
- **Ownership Transfer**: Ownership can be transferred safely using a two-step process (claimOwnership).
- **Blacklisting/Whitelisting**: Logic for blacklisting or whitelisting addresses is robust and restricted.

> **Automate with:** `run_slither`, `match_vulnerability_patterns`, `search_vulnerabilities("access control")`

## Communication (SCSVS-COMM)

- **Return Values**: External call return values are checked and handled (SCWE-109).
- **Untrusted Calls**: No `delegatecall` to untrusted or user-provided contracts (SCWE-035).
- **Payment Pattern**: Pull-over-push pattern used for payments to avoid DoS (SCWE-030).
- **Gas Limits**: Gas limit considerations for external calls to prevent out-of-gas DoS (SCWE-126).
- **Reentrancy**: Reentrancy protection (CEI or `ReentrancyGuard`) on all external calls (SCWE-046).
- **Ether Reception**: Contract handles incoming Ether correctly (or rejects it if not intended).

> **Automate with:** `run_slither`, `run_aderyn`, `match_vulnerability_patterns`, `get_remediation("SCWE-046")`

## Cryptography (SCSVS-CRYPTO)

- **Randomness**: No on-chain randomness (e.g., `block.timestamp`, `blockhash`) (SCWE-015).
- **Signature Standard**: EIP-712 used for structured data signatures (SCWE-020).
- **Hash Collisions**: `abi.encode` used instead of `abi.encodePacked` for dynamic types in hashing (SCWE-025).
- **Malleability**: Signature malleability protection implemented (e.g., using OpenZeppelin ECDSA) (SCWE-021).
- **ecrecover Zero**: Check that `ecrecover` does not return `address(0)`.

> **Automate with:** `match_vulnerability_patterns`, `search_vulnerabilities("cryptography")`

## DeFi Specific (SCSVS-DEFI)

- **Slippage**: Slippage protection implemented for all swap/liquidity operations.
- **Flash Loans**: Resistance to flash loan-assisted price manipulation.
- **Oracle Safety**: Oracle manipulation protection (e.g., using TWAP or multiple sources).
- **Balance Reliance**: No reliance on `address(this).balance` or `token.balanceOf(address(this))` for internal accounting.
- **Fee-on-Transfer**: Logic accounts for tokens that take a fee on transfer.
- **Rebasing Tokens**: Logic accounts for tokens with elastic supply (rebasing tokens).
- **Rounding Errors**: Rounding errors favor the protocol, not the user.

> **Automate with:** `run_slither`, `match_vulnerability_patterns`, `search_vulnerabilities("defi")`
