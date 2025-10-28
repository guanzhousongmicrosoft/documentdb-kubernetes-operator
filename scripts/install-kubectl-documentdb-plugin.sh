#!/bin/bash
# kubectl-documentdb installation script
# Auto-detects platform and architecture
set -e

VERSION="${1:-latest}"
REPO="guanzhousongmicrosoft/documentdb-kubernetes-operator"

# Detect OS
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
  linux*) OS="linux" ;;
  darwin*) OS="darwin" ;;
  *) 
    echo "Error: Unsupported OS: $OS"
    echo "Supported: Linux, macOS"
    exit 1 
    ;;
esac

# Detect Architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  amd64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  aarch64) ARCH="arm64" ;;
  *) 
    echo "Error: Unsupported architecture: $ARCH"
    echo "Supported: amd64, arm64"
    exit 1 
    ;;
esac

PLATFORM="${OS}-${ARCH}"
BINARY="kubectl-documentdb"
ARCHIVE="${BINARY}-${PLATFORM}.tar.gz"

# Construct download URL
if [ "$VERSION" = "latest" ]; then
  URL="https://github.com/${REPO}/releases/latest/download/${ARCHIVE}"
  echo "Installing latest version of kubectl-documentdb for ${PLATFORM}..."
else
  URL="https://github.com/${REPO}/releases/download/${VERSION}/${ARCHIVE}"
  echo "Installing kubectl-documentdb ${VERSION} for ${PLATFORM}..."
fi

# Download
echo "Downloading from: $URL"
if command -v curl &> /dev/null; then
  curl -fsSL -o "$ARCHIVE" "$URL"
elif command -v wget &> /dev/null; then
  wget -q -O "$ARCHIVE" "$URL"
else
  echo "Error: curl or wget is required"
  exit 1
fi

# Extract
echo "Extracting..."
tar xzf "$ARCHIVE"

# Install
INSTALL_DIR="/usr/local/bin"
echo "Installing to ${INSTALL_DIR}..."
chmod +x "$BINARY"

if [ -w "$INSTALL_DIR" ]; then
  mv "$BINARY" "$INSTALL_DIR/"
else
  sudo mv "$BINARY" "$INSTALL_DIR/"
fi

# Cleanup
echo "Cleaning up..."
rm "$ARCHIVE"

# Verify
if command -v kubectl-documentdb &> /dev/null; then
  echo ""
  echo "✓ kubectl-documentdb installed successfully!"
  echo "Version: $(kubectl-documentdb version 2>/dev/null || echo 'unknown')"
  echo ""
  echo "Get started:"
  echo "  kubectl documentdb --help"
else
  echo "Warning: kubectl-documentdb was installed but not found in PATH"
  echo "You may need to add $INSTALL_DIR to your PATH"
fi
