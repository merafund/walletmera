# Copy .env.example to .env and fill in values before running deploy targets.
include .env

export PRIVATE_KEY
export RPC_URL_POLYGON
export RPC_URL_AMOY
export RPC_URL_BSC
export POLYGONSCAN_API_KEY
export BSCSCAN_API_KEY

FORGE ?= forge
SCRIPT := script/DeployMERAWalletCreate2Factory.s.sol:DeployMERAWalletCreate2Factory

.PHONY: deploy-factory-polygon deploy-factory-amoy deploy-factory-bsc deploy-factory
.PHONY: deploy-meta-proxy-clone-factory deploy-meta-proxy-clone-factory-polygon deploy-meta-proxy-clone-factory-amoy deploy-meta-proxy-clone-factory-bsc
.PHONY: deploy-asset-whitelist-polygon deploy-asset-whitelist-amoy deploy-asset-whitelist-bsc
.PHONY: deploy-erc20-approve-checker-polygon deploy-erc20-approve-checker-amoy deploy-erc20-approve-checker-bsc
.PHONY: deploy-erc20-transfer-checker-polygon deploy-erc20-transfer-checker-amoy deploy-erc20-transfer-checker-bsc
.PHONY: deploy-target-blacklist-checker-polygon deploy-target-blacklist-checker-amoy deploy-target-blacklist-checker-bsc
.PHONY: deploy-target-whitelist-checker-polygon deploy-target-whitelist-checker-amoy deploy-target-whitelist-checker-bsc
.PHONY: deploy-uniswap-v2-oracle-slippage-checker-polygon deploy-uniswap-v2-oracle-slippage-checker-amoy deploy-uniswap-v2-oracle-slippage-checker-bsc
.PHONY: verify-json-factory verify-json-base-wallet

# Standard JSON for Polygonscan "Solidity (Standard-Json-Input)" (matches foundry.toml: via_ir, runs 1000, solc 0.8.34).
OUT_VERIFY_JSON_DIR ?= verification
VERIFY_JSON_CHAIN_ID ?= 137
VERIFY_JSON_SOLC := 0.8.34+commit.80d5c536
VERIFY_JSON_COMPILE := --via-ir --optimizer-runs 1000 --evm-version prague --compiler-version $(VERIFY_JSON_SOLC)

VERIFY_JSON_FACTORY_ADDR ?= 0xe6f40634c24e9bcab4239d8ada5afae85724907f
VERIFY_JSON_BASE_WALLET_ADDR ?= 0x60F307B4e7E6F26Adf01FF3C647193B98DFA3c57

# BaseMERAWallet constructor tuple; override in .env or set VERIFY_JSON_BASE_WALLET_CTOR to a single ABI-encoded hex string.
VERIFY_JSON_WALLET_PRIMARY ?= 0xb4f0b73CEA9A674aD7EbaEB4DA2e75d3162A17aa
VERIFY_JSON_WALLET_BACKUP ?= $(VERIFY_JSON_WALLET_PRIMARY)
VERIFY_JSON_WALLET_EMERGENCY ?= $(VERIFY_JSON_WALLET_PRIMARY)
VERIFY_JSON_WALLET_SIGNER ?= $(VERIFY_JSON_WALLET_PRIMARY)
VERIFY_JSON_WALLET_GUARDIAN ?= 0x0000000000000000000000000000000000000000

# Shared deploy: set RPC_URL, CHAIN_ID (EIP-155), and optionally VERIFY_API_KEY for --verify.
# Explicit --chain fixes explorer/API targeting; without it, forge script --verify can fail with "No contract bytecode" on L2/sidechains.
# --force avoids forge skipping compile while script artifacts are missing ("Error: No contract bytecode").
deploy-factory:
	$(FORGE) script $(SCRIPT) --force --rpc-url $(RPC_URL) --chain $(CHAIN_ID) --broadcast --private-key $(PRIVATE_KEY) \
		$(if $(strip $(DEPLOY_WITH_GAS_PRICE)),--with-gas-price $(DEPLOY_WITH_GAS_PRICE),) \
		$(if $(strip $(DEPLOY_PRIORITY_GAS_PRICE)),--priority-gas-price $(DEPLOY_PRIORITY_GAS_PRICE),) \
		$(if $(strip $(VERIFY_API_KEY)),--verify --etherscan-api-key $(VERIFY_API_KEY),) -vvvv

deploy-factory-polygon:
	@$(MAKE) deploy-factory RPC_URL="$(RPC_URL_POLYGON)" CHAIN_ID=137 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-factory-amoy:
	@$(MAKE) deploy-factory RPC_URL="$(RPC_URL_AMOY)" CHAIN_ID=80002 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-factory-bsc:
	@$(MAKE) deploy-factory RPC_URL="$(RPC_URL_BSC)" CHAIN_ID=56 VERIFY_API_KEY="$(BSCSCAN_API_KEY)"

deploy-meta-proxy-clone-factory:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletMetaProxyCloneFactory.s.sol:DeployMERAWalletMetaProxyCloneFactory

deploy-meta-proxy-clone-factory-polygon:
	@$(MAKE) deploy-meta-proxy-clone-factory RPC_URL="$(RPC_URL_POLYGON)" CHAIN_ID=137 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-meta-proxy-clone-factory-amoy:
	@$(MAKE) deploy-meta-proxy-clone-factory RPC_URL="$(RPC_URL_AMOY)" CHAIN_ID=80002 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-meta-proxy-clone-factory-bsc:
	@$(MAKE) deploy-meta-proxy-clone-factory RPC_URL="$(RPC_URL_BSC)" CHAIN_ID=56 VERIFY_API_KEY="$(BSCSCAN_API_KEY)"

deploy-asset-whitelist-polygon:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletUniswapV2AssetWhitelist.s.sol:DeployMERAWalletUniswapV2AssetWhitelist RPC_URL="$(RPC_URL_POLYGON)" CHAIN_ID=137 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-asset-whitelist-amoy:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletUniswapV2AssetWhitelist.s.sol:DeployMERAWalletUniswapV2AssetWhitelist RPC_URL="$(RPC_URL_AMOY)" CHAIN_ID=80002 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-asset-whitelist-bsc:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletUniswapV2AssetWhitelist.s.sol:DeployMERAWalletUniswapV2AssetWhitelist RPC_URL="$(RPC_URL_BSC)" CHAIN_ID=56 VERIFY_API_KEY="$(BSCSCAN_API_KEY)"

deploy-erc20-approve-checker-polygon:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletERC20ApproveWhitelistChecker.s.sol:DeployMERAWalletERC20ApproveWhitelistChecker RPC_URL="$(RPC_URL_POLYGON)" CHAIN_ID=137 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-erc20-approve-checker-amoy:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletERC20ApproveWhitelistChecker.s.sol:DeployMERAWalletERC20ApproveWhitelistChecker RPC_URL="$(RPC_URL_AMOY)" CHAIN_ID=80002 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-erc20-approve-checker-bsc:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletERC20ApproveWhitelistChecker.s.sol:DeployMERAWalletERC20ApproveWhitelistChecker RPC_URL="$(RPC_URL_BSC)" CHAIN_ID=56 VERIFY_API_KEY="$(BSCSCAN_API_KEY)"

deploy-erc20-transfer-checker-polygon:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletERC20TransferWhitelistChecker.s.sol:DeployMERAWalletERC20TransferWhitelistChecker RPC_URL="$(RPC_URL_POLYGON)" CHAIN_ID=137 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-erc20-transfer-checker-amoy:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletERC20TransferWhitelistChecker.s.sol:DeployMERAWalletERC20TransferWhitelistChecker RPC_URL="$(RPC_URL_AMOY)" CHAIN_ID=80002 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-erc20-transfer-checker-bsc:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletERC20TransferWhitelistChecker.s.sol:DeployMERAWalletERC20TransferWhitelistChecker RPC_URL="$(RPC_URL_BSC)" CHAIN_ID=56 VERIFY_API_KEY="$(BSCSCAN_API_KEY)"

deploy-target-blacklist-checker-polygon:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletTargetBlacklistChecker.s.sol:DeployMERAWalletTargetBlacklistChecker RPC_URL="$(RPC_URL_POLYGON)" CHAIN_ID=137 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-target-blacklist-checker-amoy:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletTargetBlacklistChecker.s.sol:DeployMERAWalletTargetBlacklistChecker RPC_URL="$(RPC_URL_AMOY)" CHAIN_ID=80002 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-target-blacklist-checker-bsc:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletTargetBlacklistChecker.s.sol:DeployMERAWalletTargetBlacklistChecker RPC_URL="$(RPC_URL_BSC)" CHAIN_ID=56 VERIFY_API_KEY="$(BSCSCAN_API_KEY)"

deploy-target-whitelist-checker-polygon:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletTargetWhitelistChecker.s.sol:DeployMERAWalletTargetWhitelistChecker RPC_URL="$(RPC_URL_POLYGON)" CHAIN_ID=137 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-target-whitelist-checker-amoy:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletTargetWhitelistChecker.s.sol:DeployMERAWalletTargetWhitelistChecker RPC_URL="$(RPC_URL_AMOY)" CHAIN_ID=80002 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-target-whitelist-checker-bsc:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletTargetWhitelistChecker.s.sol:DeployMERAWalletTargetWhitelistChecker RPC_URL="$(RPC_URL_BSC)" CHAIN_ID=56 VERIFY_API_KEY="$(BSCSCAN_API_KEY)"

deploy-target-blacklist-checker-ownable-polygon:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletTargetBlacklistCheckerOwnable.s.sol:DeployMERAWalletTargetBlacklistCheckerOwnable RPC_URL="$(RPC_URL_POLYGON)" CHAIN_ID=137 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-target-blacklist-checker-ownable-amoy:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletTargetBlacklistCheckerOwnable.s.sol:DeployMERAWalletTargetBlacklistCheckerOwnable RPC_URL="$(RPC_URL_AMOY)" CHAIN_ID=80002 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-target-blacklist-checker-ownable-bsc:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletTargetBlacklistCheckerOwnable.s.sol:DeployMERAWalletTargetBlacklistCheckerOwnable RPC_URL="$(RPC_URL_BSC)" CHAIN_ID=56 VERIFY_API_KEY="$(BSCSCAN_API_KEY)"

deploy-target-whitelist-checker-ownable-polygon:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletTargetWhitelistCheckerOwnable.s.sol:DeployMERAWalletTargetWhitelistCheckerOwnable RPC_URL="$(RPC_URL_POLYGON)" CHAIN_ID=137 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-target-whitelist-checker-ownable-amoy:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletTargetWhitelistCheckerOwnable.s.sol:DeployMERAWalletTargetWhitelistCheckerOwnable RPC_URL="$(RPC_URL_AMOY)" CHAIN_ID=80002 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-target-whitelist-checker-ownable-bsc:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletTargetWhitelistCheckerOwnable.s.sol:DeployMERAWalletTargetWhitelistCheckerOwnable RPC_URL="$(RPC_URL_BSC)" CHAIN_ID=56 VERIFY_API_KEY="$(BSCSCAN_API_KEY)"

deploy-uniswap-v2-oracle-slippage-checker-polygon:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletUniswapV2OracleSlippageChecker.s.sol:DeployMERAWalletUniswapV2OracleSlippageChecker RPC_URL="$(RPC_URL_POLYGON)" CHAIN_ID=137 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-uniswap-v2-oracle-slippage-checker-amoy:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletUniswapV2OracleSlippageChecker.s.sol:DeployMERAWalletUniswapV2OracleSlippageChecker RPC_URL="$(RPC_URL_AMOY)" CHAIN_ID=80002 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-uniswap-v2-oracle-slippage-checker-bsc:
	@$(MAKE) deploy-factory SCRIPT=script/DeployMERAWalletUniswapV2OracleSlippageChecker.s.sol:DeployMERAWalletUniswapV2OracleSlippageChecker RPC_URL="$(RPC_URL_BSC)" CHAIN_ID=56 VERIFY_API_KEY="$(BSCSCAN_API_KEY)"

verify-json-factory:
	@mkdir -p $(OUT_VERIFY_JSON_DIR)
	@$(FORGE) verify-contract $(VERIFY_JSON_FACTORY_ADDR) \
		src/MERAWalletCreate2Factory.sol:MERAWalletCreate2Factory \
		--chain $(VERIFY_JSON_CHAIN_ID) $(VERIFY_JSON_COMPILE) \
		--show-standard-json-input > $(OUT_VERIFY_JSON_DIR)/MERAWalletCreate2Factory.chain-$(VERIFY_JSON_CHAIN_ID).standard.json
	@echo Wrote $(OUT_VERIFY_JSON_DIR)/MERAWalletCreate2Factory.chain-$(VERIFY_JSON_CHAIN_ID).standard.json

verify-json-base-wallet:
	@mkdir -p $(OUT_VERIFY_JSON_DIR)
	@CTOR="$(VERIFY_JSON_BASE_WALLET_CTOR)"; \
	if [ -z "$$CTOR" ]; then CTOR=$$(cast abi-encode "c(address,address,address,address,address)" \
		"$(VERIFY_JSON_WALLET_PRIMARY)" "$(VERIFY_JSON_WALLET_BACKUP)" "$(VERIFY_JSON_WALLET_EMERGENCY)" \
		"$(VERIFY_JSON_WALLET_SIGNER)" "$(VERIFY_JSON_WALLET_GUARDIAN)"); fi; \
	$(FORGE) verify-contract $(VERIFY_JSON_BASE_WALLET_ADDR) src/BaseMERAWallet.sol:BaseMERAWallet \
		--chain $(VERIFY_JSON_CHAIN_ID) $(VERIFY_JSON_COMPILE) \
		--constructor-args "$$CTOR" \
		--show-standard-json-input > $(OUT_VERIFY_JSON_DIR)/BaseMERAWallet.chain-$(VERIFY_JSON_CHAIN_ID).standard.json
	@echo Wrote $(OUT_VERIFY_JSON_DIR)/BaseMERAWallet.chain-$(VERIFY_JSON_CHAIN_ID).standard.json
