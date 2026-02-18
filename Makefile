# Makefile for pipewire-network
#
# Produces three binaries:
#   pipewire-network-receiver      — RTP receiver (reads receiver.json)
#   pipewire-network-sender        — supervisor that spawns rtp-sender children
#   pipewire-network-rtp-sender    — low-level RTP sender (our rtp-sender.c)
#
# Dependencies: libpipewire-0.3, libspa-0.2 (for spa/utils/json.h), json-c
#   Fedora:  sudo dnf install pipewire-devel json-c-devel
#   Debian:  sudo apt install libpipewire-0.3-dev libspa-0.2-dev libjson-c-dev

CC      ?= gcc
CFLAGS  ?= -Wall -Wextra -O2 -g
CFLAGS  += $(shell pkg-config --cflags libpipewire-0.3 json-c)
LDFLAGS += $(shell pkg-config --libs   libpipewire-0.3 json-c)

PREFIX      ?= /usr/local
BINDIR      := $(PREFIX)/bin
SYSCONFDIR  ?= /etc
USERUNITDIR ?= /usr/lib/systemd/user
FWDDIR      ?= /usr/lib/firewalld/services

BINS := pipewire-network-receiver pipewire-network-sender pipewire-network-rtp-sender

.PHONY: all clean install uninstall

all: $(BINS)

pipewire-network-receiver: src/pipewire-network-receiver.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

pipewire-network-sender: src/pipewire-network-sender.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# rtp-sender.c lives in src/ and is our core low-level sender
pipewire-network-rtp-sender: src/rtp-sender.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(BINS)

install: all
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 pipewire-network-receiver      $(DESTDIR)$(BINDIR)/
	install -m 755 pipewire-network-sender         $(DESTDIR)$(BINDIR)/
	install -m 755 pipewire-network-rtp-sender     $(DESTDIR)$(BINDIR)/
	install -m 755 src/pipewire-network-sender-config $(DESTDIR)$(BINDIR)/

	install -d $(DESTDIR)$(USERUNITDIR)
	install -m 644 systemd/pipewire-network-receiver.service    $(DESTDIR)$(USERUNITDIR)/
	install -m 644 systemd/pipewire-network-sender.service      $(DESTDIR)$(USERUNITDIR)/
	install -m 644 systemd/pipewire-network-sender@.service     $(DESTDIR)$(USERUNITDIR)/

	install -d $(DESTDIR)$(SYSCONFDIR)/pipewire-network
	install -m 644 config/receiver.json $(DESTDIR)$(SYSCONFDIR)/pipewire-network/
	install -m 644 config/sender.json   $(DESTDIR)$(SYSCONFDIR)/pipewire-network/

	install -d $(DESTDIR)$(FWDDIR)
	install -m 644 firewalld/pipewire-network.xml $(DESTDIR)$(FWDDIR)/

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/pipewire-network-receiver
	rm -f $(DESTDIR)$(BINDIR)/pipewire-network-sender
	rm -f $(DESTDIR)$(BINDIR)/pipewire-network-rtp-sender
	rm -f $(DESTDIR)$(BINDIR)/pipewire-network-sender-config
	rm -f $(DESTDIR)$(USERUNITDIR)/pipewire-network-receiver.service
	rm -f $(DESTDIR)$(USERUNITDIR)/pipewire-network-sender.service
	rm -f $(DESTDIR)$(USERUNITDIR)/pipewire-network-sender@.service
	rm -f $(DESTDIR)$(FWDDIR)/pipewire-network.xml
