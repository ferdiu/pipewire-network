Name:           pipewire-network-sender
Version:        2.0.0
Release:        1%{?dist}
Summary:        PipeWire network audio sender
License:        MIT
URL:            https://github.com/ferdiu/pipewire-network
Source0:        pipewire-network-sender-%{version}.tar.gz
BuildArch:      noarch
BuildRequires:  python3-devel
BuildRequires:  systemd-rpm-macros
Requires:       python3
Requires:       pipewire-utils
Requires:       systemd

%description
PipeWire Network Sender provides a reliable way to receive RTP audio streams
from a remote PipeWire receiver and create local sinks for network audio
playback. It includes automatic reconnection, configuration management, and
health monitoring.

%prep
%setup -q

%build
# Nothing to build for Python scripts

%install
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_userunitdir}
mkdir -p %{buildroot}%{_sysconfdir}/pipewire-network
mkdir -p %{buildroot}%{_docdir}/%{name}

# Install the Python script
install -m 755 src/pipewire-network-sender %{buildroot}%{_bindir}/pipewire-network-sender

# Install configuration manager script
install -m 755 src/pipewire-network-sender-config %{buildroot}%{_bindir}/pipewire-network-sender-config

# Install systemd user services (both template and default)
install -m 644 systemd/pipewire-network-sender@.service %{buildroot}%{_userunitdir}/pipewire-network-sender@.service
install -m 644 systemd/pipewire-network-sender.service %{buildroot}%{_userunitdir}/pipewire-network-sender.service

# Install default configuration
install -m 644 config/sender.json %{buildroot}%{_sysconfdir}/pipewire-network/sender.json

# Install documentation
install -m 644 README.md %{buildroot}%{_docdir}/%{name}/README.md
install -m 644 LICENSE %{buildroot}%{_docdir}/%{name}/LICENSE

%files
%{_bindir}/pipewire-network-sender
%{_bindir}/pipewire-network-sender-config
%{_userunitdir}/pipewire-network-sender@.service
%{_userunitdir}/pipewire-network-sender.service
%config(noreplace) %{_sysconfdir}/pipewire-network/sender.json
%doc %{_docdir}/%{name}/README.md
%license %{_docdir}/%{name}/LICENSE

%post
# Inform user about manual steps
cat << EOF
PipeWire Network Sender installed successfully!

To use this service:
1. Configure your stream settings:
   ~/.config/pipewire-network/sender.json

2. Enable and start the user service:
   systemctl --user enable pipewire-network-sender.service
   systemctl --user start pipewire-network-sender.service

3. Check service status:
   systemctl --user status pipewire-network-sender.service
EOF

%preun
if [ $1 -eq 0 ]; then
    # Stop and disable all services on package removal
    systemctl --user stop 'pipewire-network-sender@*.service' >/dev/null 2>&1 || :
    systemctl --user stop pipewire-network-sender.service >/dev/null 2>&1 || :
    systemctl --user disable 'pipewire-network-sender@*.service' >/dev/null 2>&1 || :
    systemctl --user disable pipewire-network-sender.service >/dev/null 2>&1 || :
fi

%changelog
* Mar Feb 17 2026 Federico Manzella <ferdiu.manzella@gmail.com> - 2.0.0-1
- Initial package release
- PipeWire network sender with RTP transport
- Systemd user service integration
- Automatic reconnection and health monitoring
