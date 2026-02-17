#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_TYPE="${1:-both}"  # receiver, sender, or both
PREFIX="${2:-/usr/local}"

echo "Installing PipeWire Network from source..."

install_receiver() {
    echo "Installing receiver..."

    # Install binary
    sudo install -m 755 "${SCRIPT_DIR}/src/pipewire-network-receiver" "${PREFIX}/bin/"

    # Install systemd user service
    sudo install -D -m 644 "${SCRIPT_DIR}/systemd/pipewire-network-receiver.service" \
        "/usr/lib/systemd/user/pipewire-network-receiver.service"

    # Install firewalld service definition
    sudo install -D -m 644 "${SCRIPT_DIR}/firewalld/pipewire-network.xml" \
        "/usr/lib/firewalld/services/pipewire-network.xml"

    # Install default configuration
    sudo install -D -m 644 "${SCRIPT_DIR}/config/receiver.json" \
        "/etc/pipewire-network/receiver.json"

    echo "Receiver installed successfully!"
}

install_sender() {
    echo "Installing sender..."

    # Install binary
    sudo install -m 755 "${SCRIPT_DIR}/src/pipewire-network-sender" "${PREFIX}/bin/"

    # Install configuration manager
    sudo install -m 755 "${SCRIPT_DIR}/src/pipewire-network-sender-config" "${PREFIX}/bin/"

    # Install systemd user services (both template and default)
    sudo install -D -m 644 "${SCRIPT_DIR}/systemd/pipewire-network-sender@.service" \
        "/usr/lib/systemd/user/pipewire-network-sender@.service"
    sudo install -D -m 644 "${SCRIPT_DIR}/systemd/pipewire-network-sender.service" \
        "/usr/lib/systemd/user/pipewire-network-sender.service"

    # Install default configuration
    sudo install -D -m 644 "${SCRIPT_DIR}/config/sender.json" \
        "/etc/pipewire-network/sender.json"

    echo "Sender installed successfully!"
}

case "${PACKAGE_TYPE}" in
    receiver)
        install_receiver
        ;;
    sender)
        install_sender
        ;;
    both|*)
        install_receiver
        install_sender
        ;;
esac

# Reload systemd and firewalld
sudo systemctl daemon-reload
if systemctl is-active --quiet firewalld; then
    sudo firewall-cmd --reload
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Create configuration file:"
echo "   pipewire-network-sender-config create-sample"
echo ""
echo "2. List and edit configurations:"
echo "   pipewire-network-sender-config list"
echo "   editor ~/.config/pipewire-network/sender.json"
echo ""
echo "3. Enable and start services:"
echo "   pipewire-network-sender-config enable default      # for default config"
echo "   pipewire-network-sender-config enable office       # for office config"
echo ""
echo "4. Or use systemd directly:"
echo "   systemctl --user enable pipewire-network-sender@office.service"
echo "   systemctl --user start pipewire-network-sender@office.service"
