# kubectl-documentdb Makefile
# Build multi-platform binaries for kubectl plugin

VERSION ?= dev
BINARY_NAME = kubectl-documentdb
BUILD_DIR = dist

# Go build flags
LDFLAGS = -s -w -X main.version=$(VERSION)
GO_BUILD = CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)"

# Platform targets
PLATFORMS := \
	linux/amd64 \
	linux/arm64 \
	linux/arm \
	darwin/amd64 \
	darwin/arm64 \
	windows/amd64 \
	windows/arm64

.PHONY: all
all: clean build-all

.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@rm -f $(BINARY_NAME) $(BINARY_NAME).exe

.PHONY: build
build:
	@echo "Building $(BINARY_NAME)..."
	@go build -ldflags "$(LDFLAGS)" -o $(BINARY_NAME) .

.PHONY: build-all
build-all: $(PLATFORMS)

.PHONY: test
test:
	@echo "Running tests..."
	@go test -v ./...

.PHONY: fmt
fmt:
	@echo "Formatting code..."
	@go fmt ./...

.PHONY: vet
vet:
	@echo "Running go vet..."
	@go vet ./...

.PHONY: lint
lint: fmt vet
	@echo "Running golangci-lint..."
	@golangci-lint run || true

# Build for specific platform
.PHONY: $(PLATFORMS)
$(PLATFORMS):
	$(eval GOOS := $(word 1,$(subst /, ,$@)))
	$(eval GOARCH := $(word 2,$(subst /, ,$@)))
	$(eval OUTPUT_NAME := $(BUILD_DIR)/$(BINARY_NAME)-$(GOOS)-$(GOARCH))
	$(eval ARCHIVE_NAME := $(BINARY_NAME)-$(GOOS)-$(GOARCH))
	
	@echo "Building for $(GOOS)/$(GOARCH)..."
	@mkdir -p $(BUILD_DIR)
	
	@if [ "$(GOOS)" = "windows" ]; then \
		GOOS=$(GOOS) GOARCH=$(GOARCH) $(GO_BUILD) -o $(OUTPUT_NAME).exe; \
		cd $(BUILD_DIR) && zip $(ARCHIVE_NAME).zip $(BINARY_NAME)-$(GOOS)-$(GOARCH).exe; \
		cd $(BUILD_DIR) && sha256sum $(ARCHIVE_NAME).zip > $(ARCHIVE_NAME).zip.sha256; \
	else \
		GOOS=$(GOOS) GOARCH=$(GOARCH) $(GO_BUILD) -o $(OUTPUT_NAME); \
		cd $(BUILD_DIR) && tar czf $(ARCHIVE_NAME).tar.gz $(BINARY_NAME)-$(GOOS)-$(GOARCH); \
		cd $(BUILD_DIR) && sha256sum $(ARCHIVE_NAME).tar.gz > $(ARCHIVE_NAME).tar.gz.sha256; \
	fi

# Install locally (builds for current platform and installs to /usr/local/bin)
.PHONY: install
install: build
	@echo "Installing $(BINARY_NAME) to /usr/local/bin..."
	@sudo mv $(BINARY_NAME) /usr/local/bin/
	@echo "Installation complete. Try: kubectl documentdb --help"

# Quick build for current platform
.PHONY: dev
dev:
	@echo "Building for development..."
	@go build -o $(BINARY_NAME) .

# Generate release archives for all platforms
.PHONY: release
release: clean test build-all
	@echo "Release artifacts created in $(BUILD_DIR)/"
	@ls -lh $(BUILD_DIR)/

# Help target
.PHONY: help
help:
	@echo "kubectl-documentdb Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make build          Build for current platform"
	@echo "  make build-all      Build for all platforms"
	@echo "  make install        Build and install locally"
	@echo "  make dev            Quick development build"
	@echo "  make release        Create release archives for all platforms"
	@echo "  make test           Run tests"
	@echo "  make lint           Run linters"
	@echo "  make clean          Remove build artifacts"
	@echo ""
	@echo "Platform-specific builds:"
	@echo "  make linux/amd64"
	@echo "  make linux/arm64"
	@echo "  make darwin/amd64"
	@echo "  make darwin/arm64"
	@echo "  make windows/amd64"
	@echo ""
	@echo "Environment variables:"
	@echo "  VERSION=x.y.z       Set version (default: dev)"
