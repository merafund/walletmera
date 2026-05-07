// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IMERAWalletWhitelistRouterErrors} from "../errors/IMERAWalletWhitelistRouterErrors.sol";

/// @title MERAWalletWhitelistRouter
/// @notice Ownable registry that maps route hashes to active whitelist contracts.
contract MERAWalletWhitelistRouter is Ownable, IMERAWalletWhitelistRouterErrors {
    bytes32 public constant ASSET_WHITELIST_KEY = keccak256("MERA_ASSET_WHITELIST");
    bytes32 public constant RECIPIENT_WHITELIST_KEY = keccak256("MERA_RECIPIENT_WHITELIST");

    event WhitelistRouteUpdated(
        bytes32 indexed key, address indexed previous, address indexed whitelist, address caller
    );

    mapping(bytes32 routeHash => address whitelist) public whitelistByHash;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setWhitelist(bytes32 key, address whitelist) external onlyOwner {
        _setWhitelist(key, whitelist);
    }

    function setWhitelists(bytes32[] calldata keys, address[] calldata whitelists) external onlyOwner {
        uint256 n = keys.length;
        require(n == whitelists.length, WhitelistRouterArrayLengthMismatch());
        for (uint256 i = 0; i < n;) {
            _setWhitelist(keys[i], whitelists[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _setWhitelist(bytes32 key, address whitelist) private {
        require(key != bytes32(0), WhitelistRouterInvalidHash());
        address previous = whitelistByHash[key];
        whitelistByHash[key] = whitelist;
        emit WhitelistRouteUpdated(key, previous, whitelist, msg.sender);
    }
}
