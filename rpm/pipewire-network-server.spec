Name:           pipewire-network-server
Version:        2.0.0
Release:        1%{?dist}
Summary:        PipeWire network audio server
License:        MIT
URL:            https://github.com/ferdiu/pipewire-network
Source0:        pipewire-network-server-%{version}.tar.gz
BuildArch:      noarch
BuildRequires:  python3-devel
BuildRequires:  systemd-rpm-macros
Requires:       python3
Requires:       pipewire-utils
Requires:       systemd
Requires:       firewalld

%description
PipeWire Network Server provides a reliable way to share audio from a
PipeWire-enabled system over the network using RTP transport. It includes
automatic configuration management, health monitoring, and graceful error
handling.

%prep
%setup -q

%build
# Nothing to build for Python scripts

%install
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_userunitdir}
mkdir -p %{buildroot}%{_sysconfdir}/pipewire-network
mkdir -p %{buildroot}%{_prefix}/lib/firewalld/services
mkdir -p %{buildroot}%{_docdir}/%{name}

# Install the Python script
install -m 755 src/pipewire-network-server %{buildroot}%{_bindir}/pipewire-network-server

# Install systemd user service
install -m 644 systemd/pipewire-network-server.service %{buildroot}%{_userunitdir}/pipewire-network-server.service

# Install firewalld service definition
install -m 644 firewalld/pipewire-network.xml %{buildroot}%{_prefix}/lib/firewalld/services/pipewire-network.xml

# Install default configuration
install -m 644 config/server.json %{buildroot}%{_sysconfdir}/pipewire-network/server.json

# Install documentation
install -m 644 README.md %{buildroot}%{_docdir}/%{name}/README.md
install -m 644 LICENSE %{buildroot}%{_docdir}/%{name}/LICENSE

%files
%{_bindir}/pipewire-network-server
%{_userunitdir}/pipewire-network-server.service
%{_prefix}/lib/firewalld/services/pipewire-network.xml
%config(noreplace) %{_sysconfdir}/pipewire-network/server.json
%doc %{_docdir}/%{name}/README.md
%license %{_docdir}/%{name}/LICENSE

%post
# Reload firewalld to pick up new service definition
if systemctl is-active --quiet firewalld; then
    firewall-cmd --reload >/dev/null 2>&1 || :
fi

# Inform user about manual steps
cat << EOF
PipeWire Network Server installed successfully!

To use this service:
1. Enable and start the user service:
   systemctl --user enable pipewire-network-server.service
   systemctl --user start pipewire-network-server.service

2. Configure firewall (as root):
   firewall-cmd --permanent --add-service=pipewire-network
   firewall-cmd --reload

3. Edit configuration if needed:
   ~/.config/pipewire-network/server.json
EOF

%preun
if [ $1 -eq 0 ]; then
    # Stop and disable the service on package removal
    systemctl --user stop pipewire-network-server.service >/dev/null 2>&1 || :
    systemctl --user disable pipewire-network-server.service >/dev/null 2>&1 || :
fi

%postun
if [ $1 -eq 0 ]; then
    # Reload firewalld on package removal
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --reload >/dev/null 2>&1 || :
    fi
fi

%changelog
* Mar Feb 17 2026 Federico Manzella <ferdiu.manzella@gmail.com> - 2.0.0-1
- Initial package release
- PipeWire network server with RTP transport
- Systemd user service integration
- Firewalld service definition
