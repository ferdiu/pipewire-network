#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_TYPE="${1:-both}"  # server, client, or both
PREFIX="${2:-/usr/local}"

echo "Installing PipeWire Network from source..."

install_server() {
    echo "Installing server..."

    # Install binary
    sudo install -m 755 "${SCRIPT_DIR}/src/pipewire-network-server" "${PREFIX}/bin/"

    # Install systemd user service
    sudo install -D -m 644 "${SCRIPT_DIR}/systemd/pipewire-network-server.service" \
        "/usr/lib/systemd/user/pipewire-network-server.service"

    # Install firewalld service definition
    sudo install -D -m 644 "${SCRIPT_DIR}/firewalld/pipewire-network.xml" \
        "/usr/lib/firewalld/services/pipewire-network.xml"

    # Install default configuration
    sudo install -D -m 644 "${SCRIPT_DIR}/config/server.json" \
        "/etc/pipewire-network/server.json"

    echo "Server installed successfully!"
}

install_client() {
    echo "Installing client..."

    # Install binary
    sudo install -m 755 "${SCRIPT_DIR}/src/pipewire-network-client" "${PREFIX}/bin/"

    # Install configuration manager
    sudo install -m 755 "${SCRIPT_DIR}/src/pipewire-network-client-config" "${PREFIX}/bin/"

    # Install systemd user services (both template and default)
    sudo install -D -m 644 "${SCRIPT_DIR}/systemd/pipewire-network-client@.service" \
        "/usr/lib/systemd/user/pipewire-network-client@.service"
    sudo install -D -m 644 "${SCRIPT_DIR}/systemd/pipewire-network-client.service" \
        "/usr/lib/systemd/user/pipewire-network-client.service"

    # Install default configuration
    sudo install -D -m 644 "${SCRIPT_DIR}/config/client.json" \
        "/etc/pipewire-network/client.json"

    echo "Client installed successfully!"
}

case "${PACKAGE_TYPE}" in
    server)
        install_server
        ;;
    client)
        install_client
        ;;
    both|*)
        install_server
        install_client
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
echo "   pipewire-network-client-config create-sample"
echo ""
echo "2. List and edit configurations:"
echo "   pipewire-network-client-config list"
echo "   editor ~/.config/pipewire-network/client.json"
echo ""
echo "3. Enable and start services:"
echo "   pipewire-network-client-config enable default      # for default config"
echo "   pipewire-network-client-config enable office       # for office config"
echo ""
echo "4. Or use systemd directly:"
echo "   systemctl --user enable pipewire-network-client@office.service"
echo "   systemctl --user start pipewire-network-client@office.service"
