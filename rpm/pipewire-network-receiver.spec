Name:           pipewire-network-receiver
Version:        2.0.0
Release:        1%{?dist}
Summary:        PipeWire network audio receiver
License:        MIT
URL:            https://github.com/ferdiu/pipewire-network
Source0:        pipewire-network-receiver-%{version}.tar.gz

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
Recommends:     firewalld

%description
PipeWire Network Receiver listens for incoming RTP audio streams and
automatically connects them to the system default output sink. It reads
its configuration from JSON and supports live sink-switching when the
default output changes.

%prep
%setup -q

%build
%make_build pipewire-network-receiver

%install
install -D -m 755 pipewire-network-receiver \
    %{buildroot}%{_bindir}/pipewire-network-receiver
install -D -m 644 systemd/pipewire-network-receiver.service \
    %{buildroot}%{_userunitdir}/pipewire-network-receiver.service
install -D -m 644 firewalld/pipewire-network.xml \
    %{buildroot}%{_prefix}/lib/firewalld/services/pipewire-network.xml
install -D -m 644 config/receiver.json \
    %{buildroot}%{_sysconfdir}/pipewire-network/receiver.json
install -D -m 644 README.md %{buildroot}%{_docdir}/%{name}/README.md
install -D -m 644 LICENSE   %{buildroot}%{_docdir}/%{name}/LICENSE

%files
%{_bindir}/pipewire-network-receiver
%{_userunitdir}/pipewire-network-receiver.service
%{_prefix}/lib/firewalld/services/pipewire-network.xml
%config(noreplace) %{_sysconfdir}/pipewire-network/receiver.json
%doc %{_docdir}/%{name}/README.md
%license %{_docdir}/%{name}/LICENSE

%post
if systemctl is-active --quiet firewalld; then
    firewall-cmd --reload >/dev/null 2>&1 || :
fi
cat << 'EOF'
PipeWire Network Receiver installed!

  systemctl --user enable --now pipewire-network-receiver.service

  # Open firewall port (as root):
  firewall-cmd --permanent --add-service=pipewire-network && firewall-cmd --reload

  # Edit config:
  ~/.config/pipewire-network/receiver.json
EOF

%preun
if [ $1 -eq 0 ]; then
    systemctl --user stop    pipewire-network-receiver.service >/dev/null 2>&1 || :
    systemctl --user disable pipewire-network-receiver.service >/dev/null 2>&1 || :
fi

%postun
if [ $1 -eq 0 ]; then
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --reload >/dev/null 2>&1 || :
    fi
fi

%changelog
* Tue Feb 17 2026 Federico Manzella <ferdiu.manzella@gmail.com> - 2.0.0-1
- Rewritten in C using libpipewire-0.3 native API
- JSON configuration via libjson-c
- Auto-connects to default sink with live sink-switching support
