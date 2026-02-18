#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
DIST_DIR="${SCRIPT_DIR}/dist"
PACKAGE_TYPE="${1:-both}"

VERSION="${VERSION:-2.0.0}"
VERSION="${VERSION#v}"
VERSION="${VERSION%-rc*}"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"/{receiver,sender}

echo "Building PipeWire Network RPM packages (version: ${VERSION})..."

build_receiver_rpm() {
    echo "Building receiver RPM..."
    mkdir -p "${BUILD_DIR}/receiver/rpmbuild"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    local pkg="pipewire-network-receiver-${VERSION}"
    mkdir -p "${BUILD_DIR}/receiver/${pkg}"/{src,systemd,firewalld,config}

    cp "${SCRIPT_DIR}/src/pipewire-network-receiver.c"           "${BUILD_DIR}/receiver/${pkg}/src/"
    cp "${SCRIPT_DIR}/Makefile"                                  "${BUILD_DIR}/receiver/${pkg}/"
    cp "${SCRIPT_DIR}/systemd/pipewire-network-receiver.service" "${BUILD_DIR}/receiver/${pkg}/systemd/"
    cp "${SCRIPT_DIR}/firewalld/pipewire-network.xml"            "${BUILD_DIR}/receiver/${pkg}/firewalld/"
    cp "${SCRIPT_DIR}/config/receiver.json"                      "${BUILD_DIR}/receiver/${pkg}/config/"
    cp "${SCRIPT_DIR}/README.md"                                 "${BUILD_DIR}/receiver/${pkg}/"
    cp "${SCRIPT_DIR}/LICENSE"                                   "${BUILD_DIR}/receiver/${pkg}/"

    cd "${BUILD_DIR}/receiver"
    tar czf "rpmbuild/SOURCES/${pkg}.tar.gz" "${pkg}/"
    cp "${SCRIPT_DIR}/rpm/pipewire-network-receiver.spec" "rpmbuild/SPECS/"
    rpmbuild --define "_topdir $(pwd)/rpmbuild" \
             --define "version ${VERSION}" \
             -ba "rpmbuild/SPECS/pipewire-network-receiver.spec"

    mkdir -p "${DIST_DIR}"
    find "${BUILD_DIR}/receiver/rpmbuild/RPMS" -name "*.rpm" -exec cp {} "${DIST_DIR}/" \;
    echo "Receiver RPM built."
}

build_sender_rpm() {
    echo "Building sender RPM..."
    mkdir -p "${BUILD_DIR}/sender/rpmbuild"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    local pkg="pipewire-network-sender-${VERSION}"
    mkdir -p "${BUILD_DIR}/sender/${pkg}"/{src,systemd,config}

    cp "${SCRIPT_DIR}/src/pipewire-network-sender.c"            "${BUILD_DIR}/sender/${pkg}/src/"
    cp "${SCRIPT_DIR}/src/rtp-sender.c"                         "${BUILD_DIR}/sender/${pkg}/src/"
    cp "${SCRIPT_DIR}/src/pipewire-network-sender-config"       "${BUILD_DIR}/sender/${pkg}/src/"
    cp "${SCRIPT_DIR}/Makefile"                                 "${BUILD_DIR}/sender/${pkg}/"
    cp "${SCRIPT_DIR}/systemd/pipewire-network-sender@.service" "${BUILD_DIR}/sender/${pkg}/systemd/"
    cp "${SCRIPT_DIR}/systemd/pipewire-network-sender.service"  "${BUILD_DIR}/sender/${pkg}/systemd/"
    cp "${SCRIPT_DIR}/config/sender.json"                       "${BUILD_DIR}/sender/${pkg}/config/"
    cp "${SCRIPT_DIR}/README.md"                                "${BUILD_DIR}/sender/${pkg}/"
    cp "${SCRIPT_DIR}/LICENSE"                                  "${BUILD_DIR}/sender/${pkg}/"

    cd "${BUILD_DIR}/sender"
    tar czf "rpmbuild/SOURCES/${pkg}.tar.gz" "${pkg}/"
    cp "${SCRIPT_DIR}/rpm/pipewire-network-sender.spec" "rpmbuild/SPECS/"
    rpmbuild --define "_topdir $(pwd)/rpmbuild" \
             --define "version ${VERSION}" \
             -ba "rpmbuild/SPECS/pipewire-network-sender.spec"

    mkdir -p "${DIST_DIR}"
    find "${BUILD_DIR}/sender/rpmbuild/RPMS" -name "*.rpm" -exec cp {} "${DIST_DIR}/" \;
    echo "Sender RPM built."
}

case "${PACKAGE_TYPE}" in
    receiver) build_receiver_rpm ;;
    sender)   build_sender_rpm ;;
    *)        build_receiver_rpm; build_sender_rpm ;;
esac

echo "Build complete! Packages in ${DIST_DIR}/"
