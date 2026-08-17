.PHONY: docker-build docker-dev docker-push build-test-exe setup lint
GIT_TAG := $(shell git rev-parse --short HEAD)
export TAG=$(GIT_TAG)
export VERSION=$(GIT_TAG)

# The wine/proton Docker targets COPY this binary in; it has to exist
# on the host before `docker buildx bake` runs.
build-test-exe:
	@cargo build --release

docker-build: build-test-exe
	@docker buildx bake --load

docker-dev: docker-build
	@docker compose up --abort-on-container-exit

docker-push: build-test-exe
	@docker buildx bake --push

setup:
	@echo "Setting up git hooks..."
	@mkdir -p .hooks
	@git config core.hooksPath .hooks
	@echo "Git hooks configured to use .hooks directory"

lint:
	@echo "Running linters and formatters..."
	@npx -y pretty-quick --staged
