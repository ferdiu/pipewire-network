#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build-deb"
DIST_DIR="${SCRIPT_DIR}/dist"
PACKAGE_TYPE="${1:-both}"  # receiver, sender, or both

# Respect VERSION from the environment (e.g. set by CI); fall back to default.
VERSION="${VERSION:-2.0.0}"

# Strip a leading "v" so "v2.0.0-rc1" becomes "2.0.0-rc1"
VERSION="${VERSION#v}"

# Strip -rc ... part
VERSION="${VERSION%-*}"

# Clean and create build directory
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"/{receiver,sender}

echo "Building PipeWire Network DEB packages (version: ${VERSION})..."

build_receiver_deb() {
    echo "Building receiver DEB..."
    # Create package structure
    cd "${BUILD_DIR}/receiver"
    mkdir -p pipewire-network-receiver-${VERSION}/{src,systemd,firewalld,config,debian}

    # Copy source files
    cp "${SCRIPT_DIR}/src/pipewire-network-receiver" pipewire-network-receiver-${VERSION}/src/
    cp "${SCRIPT_DIR}/systemd/pipewire-network-receiver.service" pipewire-network-receiver-${VERSION}/systemd/
    cp "${SCRIPT_DIR}/firewalld/pipewire-network.xml" pipewire-network-receiver-${VERSION}/firewalld/
    cp "${SCRIPT_DIR}/config/receiver.json" pipewire-network-receiver-${VERSION}/config/
    cp "${SCRIPT_DIR}/README.md" pipewire-network-receiver-${VERSION}/
    cp "${SCRIPT_DIR}/LICENSE" pipewire-network-receiver-${VERSION}/

    # Copy debian control files
    cp -r "${SCRIPT_DIR}/debian/receiver/"* pipewire-network-receiver-${VERSION}/debian/

    # Copy pyproject to make sure pybuild works
    cp "${SCRIPT_DIR}/pyproject.toml" pipewire-network-receiver-${VERSION}/

    # Build package
    cd pipewire-network-receiver-${VERSION}
    dpkg-buildpackage -us -uc -b

    echo "Receiver DEB built: ${BUILD_DIR}/receiver/"

    # Copy debs to dist directory
    mkdir -p "${DIST_DIR}"
    find "${BUILD_DIR}/receiver" -maxdepth 2 -name "*.deb" -exec cp {} "${DIST_DIR}/" \;
}

build_sender_deb() {
    echo "Building sender DEB..."
    # Create package structure
    cd "${BUILD_DIR}/sender"
    mkdir -p pipewire-network-sender-${VERSION}/{src,systemd,config,debian}

    # Copy source files
    cp "${SCRIPT_DIR}/src/pipewire-network-sender" pipewire-network-sender-${VERSION}/src/
    cp "${SCRIPT_DIR}/src/pipewire-network-sender-config" pipewire-network-sender-${VERSION}/src/
    cp "${SCRIPT_DIR}/systemd/pipewire-network-sender@.service" pipewire-network-sender-${VERSION}/systemd/
    cp "${SCRIPT_DIR}/systemd/pipewire-network-sender.service" pipewire-network-sender-${VERSION}/systemd/
    cp "${SCRIPT_DIR}/config/sender.json" pipewire-network-sender-${VERSION}/config/
    cp "${SCRIPT_DIR}/README.md" pipewire-network-sender-${VERSION}/
    cp "${SCRIPT_DIR}/LICENSE" pipewire-network-sender-${VERSION}/

    # Copy debian control files
    cp -r "${SCRIPT_DIR}/debian/sender/"* pipewire-network-sender-${VERSION}/debian/

    # Copy pyproject to make sure pybuild works
    cp "${SCRIPT_DIR}/pyproject.toml" pipewire-network-sender-${VERSION}/

    # Build package
    cd pipewire-network-sender-${VERSION}
    dpkg-buildpackage -us -uc -b

    echo "Sender DEB built: ${BUILD_DIR}/sender/"

    # Copy debs to dist directory
    mkdir -p "${DIST_DIR}"
    find "${BUILD_DIR}/sender" -maxdepth 2 -name "*.deb" -exec cp {} "${DIST_DIR}/" \;
}

case "${PACKAGE_TYPE}" in
    receiver)
        build_receiver_deb
        ;;
    sender)
        build_sender_deb
        ;;
    both|*)
        build_receiver_deb
        build_sender_deb
        ;;
esac

echo "Build complete!"