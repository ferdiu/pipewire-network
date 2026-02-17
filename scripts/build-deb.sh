#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build-deb"
DIST_DIR="${SCRIPT_DIR}/dist"
PACKAGE_TYPE="${1:-both}"  # server, client, or both

# Respect VERSION from the environment (e.g. set by CI); fall back to default.
VERSION="${VERSION:-2.0.0}"

# Strip a leading "v" so "v2.0.0-rc1" becomes "2.0.0-rc1"
VERSION="${VERSION#v}"

# Strip -rc ... part
VERSION="${VERSION%-*}"

# Clean and create build directory
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"/{server,client}

echo "Building PipeWire Network DEB packages (version: ${VERSION})..."

build_server_deb() {
    echo "Building server DEB..."
    # Create package structure
    cd "${BUILD_DIR}/server"
    mkdir -p pipewire-network-server-${VERSION}/{src,systemd,firewalld,config,debian}

    # Copy source files
    cp "${SCRIPT_DIR}/src/pipewire-network-server" pipewire-network-server-${VERSION}/src/
    cp "${SCRIPT_DIR}/systemd/pipewire-network-server.service" pipewire-network-server-${VERSION}/systemd/
    cp "${SCRIPT_DIR}/firewalld/pipewire-network.xml" pipewire-network-server-${VERSION}/firewalld/
    cp "${SCRIPT_DIR}/config/server.json" pipewire-network-server-${VERSION}/config/
    cp "${SCRIPT_DIR}/README.md" pipewire-network-server-${VERSION}/
    cp "${SCRIPT_DIR}/LICENSE" pipewire-network-server-${VERSION}/

    # Copy debian control files
    cp -r "${SCRIPT_DIR}/debian/server/"* pipewire-network-server-${VERSION}/debian/

    # Build package
    cd pipewire-network-server-${VERSION}
    dpkg-buildpackage -us -uc -b

    echo "Server DEB built: ${BUILD_DIR}/server/"

    # Copy debs to dist directory
    mkdir -p "${DIST_DIR}"
    cp "${BUILD_DIR}/server/"*.deb "${DIST_DIR}/"
}

build_client_deb() {
    echo "Building client DEB..."
    # Create package structure
    cd "${BUILD_DIR}/client"
    mkdir -p pipewire-network-client-${VERSION}/{src,systemd,config,debian}

    # Copy source files
    cp "${SCRIPT_DIR}/src/pipewire-network-client" pipewire-network-client-${VERSION}/src/
    cp "${SCRIPT_DIR}/src/pipewire-network-client-config" pipewire-network-client-${VERSION}/src/
    cp "${SCRIPT_DIR}/systemd/pipewire-network-client@.service" pipewire-network-client-${VERSION}/systemd/
    cp "${SCRIPT_DIR}/systemd/pipewire-network-client.service" pipewire-network-client-${VERSION}/systemd/
    cp "${SCRIPT_DIR}/config/client.json" pipewire-network-client-${VERSION}/config/
    cp "${SCRIPT_DIR}/README.md" pipewire-network-client-${VERSION}/
    cp "${SCRIPT_DIR}/LICENSE" pipewire-network-client-${VERSION}/

    # Copy debian control files
    cp -r "${SCRIPT_DIR}/debian/client/"* pipewire-network-client-${VERSION}/debian/

    # Build package
    cd pipewire-network-client-${VERSION}
    dpkg-buildpackage -us -uc -b

    echo "Client DEB built: ${BUILD_DIR}/client/"

    # Copy debs to dist directory
    mkdir -p "${DIST_DIR}"
    cp "${BUILD_DIR}/client/"*.deb "${DIST_DIR}/"
}

case "${PACKAGE_TYPE}" in
    server)
        build_server_deb
        ;;
    client)
        build_client_deb
        ;;
    both|*)
        build_server_deb
        build_client_deb
        ;;
esac

echo "Build complete!"