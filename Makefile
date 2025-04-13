.PHONY: docker-build docker-dev docker-push setup lint
GIT_TAG := $(shell git rev-parse --short HEAD)
export COMPOSE_BAKE=true
export VERSION=$(GIT_TAG)

docker-build:
	@docker compose build

docker-dev: docker-build
	@docker compose up --abort-on-container-exit

docker-push: docker-build
	@docker compose push

setup:
	@echo "Setting up git hooks..."
	@mkdir -p .hooks
	@git config core.hooksPath .hooks
	@echo "Git hooks configured to use .hooks directory"

lint:
	@echo "Running linters and formatters..."
	@npx -y pretty-quick --staged
