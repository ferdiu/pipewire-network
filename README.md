# PipeWire Network Audio Streaming

A reliable solution for streaming audio over the network using PipeWire's RTP transport. This project provides both receiver and sender components with proper configuration management, automatic reconnection, and packaging for Fedora (RPM) and Debian/Ubuntu (DEB).

> This is a full-reimplementation of my old project [pulseaudio-network](https://github.com/ferdiu/pulseaudio-network) which used TCP sinks which could not guarantee the same low-latency as RTP sinks do.

## Features

### Receiver Features
- **Auto-Connect**: Automatically connects incoming RTP stream to the default output sink
- **Live Sink Switching**: Follows the default sink when it changes — old links torn down, new ones created
- **JSON Configuration**: Reads `~/.config/pipewire-network/receiver.json` with system-wide fallback
- **Firewall Integration**: Includes firewalld service definition
- **Graceful Shutdown**: Cleans up PipeWire links on SIGTERM/SIGINT

### Sender Features
- **Named Configurations**: Multiple named setups in a single JSON file
- **Multi-Stream**: Each named config can send to several receivers simultaneously
- **Auto-Reconnection**: Supervisor restarts failed streams with configurable retry logic
- **Unique Sink Names**: Each stream gets a unique null-sink so they appear separately in the mixer
- **Config Manager**: `pipewire-network-sender-config` tool for listing, validating, and enabling configs

## Project Structure

```
pipewire-network/
├── src/
│   ├── pipewire-network-receiver.c        # RTP receiver (C, libpipewire)
│   ├── pipewire-network-sender.c          # Supervisor process (C, libjson-c)
│   ├── rtp-sender.c                       # Low-level RTP sender (C, libpipewire)
│   └── pipewire-network-sender-config     # Config management shell script
├── systemd/
│   ├── pipewire-network-receiver.service  # Systemd user service for receiver
│   ├── pipewire-network-sender.service    # Systemd user service for sender (default config)
│   └── pipewire-network-sender@.service   # Systemd template for named configs
├── config/
│   ├── receiver.json                      # Default receiver configuration
│   └── sender.json                        # Default sender configuration
├── firewalld/
│   └── pipewire-network.xml              # Firewalld service definition
├── rpm/
│   ├── pipewire-network-receiver.spec
│   └── pipewire-network-sender.spec
├── debian/
│   ├── receiver/                          # Debian packaging for receiver
│   └── sender/                            # Debian packaging for sender
├── scripts/
│   ├── build-rpm.sh
│   ├── build-deb.sh
│   └── install.sh
├── Makefile
├── README.md
└── LICENSE
```

## Building

### Prerequisites

```bash
# Fedora/RHEL/CentOS
sudo dnf install gcc make pkgconfig pipewire-devel json-c-devel

# Debian/Ubuntu
sudo apt install gcc make pkg-config libpipewire-0.3-dev libspa-0.2-dev libjson-c-dev
```

### Build

```bash
make          # builds all three binaries
make clean    # remove built binaries
```

This produces:
- `pipewire-network-receiver` — the receiver daemon
- `pipewire-network-sender` — the supervisor process
- `pipewire-network-rtp-sender` — the low-level per-stream RTP sender

## Installation

### From Packages

#### Fedora/RHEL/CentOS (RPM)

```bash
./scripts/build-rpm.sh
sudo dnf install dist/pipewire-network-receiver-*.rpm
sudo dnf install dist/pipewire-network-sender-*.rpm
```

#### Debian/Ubuntu (DEB)

```bash
./scripts/build-deb.sh
sudo dpkg -i dist/pipewire-network-receiver_*.deb
sudo dpkg -i dist/pipewire-network-sender_*.deb
sudo apt-get install -f
```

### From Source

```bash
./scripts/install.sh          # both
./scripts/install.sh receiver
./scripts/install.sh sender
```

## Configuration

### Receiver (`~/.config/pipewire-network/receiver.json`)

```json
{
  "port": 9875,
  "address": "0.0.0.0",
  "target_latency": 5
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `port` | `9875` | UDP port to listen on |
| `address` | `"0.0.0.0"` | Interface address to bind |
| `target_latency` | `5` | Buffer latency in milliseconds |

### Sender (`~/.config/pipewire-network/sender.json`)

```json
{
  "default": {
    "streams": [
      { "address": "192.168.1.2", "port": 9875 }
    ],
    "auto_connect": true,
    "retry_interval": 10,
    "max_retries": -1
  },
  "living-room": {
    "streams": [
      { "address": "192.168.1.3", "port": 9875 }
    ],
    "auto_connect": true,
    "retry_interval": 10,
    "max_retries": 3
  }
}
```

Each top-level key is a named configuration. `max_retries: -1` means unlimited restarts.

**Stream fields:**
- `address`: Destination IP (unicast or multicast) — must match the receiver's network address
- `port`: UDP port — must match the receiver's configured port

## Usage

### Receiver Setup

```bash
# Open firewall port (if using firewalld)
sudo firewall-cmd --permanent --add-service=pipewire-network
sudo firewall-cmd --reload

# Enable and start
systemctl --user enable --now pipewire-network-receiver.service

# Check logs
journalctl --user -u pipewire-network-receiver.service -f
```

### Sender Setup

```bash
# Create sample configuration
pipewire-network-sender-config create-sample

# List available configs
pipewire-network-sender-config list

# Validate a config before enabling
pipewire-network-sender-config validate living-room

# Enable and start a named config
pipewire-network-sender-config enable living-room

# Or use systemd directly
systemctl --user enable --now pipewire-network-sender@living-room.service

# Check what's running
pipewire-network-sender-config status
```

Once running, network sinks appear in your audio settings. Each stream gets a sink named `<config-name>-<index>`:

```bash
pactl list sinks short
# → living-room-0   PipeWire  ...
pactl set-default-sink living-room-0
```

## Architecture

```
Receiver side                      Sender side
─────────────                      ───────────
pipewire-network-receiver          pipewire-network-sender <config-name>
  │                                  │  (supervisor: reads JSON, forks children)
  │  libpipewire-module-rtp-source   │
  │  ← UDP RTP stream ←              ├─ pipewire-network-rtp-sender <name>-0 <addr> <port>
  │                                  │    (null-sink + rtp-sink module)
  │  auto-links to default sink      │
  │  follows sink changes            └─ pipewire-network-rtp-sender <name>-1 <addr> <port>
  │                                       (null-sink + rtp-sink module)
  ↓
[speakers / headphones]
```

## Troubleshooting

### Receiver: audio not playing

```bash
# Is PipeWire running?
pactl info

# Is the port open?
ss -ulnp | grep 9875

# Check receiver logs
journalctl --user -u pipewire-network-receiver.service -f
```

### Sender: sinks not appearing

```bash
# Is the sender running?
pipewire-network-sender-config status

# Check sender logs
journalctl --user -u 'pipewire-network-sender@*.service' -f

# List PipeWire sinks
pactl list sinks short
```

### High Latency

Create `~/.config/pipewire/pipewire.conf.d/lowlatency.conf`:

```conf
context.properties = {
    default.clock.rate        = 48000
    default.clock.quantum     = 128
    default.clock.min-quantum = 64
    default.clock.max-quantum = 256
    default.daemon.realtime   = true
    default.daemon.priority   = 89
}
```

Then restart: `systemctl --user restart pipewire pipewire-pulse wireplumber`

> Note: a quantum of `128` may increase CPU usage or introduce crackling on slower systems. Tune to taste.

## Security Considerations

- Use unicast addresses or a dedicated multicast group
- Wrap in a VPN for internet links
- Use firewalld to restrict which source IPs can send to the receiver port

## License

MIT License — see [LICENSE](LICENSE) for details.

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make changes and test thoroughly
4. Submit a pull request

## Changelog

### Version 2.0.0
- **Rewritten in C** using libpipewire-0.3 native API (no Python dependency)
- Receiver auto-connects to default sink and follows live sink changes
- Sender supervisor with per-stream retry logic
- JSON configuration via libjson-c
- `pipewire-network-sender-config` shell tool for config management
- Makefile-based build (no meson/cmake)
- RPM and DEB packaging with proper C build steps

### Version 1.0.0
- Initial release (Python implementation)
- Basic receiver and sender functionality
- RPM and DEB packaging
