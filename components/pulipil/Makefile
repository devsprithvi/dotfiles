# pulipil — build automation

BINARY      := pulipil
PKG         := github.com/devsprithvi/pulipil
CMD         := ./cmd/pulipil
BIN_DIR     := bin
VERSION     ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "0.1.0-dev")
COMMIT      ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo none)
DATE        ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

LDFLAGS := -s -w \
	-X $(PKG)/internal/version.Version=$(VERSION) \
	-X $(PKG)/internal/version.Commit=$(COMMIT) \
	-X $(PKG)/internal/version.Date=$(DATE)

.PHONY: all build install run test vet fmt tidy clean

all: build

build: ## Build the binary into ./bin
	@mkdir -p $(BIN_DIR)
	go build -trimpath -ldflags "$(LDFLAGS)" -o $(BIN_DIR)/$(BINARY) $(CMD)

install: ## Install the binary into $GOBIN / $GOPATH/bin
	go install -trimpath -ldflags "$(LDFLAGS)" $(CMD)

run: ## Run against the example config (plan)
	go run $(CMD) plan -c examples/packages.cue

test: ## Run tests
	go test ./...

vet: ## Static analysis
	go vet ./...

fmt: ## Format sources
	go fmt ./...

tidy: ## Tidy module dependencies
	go mod tidy

clean: ## Remove build artefacts
	rm -rf $(BIN_DIR)
