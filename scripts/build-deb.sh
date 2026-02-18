#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build-deb"
DIST_DIR="${SCRIPT_DIR}/dist"
PACKAGE_TYPE="${1:-both}"

VERSION="${VERSION:-2.0.0}"
VERSION="${VERSION#v}"
VERSION="${VERSION%-rc*}"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"/{receiver,sender}

echo "Building PipeWire Network DEB packages (version: ${VERSION})..."

build_receiver_deb() {
    echo "Building receiver DEB..."
    cd "${BUILD_DIR}/receiver"
    local pkg="pipewire-network-receiver-${VERSION}"
    mkdir -p "${pkg}"/{src,systemd,firewalld,config,debian}

    cp "${SCRIPT_DIR}/src/pipewire-network-receiver.c"              "${pkg}/src/"
    cp "${SCRIPT_DIR}/Makefile"                                     "${pkg}/"
    cp "${SCRIPT_DIR}/systemd/pipewire-network-receiver.service"    "${pkg}/systemd/"
    cp "${SCRIPT_DIR}/firewalld/pipewire-network.xml"               "${pkg}/firewalld/"
    cp "${SCRIPT_DIR}/config/receiver.json"                         "${pkg}/config/"
    cp "${SCRIPT_DIR}/README.md"                                    "${pkg}/"
    cp "${SCRIPT_DIR}/LICENSE"                                      "${pkg}/"
    cp -r "${SCRIPT_DIR}/debian/receiver/"*                         "${pkg}/debian/"

    cd "${pkg}"
    dpkg-buildpackage -us -uc -b

    mkdir -p "${DIST_DIR}"
    find "${BUILD_DIR}/receiver" -maxdepth 2 -name "*.deb" -exec cp {} "${DIST_DIR}/" \;
    echo "Receiver DEB built."
}

build_sender_deb() {
    echo "Building sender DEB..."
    cd "${BUILD_DIR}/sender"
    local pkg="pipewire-network-sender-${VERSION}"
    mkdir -p "${pkg}"/{src,systemd,config,debian}

    cp "${SCRIPT_DIR}/src/pipewire-network-sender.c"               "${pkg}/src/"
    cp "${SCRIPT_DIR}/src/rtp-sender.c"                            "${pkg}/src/"
    cp "${SCRIPT_DIR}/src/pipewire-network-sender-config"          "${pkg}/src/"
    cp "${SCRIPT_DIR}/Makefile"                                    "${pkg}/"
    cp "${SCRIPT_DIR}/systemd/pipewire-network-sender@.service"    "${pkg}/systemd/"
    cp "${SCRIPT_DIR}/systemd/pipewire-network-sender.service"     "${pkg}/systemd/"
    cp "${SCRIPT_DIR}/config/sender.json"                          "${pkg}/config/"
    cp "${SCRIPT_DIR}/README.md"                                   "${pkg}/"
    cp "${SCRIPT_DIR}/LICENSE"                                     "${pkg}/"
    cp -r "${SCRIPT_DIR}/debian/sender/"*                          "${pkg}/debian/"

    cd "${pkg}"
    dpkg-buildpackage -us -uc -b

    mkdir -p "${DIST_DIR}"
    find "${BUILD_DIR}/sender" -maxdepth 2 -name "*.deb" -exec cp {} "${DIST_DIR}/" \;
    echo "Sender DEB built."
}

case "${PACKAGE_TYPE}" in
    receiver) build_receiver_deb ;;
    sender)   build_sender_deb ;;
    *)        build_receiver_deb; build_sender_deb ;;
esac

echo "Build complete! Packages in ${DIST_DIR}/"
