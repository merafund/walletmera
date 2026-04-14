# Foundry Cheatsheet

> **MCP Integration**: Many Forge commands have equivalent MCP tools (`compile_contract`, `run_tests`, `gas_snapshot`, `dry_run_deploy`). Use MCP tools for programmatic access within AI agent workflows.

## Forge Commands

- `forge build`: Compile the project.
- `forge test`: Run tests.
- `forge snapshot`: Generate gas snapshots.
- `forge script`: Run Solidity scripts.
- `forge verify-contract`: Verify contracts on Etherscan.
- `forge fmt`: Format Solidity files.
- `forge inspect`: Get contract metadata (bytecode, storage layout, etc.).
- `forge create`: Deploy a contract from the CLI.
- `forge debug`: Debug a single transaction.

## Cast Commands

- `cast call`: Perform a read-only call.
- `cast send`: Send a transaction.
- `cast estimate`: Estimate gas for a transaction.
- `cast abi-encode`: Encode arguments for a function.
- `cast abi-decode`: Decode return data.
- `cast sig`: Get the selector of a function signature.
- `cast storage`: Get the value of a storage slot.
- `cast block`: Get information about a block.
- `cast tx`: Get information about a transaction.
- `cast wallet`: Manage local wallets and keys.

## Anvil Commands

- `anvil`: Start a local Ethereum node.
- `--fork-url <URL>`: Fork a remote network.
- `--fork-block-number <BLOCK>`: Pin the fork to a block.
- `--port <PORT>`: Specify the port to listen on.
- `anvil_setBalance`: Set the balance of an account (via RPC).

## Common Cheatcode Patterns

### Identity & Funds

```solidity
vm.prank(alice);
contract.call(); // msg.sender is alice

vm.deal(alice, 10 ether); // alice now has 10 ETH

hoax(alice, 10 ether); // prank + deal
contract.call();
```

### Time & Blocks

```solidity
vm.warp(1641006000); // set block.timestamp
vm.roll(14000000);   // set block.number
```

### State

```solidity
uint256 slot = vm.load(address(contract), bytes32(0));
vm.store(address(contract), bytes32(0), bytes32(uint256(1)));

uint256 id = vm.snapshot();
// ... do things ...
vm.revertTo(id);
```

### Assertions

```solidity
vm.expectRevert("Error message");
contract.fail();

vm.expectEmit(true, true, false, true);
emit MyEvent(1, 2, 3);
contract.emitEvent();

vm.expectCall(address(target), abi.encodeWithSelector(Target.func.selector));
contract.callTarget();
```

### Environment

```solidity
uint256 key = vm.envUint("PRIVATE_KEY");
address addr = vm.envAddress("CONTRACT_ADDR");
string memory s = vm.envString("API_KEY");
```

## Testing Patterns

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Counter.sol";

contract CounterTest is Test {
    Counter public counter;

    function setUp() public {
        counter = new Counter();
        counter.setNumber(0);
    }

    function test_Increment() public {
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function testFuzz_SetNumber(uint256 x) public {
        counter.setNumber(x);
        assertEq(counter.number(), x);
    }
}
```
