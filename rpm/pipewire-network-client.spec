Name:           pipewire-network-client
Version:        2.0.0
Release:        1%{?dist}
Summary:        PipeWire network audio client
License:        MIT
URL:            https://github.com/ferdiu/pipewire-network
Source0:        pipewire-network-client-%{version}.tar.gz
BuildArch:      noarch
BuildRequires:  python3-devel
BuildRequires:  systemd-rpm-macros
Requires:       python3
Requires:       pipewire-utils
Requires:       systemd

%description
PipeWire Network Client provides a reliable way to receive RTP audio streams
from a remote PipeWire server and create local sinks for network audio
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
install -m 755 src/pipewire-network-client %{buildroot}%{_bindir}/pipewire-network-client

# Install configuration manager script
install -m 755 src/pipewire-network-client-config %{buildroot}%{_bindir}/pipewire-network-client-config

# Install systemd user services (both template and default)
install -m 644 systemd/pipewire-network-client@.service %{buildroot}%{_userunitdir}/pipewire-network-client@.service
install -m 644 systemd/pipewire-network-client.service %{buildroot}%{_userunitdir}/pipewire-network-client.service

# Install default configuration
install -m 644 config/client.json %{buildroot}%{_sysconfdir}/pipewire-network/client.json

# Install documentation
install -m 644 README.md %{buildroot}%{_docdir}/%{name}/README.md
install -m 644 LICENSE %{buildroot}%{_docdir}/%{name}/LICENSE

%files
%{_bindir}/pipewire-network-client
%{_bindir}/pipewire-network-client-config
%{_userunitdir}/pipewire-network-client@.service
%{_userunitdir}/pipewire-network-client.service
%config(noreplace) %{_sysconfdir}/pipewire-network/client.json
%doc %{_docdir}/%{name}/README.md
%license %{_docdir}/%{name}/LICENSE

%post
# Inform user about manual steps
cat << EOF
PipeWire Network Client installed successfully!

To use this service:
1. Configure your stream settings:
   ~/.config/pipewire-network/client.json

2. Enable and start the user service:
   systemctl --user enable pipewire-network-client.service
   systemctl --user start pipewire-network-client.service

3. Check service status:
   systemctl --user status pipewire-network-client.service
EOF

%preun
if [ $1 -eq 0 ]; then
    # Stop and disable all services on package removal
    systemctl --user stop 'pipewire-network-client@*.service' >/dev/null 2>&1 || :
    systemctl --user stop pipewire-network-client.service >/dev/null 2>&1 || :
    systemctl --user disable 'pipewire-network-client@*.service' >/dev/null 2>&1 || :
    systemctl --user disable pipewire-network-client.service >/dev/null 2>&1 || :
fi

%changelog
* Mar Feb 17 2026 Federico Manzella <ferdiu.manzella@gmail.com> - 2.0.0-1
- Initial package release
- PipeWire network client with RTP transport
- Systemd user service integration
- Automatic reconnection and health monitoring
