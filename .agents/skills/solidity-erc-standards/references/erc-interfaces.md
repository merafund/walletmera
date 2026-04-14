# ERC Standard Interfaces

> **MCP Integration**: Use `erc://{standard}` resource to fetch these interfaces programmatically. Use `check_vulnerability` to verify implementations against known pitfalls.

## ERC20 Interface

```solidity
interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
```

## ERC721 Interface

```solidity
interface IERC721 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool _approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}
```

## ERC1155 Interface

```solidity
interface IERC1155 {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values);
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);
    event URI(string value, uint256 indexed id);
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids) external view returns (uint256[] memory);
    function setApprovalForAll(address operator, bool approved) external;
    function isApprovedForAll(address account, address operator) external view returns (bool);
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
    function safeBatchTransferFrom(address from, address to, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data) external;
}
```

## ERC4626 Interface

```solidity
interface IERC4626 {
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function maxDeposit(address receiver) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function maxMint(address receiver) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
}
```

## Common Extensions

- **ERC20Permit**: Adds `permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)` for signature-based approvals.
- **ERC20Votes**: Adds `delegate(address delegatee)` and `getVotes(address account)` for governance.
- **ERC721Enumerable**: Adds `totalSupply()`, `tokenByIndex(uint256 index)`, and `tokenOfOwnerByIndex(address owner, uint256 index)`.
- **IERC721Receiver**: Must be implemented by contracts to receive ERC721 tokens via `safeTransferFrom`.
- **IERC1155Receiver**: Must be implemented by contracts to receive ERC1155 tokens.

## Common Pitfalls per Standard

| Standard | Pitfall                      | Fix                                                                  | SCWE     |
| -------- | ---------------------------- | -------------------------------------------------------------------- | -------- |
| ERC20    | Approval race condition      | Use `increaseAllowance`/`decreaseAllowance` or `Permit`.             | SCWE-029 |
| ERC20    | Tokens returning `false`     | Use `SafeERC20` wrapper.                                             | SCWE-109 |
| ERC721   | Reentrancy in `safeTransfer` | Use `nonReentrant` modifier or CEI pattern.                          | SCWE-138 |
| ERC721   | Gas cost of Enumerable       | Avoid `Enumerable` if on-chain discovery isn't required.             | -        |
| ERC1155  | Missing batch support        | Ensure `balanceOfBatch` and `safeBatchTransferFrom` are implemented. | -        |
| ERC4626  | Inflation attack             | Mint "dead shares" to `address(0)` on first deposit.                 | SCWE-049 |
| ERC4626  | Rounding errors              | Round in favor of the vault (Down for deposit, Up for withdraw).     | -        |
