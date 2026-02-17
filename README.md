# PipeWire Network Audio Streaming

A reliable solution for streaming audio over the network using PipeWire's RTP transport. This project provides both server and client components with proper configuration management, health monitoring, and packaging for Fedora (RPM) and Debian/Ubuntu (DEB).

> This is a full-reimplementation of my old project [pulseaudio-network](https://github.com/ferdiu/pulseaudio-network) which used TCP sinks which could not guarantee the same low-latency as RTP sinks do.

## Features

### Server Features
- **RTP Sender**: Streams audio via RTP (unicast or multicast)
- **Configuration Management**: JSON-based configuration with automatic defaults
- **Health Monitoring**: Automatic PipeWire connection monitoring
- **Firewall Integration**: Includes firewalld service definition
- **Graceful Shutdown**: Proper module cleanup on service stop

### Client Features
- **Multi-Server Support**: Receive from multiple RTP streams simultaneously
- **Auto-Reconnection**: Automatic reconnection with configurable retry logic
- **Health Monitoring**: Connection and PipeWire health checks
- **Custom Sink Names**: Configurable sink names and descriptions
- **Graceful Degradation**: Continues operating even if some streams are unavailable

## Project Structure

```
pipewire-network/
├── src/
│   ├── pipewire-network-server          # Python server script
│   └── pipewire-network-client          # Python client script
├── systemd/
│   ├── pipewire-network-server.service  # Systemd user service for server
│   └── pipewire-network-client.service  # Systemd user service for client
├── config/
│   ├── server.json                      # Default server configuration
│   └── client.json                      # Default client configuration
├── firewalld/
│   └── pipewire-network.xml             # Firewalld service definition
├── rpm/
│   ├── pipewire-network-server.spec     # RPM spec file for server
│   └── pipewire-network-client.spec     # RPM spec file for client
├── debian/
│   ├── server/                          # Debian packaging files for server
│   │   ├── control
│   │   ├── rules
│   │   ├── postinst
│   │   ├── prerm
│   │   ├── postrm
│   │   ├── changelog
│   │   ├── compat
│   │   └── copyright
│   └── client/                          # Debian packaging files for client
│       ├── control
│       ├── rules
│       ├── postinst
│       ├── prerm
│       ├── changelog
│       ├── compat
│       └── copyright
├── scripts/
│   ├── build-rpm.sh                     # Build RPM packages
│   ├── build-deb.sh                     # Build DEB packages
│   └── install.sh                       # Install from source
├── README.md
└── LICENSE
```

## Installation

### From Packages

#### Fedora/RHEL/CentOS (RPM)
```bash
# Build packages
./scripts/build-rpm.sh

# Install server
sudo dnf install build/server/rpmbuild/RPMS/noarch/pipewire-network-server-*.rpm

# Install client
sudo dnf install build/client/rpmbuild/RPMS/noarch/pipewire-network-client-*.rpm
```

#### Debian/Ubuntu (DEB)
```bash
# Build packages
./scripts/build-deb.sh

# Install server
sudo dpkg -i build-deb/server/pipewire-network-server_*.deb
sudo apt-get install -f  # Fix dependencies if needed

# Install client
sudo dpkg -i build-deb/client/pipewire-network-client_*.deb
sudo apt-get install -f  # Fix dependencies if needed
```

### From Source
```bash
# Install both server and client
./scripts/install.sh

# Install only server
./scripts/install.sh server

# Install only client
./scripts/install.sh client
```

## Configuration

### Server Configuration

Edit `~/.config/pipewire-network/server.json`:

```json
{
  "rtp_destination": "224.0.0.56",
  "rtp_port": 46998,
  "source_address": "0.0.0.0",
  "mtu": 1280,
  "loop": false,
  "ttl": 1,
  "sample_spec": null,
  "channel_map": null
}
```

**Configuration Options:**
- `rtp_destination`: Multicast or unicast destination address (default: `"224.0.0.56"`)
- `rtp_port`: UDP port for the RTP stream (default: `46998`)
- `source_address`: Source interface address to bind to (default: `"0.0.0.0"`)
- `mtu`: Maximum Transmission Unit for RTP packets (default: `1280`)
- `loop`: Enable multicast loopback (default: `false`)
- `ttl`: Multicast TTL (default: `1`)
- `sample_spec`: Custom sample specification (e.g., `"s16le 44100 2"`)
- `channel_map`: Custom channel map (e.g., `"front-left,front-right"`)

### Client Configuration

Edit `~/.config/pipewire-network/client.json` with named configurations:

```json
{
  "default": {
    "streams": [
      {
        "rtp_destination": "224.0.0.56",
        "rtp_port": 46998,
        "sink_name": "network_sink_main",
        "sink_description": "Main Network Audio Sink"
      }
    ],
    "auto_connect": true,
    "retry_interval": 10,
    "max_retries": -1
  }
}
```

**Configuration Options:**
- **Named Configurations**: Each top-level key is a configuration name
- **Multiple Instances**: Run different configs simultaneously with systemd templates
- **Backwards Compatibility**: Old format is automatically migrated
- **Unique Sink Names**: Each config gets unique sink names to avoid conflicts

**Stream fields:**
- `rtp_destination`: Multicast group or unicast address the server is sending to
- `rtp_port`: UDP port matching the server
- `sink_name`: Local sink name to create
- `sink_description`: Human-readable description

## Usage

### Server Setup

1. **Install and configure firewall** (if using firewalld):
   ```bash
   sudo firewall-cmd --permanent --add-service=pipewire-network
   sudo firewall-cmd --reload
   ```

2. **Enable and start the service**:
   ```bash
   systemctl --user enable pipewire-network-server.service
   systemctl --user start pipewire-network-server.service
   ```

3. **Check status**:
   ```bash
   systemctl --user status pipewire-network-server.service
   journalctl --user -u pipewire-network-server.service
   ```

### Client Setup

1. **Create and configure multiple setups**:
   ```bash
   # Create sample configuration with multiple named configs
   pipewire-network-client-config create-sample

   # List available configurations
   pipewire-network-client-config list

   # Validate a specific configuration
   pipewire-network-client-config validate office
   ```

2. **Enable specific configurations**:
   ```bash
   # Enable default configuration
   pipewire-network-client-config enable default

   # Enable office configuration
   pipewire-network-client-config enable office
   ```

3. **Alternative: Use systemd directly**:
   ```bash
   # Enable template service for specific config
   systemctl --user enable pipewire-network-client@office.service
   systemctl --user start pipewire-network-client@office.service
   ```

4. **Verify sinks are available**:
   ```bash
   pactl list sinks short
   ```

### Using Network Sinks

Once the client is connected, network sinks will appear in your audio settings:
- **GNOME**: Settings → Sound → Output Device
- **KDE**: System Settings → Audio → Playback Devices
- **Command line**: `pactl set-default-sink network_sink_main`

## Troubleshooting

### Common Issues

#### Server Issues

**Service fails to start:**
```bash
# Check if PipeWire is running
pactl info

# Check for port conflicts
sudo netstat -ulnp | grep :46998

# View detailed logs
journalctl --user -u pipewire-network-server.service -f
```

#### Client Issues

**Sinks not appearing:**
```bash
# Check module status
pactl list modules short | grep rtp
```

#### High Latency

If you have high latency problem, you probably need to set correctly your PipeWire configuration to use a lower quantum. Add a new file if it does not exist at `~/.config/pipewire/pipewire.conf.d/lowlatency.conf` with this content:

```conf
context.properties = {
    # Set sample rate
    default.clock.rate          = 48000

    # Set small quantum for low latency
    default.clock.quantum       = 128
    default.clock.min-quantum   = 64
    default.clock.max-quantum   = 256

    # Optional: allow realtime threads
    default.daemon.realtime     = true
    default.daemon.priority     = 89
}
```

Then restart pipewire: `systemctl --user restart pipewire pipewire-pulse wireplumber`.

Please, note that you might need to customize the values in the `lowlatency.conf` file accordingly to your system specification. A value of `128` for quantum might increase your CPU usage or might break audio (not the hardware) by introducing cracklings.

### Log Locations
- **Systemd logs**: `journalctl --user -u pipewire-network-{server,client}.service`

### Performance Tuning

#### Network Optimization
```json
// server.json - for high-quality audio
{
  "sample_spec": "s24le 96000 2",
  "channel_map": "front-left,front-right"
}
```

#### Latency Reduction
```json
// client.json - reduce retry interval for faster reconnection
{
  "retry_interval": 5,
  "streams": [...]
}
```

## Security Considerations

- Use a dedicated multicast group or unicast destination
- Consider VPN for internet connections
- Use firewalld to restrict which hosts can receive the UDP stream

## Development

### Building from Source

#### Prerequisites
```bash
# Fedora/RHEL/CentOS
sudo dnf install python3 python3-devel systemd-rpm-macros rpm-build pipewire pipewire-utils

# Debian/Ubuntu
sudo apt install python3 python3-dev debhelper dh-python dpkg-dev pipewire pipewire-pulse
```

### Testing

#### Manual Testing
```bash
# Start server manually
python3 src/pipewire-network-server

# Start client manually
python3 src/pipewire-network-client

# Test with custom config
CONFIG_DIR=/tmp/test-config python3 src/pipewire-network-server
```

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make changes and test thoroughly
4. Submit a pull request

## Changelog

### Version 2.0.0
- Ported the whole project to pipewire and renamed to `pipewire-network`
- Basic server and client functionality using PipeWire RTP transport

### Version 1.0.0
- Initial release
- Basic server and client functionality
- RPM and DEB packaging
- Systemd integration
- Configuration file support
- Health monitoring and auto-reconnection