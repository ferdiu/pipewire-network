#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
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

echo "Building PipeWire Network RPM packages (version: ${VERSION})..."

build_receiver_rpm() {
    echo "Building receiver RPM..."

    # Create source structure
    mkdir -p "${BUILD_DIR}/receiver/rpmbuild"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    mkdir -p "${BUILD_DIR}/receiver/pipewire-network-receiver-${VERSION}"/{src,systemd,firewalld,config}

    # Copy files
    cp "${SCRIPT_DIR}/src/pipewire-network-receiver" "${BUILD_DIR}/receiver/pipewire-network-receiver-${VERSION}/src/"
    cp "${SCRIPT_DIR}/systemd/pipewire-network-receiver.service" "${BUILD_DIR}/receiver/pipewire-network-receiver-${VERSION}/systemd/"
    cp "${SCRIPT_DIR}/firewalld/pipewire-network.xml" "${BUILD_DIR}/receiver/pipewire-network-receiver-${VERSION}/firewalld/"
    cp "${SCRIPT_DIR}/config/receiver.json" "${BUILD_DIR}/receiver/pipewire-network-receiver-${VERSION}/config/"
    cp "${SCRIPT_DIR}/README.md" "${BUILD_DIR}/receiver/pipewire-network-receiver-${VERSION}/"
    cp "${SCRIPT_DIR}/LICENSE" "${BUILD_DIR}/receiver/pipewire-network-receiver-${VERSION}/"

    # Create tarball
    cd "${BUILD_DIR}/receiver"
    tar czf "rpmbuild/SOURCES/pipewire-network-receiver-${VERSION}.tar.gz" pipewire-network-receiver-${VERSION}/

    # Copy spec file
    cp "${SCRIPT_DIR}/rpm/pipewire-network-receiver.spec" "rpmbuild/SPECS/"

    # Build RPM
    rpmbuild --define "_topdir $(pwd)/rpmbuild" -ba "rpmbuild/SPECS/pipewire-network-receiver.spec"

    echo "Receiver RPM built: ${BUILD_DIR}/receiver/rpmbuild/RPMS/"

    # Copy rpms to dist directory
    mkdir -p "${DIST_DIR}"
    cp "${BUILD_DIR}/receiver/rpmbuild/RPMS/noarch/"*.rpm "${DIST_DIR}/"
}

build_sender_rpm() {
    echo "Building sender RPM..."

    # Create source structure
    mkdir -p "${BUILD_DIR}/sender/rpmbuild"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    mkdir -p "${BUILD_DIR}/sender/pipewire-network-sender-${VERSION}"/{src,systemd,config}

    # Copy files
    cp "${SCRIPT_DIR}/src/pipewire-network-sender" "${BUILD_DIR}/sender/pipewire-network-sender-${VERSION}/src/"
    cp "${SCRIPT_DIR}/src/pipewire-network-sender-config" "${BUILD_DIR}/sender/pipewire-network-sender-${VERSION}/src/"
    cp "${SCRIPT_DIR}/systemd/pipewire-network-sender@.service" "${BUILD_DIR}/sender/pipewire-network-sender-${VERSION}/systemd/"
    cp "${SCRIPT_DIR}/systemd/pipewire-network-sender.service" "${BUILD_DIR}/sender/pipewire-network-sender-${VERSION}/systemd/"
    cp "${SCRIPT_DIR}/config/sender.json" "${BUILD_DIR}/sender/pipewire-network-sender-${VERSION}/config/"
    cp "${SCRIPT_DIR}/README.md" "${BUILD_DIR}/sender/pipewire-network-sender-${VERSION}/"
    cp "${SCRIPT_DIR}/LICENSE" "${BUILD_DIR}/sender/pipewire-network-sender-${VERSION}/"

    # Create tarball
    cd "${BUILD_DIR}/sender"
    tar czf "rpmbuild/SOURCES/pipewire-network-sender-${VERSION}.tar.gz" pipewire-network-sender-${VERSION}/

    # Copy spec file
    cp "${SCRIPT_DIR}/rpm/pipewire-network-sender.spec" "rpmbuild/SPECS/"

    # Build RPM
    rpmbuild --define "_topdir $(pwd)/rpmbuild" -ba "rpmbuild/SPECS/pipewire-network-sender.spec"

    echo "Sender RPM built: ${BUILD_DIR}/sender/rpmbuild/RPMS/"

    # Copy rpms to dist directory
    mkdir -p "${DIST_DIR}"
    cp "${BUILD_DIR}/sender/rpmbuild/RPMS/noarch/"*.rpm "${DIST_DIR}/"
}

case "${PACKAGE_TYPE}" in
    receiver)
        build_receiver_rpm
        ;;
    sender)
        build_sender_rpm
        ;;
    both|*)
        build_receiver_rpm
        build_sender_rpm
        ;;
esac

echo "Build complete!"