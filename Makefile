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

# Shared deploy: set RPC_URL, CHAIN_ID (EIP-155), and optionally VERIFY_API_KEY for --verify.
# Explicit --chain fixes explorer/API targeting; without it, forge script --verify can fail with "No contract bytecode" on L2/sidechains.
deploy-factory:
	$(FORGE) script $(SCRIPT) --rpc-url $(RPC_URL) --chain $(CHAIN_ID) --broadcast --private-key $(PRIVATE_KEY) \
		$(if $(strip $(VERIFY_API_KEY)),--verify --etherscan-api-key $(VERIFY_API_KEY),) -vvvv

deploy-factory-polygon:
	@$(MAKE) deploy-factory RPC_URL="$(RPC_URL_POLYGON)" CHAIN_ID=137 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-factory-amoy:
	@$(MAKE) deploy-factory RPC_URL="$(RPC_URL_AMOY)" CHAIN_ID=80002 VERIFY_API_KEY="$(POLYGONSCAN_API_KEY)"

deploy-factory-bsc:
	@$(MAKE) deploy-factory RPC_URL="$(RPC_URL_BSC)" CHAIN_ID=56 VERIFY_API_KEY="$(BSCSCAN_API_KEY)"
