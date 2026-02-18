Name:           pipewire-network-sender
Version:        2.0.0
Release:        1%{?dist}
Summary:        PipeWire network audio sender
License:        MIT
URL:            https://github.com/ferdiu/pipewire-network
Source0:        pipewire-network-sender-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  pkgconfig
BuildRequires:  pipewire-devel
BuildRequires:  json-c-devel
BuildRequires:  systemd-rpm-macros

Requires:       pipewire
Requires:       pipewire-utils
Requires:       json-c
Requires:       systemd
Requires:       jq

%description
PipeWire Network Sender creates local PipeWire null-sinks and streams
their audio to remote receivers via RTP/UDP. It reads named configurations
from JSON, supports multiple simultaneous streams, and automatically
restarts streams on failure.

Includes:
  pipewire-network-rtp-sender    — low-level RTP sender (one per stream)
  pipewire-network-sender        — supervisor process (reads config, spawns children)
  pipewire-network-sender-config — configuration management and systemd helper

%prep
%setup -q

%build
%make_build pipewire-network-sender pipewire-network-rtp-sender

%install
install -D -m 755 pipewire-network-sender \
    %{buildroot}%{_bindir}/pipewire-network-sender
install -D -m 755 pipewire-network-rtp-sender \
    %{buildroot}%{_bindir}/pipewire-network-rtp-sender
install -D -m 755 src/pipewire-network-sender-config \
    %{buildroot}%{_bindir}/pipewire-network-sender-config
install -D -m 644 systemd/pipewire-network-sender@.service \
    %{buildroot}%{_userunitdir}/pipewire-network-sender@.service
install -D -m 644 systemd/pipewire-network-sender.service \
    %{buildroot}%{_userunitdir}/pipewire-network-sender.service
install -D -m 644 config/sender.json \
    %{buildroot}%{_sysconfdir}/pipewire-network/sender.json
install -D -m 644 README.md %{buildroot}%{_docdir}/%{name}/README.md
install -D -m 644 LICENSE   %{buildroot}%{_docdir}/%{name}/LICENSE

%files
%{_bindir}/pipewire-network-sender
%{_bindir}/pipewire-network-rtp-sender
%{_bindir}/pipewire-network-sender-config
%{_userunitdir}/pipewire-network-sender@.service
%{_userunitdir}/pipewire-network-sender.service
%config(noreplace) %{_sysconfdir}/pipewire-network/sender.json
%doc %{_docdir}/%{name}/README.md
%license %{_docdir}/%{name}/LICENSE

%post
cat << 'EOF'
PipeWire Network Sender installed!

  # Create your configuration:
  pipewire-network-sender-config create-sample

  # Enable a named configuration:
  pipewire-network-sender-config enable default
EOF

%preun
if [ $1 -eq 0 ]; then
    systemctl --user stop    'pipewire-network-sender@*.service' >/dev/null 2>&1 || :
    systemctl --user stop    pipewire-network-sender.service     >/dev/null 2>&1 || :
    systemctl --user disable 'pipewire-network-sender@*.service' >/dev/null 2>&1 || :
    systemctl --user disable pipewire-network-sender.service     >/dev/null 2>&1 || :
fi

%changelog
* Tue Feb 17 2026 Federico Manzella <ferdiu.manzella@gmail.com> - 2.0.0-1
- Rewritten in C using libpipewire-0.3 native API
- JSON configuration via libjson-c
- Supervisor process with per-stream retry logic
- pipewire-network-sender-config shell tool for managing named configs
