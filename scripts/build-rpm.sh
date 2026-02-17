#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
DIST_DIR="${SCRIPT_DIR}/dist"
PACKAGE_TYPE="${1:-both}"  # server, client, or both

# Respect VERSION from the environment (e.g. set by CI); fall back to default.
VERSION="${VERSION:-2.0.0}"

# Strip a leading "v" so "v2.0.0-rc1" becomes "2.0.0-rc1"
VERSION="${VERSION#v}"

# Clean and create build directory
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"/{server,client}

echo "Building PipeWire Network RPM packages (version: ${VERSION})..."

build_server_rpm() {
    echo "Building server RPM..."

    # Create source structure
    mkdir -p "${BUILD_DIR}/server/rpmbuild"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    mkdir -p "${BUILD_DIR}/server/pipewire-network-server-${VERSION}"/{src,systemd,firewalld,config}

    # Copy files
    cp "${SCRIPT_DIR}/src/pipewire-network-server" "${BUILD_DIR}/server/pipewire-network-server-${VERSION}/src/"
    cp "${SCRIPT_DIR}/systemd/pipewire-network-server.service" "${BUILD_DIR}/server/pipewire-network-server-${VERSION}/systemd/"
    cp "${SCRIPT_DIR}/firewalld/pipewire-network.xml" "${BUILD_DIR}/server/pipewire-network-server-${VERSION}/firewalld/"
    cp "${SCRIPT_DIR}/config/server.json" "${BUILD_DIR}/server/pipewire-network-server-${VERSION}/config/"
    cp "${SCRIPT_DIR}/README.md" "${BUILD_DIR}/server/pipewire-network-server-${VERSION}/"
    cp "${SCRIPT_DIR}/LICENSE" "${BUILD_DIR}/server/pipewire-network-server-${VERSION}/"

    # Create tarball
    cd "${BUILD_DIR}/server"
    tar czf "rpmbuild/SOURCES/pipewire-network-server-${VERSION}.tar.gz" pipewire-network-server-${VERSION}/

    # Copy spec file and inject version
    sed "s/^Version:.*/Version:        ${VERSION}/" \
        "${SCRIPT_DIR}/rpm/pipewire-network-server.spec" \
        > "rpmbuild/SPECS/pipewire-network-server.spec"

    # Build RPM
    rpmbuild --define "_topdir $(pwd)/rpmbuild" -ba "rpmbuild/SPECS/pipewire-network-server.spec"

    echo "Server RPM built: ${BUILD_DIR}/server/rpmbuild/RPMS/"

    # Copy rpms to dist directory
    mkdir -p "${DIST_DIR}"
    cp "${BUILD_DIR}/server/rpmbuild/RPMS/noarch/"*.rpm "${DIST_DIR}/"
}

build_client_rpm() {
    echo "Building client RPM..."

    # Create source structure
    mkdir -p "${BUILD_DIR}/client/rpmbuild"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    mkdir -p "${BUILD_DIR}/client/pipewire-network-client-${VERSION}"/{src,systemd,config}

    # Copy files
    cp "${SCRIPT_DIR}/src/pipewire-network-client" "${BUILD_DIR}/client/pipewire-network-client-${VERSION}/src/"
    cp "${SCRIPT_DIR}/src/pipewire-network-client-config" "${BUILD_DIR}/client/pipewire-network-client-${VERSION}/src/"
    cp "${SCRIPT_DIR}/systemd/pipewire-network-client@.service" "${BUILD_DIR}/client/pipewire-network-client-${VERSION}/systemd/"
    cp "${SCRIPT_DIR}/systemd/pipewire-network-client.service" "${BUILD_DIR}/client/pipewire-network-client-${VERSION}/systemd/"
    cp "${SCRIPT_DIR}/config/client.json" "${BUILD_DIR}/client/pipewire-network-client-${VERSION}/config/"
    cp "${SCRIPT_DIR}/README.md" "${BUILD_DIR}/client/pipewire-network-client-${VERSION}/"
    cp "${SCRIPT_DIR}/LICENSE" "${BUILD_DIR}/client/pipewire-network-client-${VERSION}/"

    # Create tarball
    cd "${BUILD_DIR}/client"
    tar czf "rpmbuild/SOURCES/pipewire-network-client-${VERSION}.tar.gz" pipewire-network-client-${VERSION}/

    # Copy spec file and inject version
    sed "s/^Version:.*/Version:        ${VERSION}/" \
        "${SCRIPT_DIR}/rpm/pipewire-network-client.spec" \
        > "rpmbuild/SPECS/pipewire-network-client.spec"

    # Build RPM
    rpmbuild --define "_topdir $(pwd)/rpmbuild" -ba "rpmbuild/SPECS/pipewire-network-client.spec"

    echo "Client RPM built: ${BUILD_DIR}/client/rpmbuild/RPMS/"

    # Copy rpms to dist directory
    mkdir -p "${DIST_DIR}"
    cp "${BUILD_DIR}/client/rpmbuild/RPMS/noarch/"*.rpm "${DIST_DIR}/"
}

case "${PACKAGE_TYPE}" in
    server)
        build_server_rpm
        ;;
    client)
        build_client_rpm
        ;;
    both|*)
        build_server_rpm
        build_client_rpm
        ;;
esac

echo "Build complete!"