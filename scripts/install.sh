#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_TYPE="${1:-both}"
PREFIX="${2:-/usr/local}"

echo "Installing PipeWire Network from source..."

# Build first
echo "Building..."
make -C "${SCRIPT_DIR}" PREFIX="${PREFIX}"

install_receiver() {
    echo "Installing receiver..."
    sudo install -m 755 "${SCRIPT_DIR}/pipewire-network-receiver" "${PREFIX}/bin/"

    sudo install -D -m 644 "${SCRIPT_DIR}/systemd/pipewire-network-receiver.service" \
        "/usr/lib/systemd/user/pipewire-network-receiver.service"
    sudo install -D -m 644 "${SCRIPT_DIR}/firewalld/pipewire-network.xml" \
        "/usr/lib/firewalld/services/pipewire-network.xml"
    sudo install -D -m 644 "${SCRIPT_DIR}/config/receiver.json" \
        "/etc/pipewire-network/receiver.json"

    echo "Receiver installed."
}

install_sender() {
    echo "Installing sender..."
    sudo install -m 755 "${SCRIPT_DIR}/pipewire-network-sender"            "${PREFIX}/bin/"
    sudo install -m 755 "${SCRIPT_DIR}/pipewire-network-rtp-sender"        "${PREFIX}/bin/"
    sudo install -m 755 "${SCRIPT_DIR}/src/pipewire-network-sender-config" "${PREFIX}/bin/"

    sudo install -D -m 644 "${SCRIPT_DIR}/systemd/pipewire-network-sender@.service" \
        "/usr/lib/systemd/user/pipewire-network-sender@.service"
    sudo install -D -m 644 "${SCRIPT_DIR}/systemd/pipewire-network-sender.service" \
        "/usr/lib/systemd/user/pipewire-network-sender.service"
    sudo install -D -m 644 "${SCRIPT_DIR}/config/sender.json" \
        "/etc/pipewire-network/sender.json"

    echo "Sender installed."
}

case "${PACKAGE_TYPE}" in
    receiver) install_receiver ;;
    sender)   install_sender ;;
    *)        install_receiver; install_sender ;;
esac

sudo systemctl daemon-reload
if systemctl is-active --quiet firewalld; then
    sudo firewall-cmd --reload
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  Receiver:"
echo "    systemctl --user enable --now pipewire-network-receiver.service"
echo ""
echo "  Sender:"
echo "    pipewire-network-sender-config create-sample"
echo "    pipewire-network-sender-config enable default"
