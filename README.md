# Kernel-Based Proxy Server Deployment
This repository contains a proxy server configuration whose primary purpose is to efficiently
forward connections from a publicly hosted machine (such as a cheap VPS in the cloud) to clients
behind a firewall (such as on a home network). It hides the clients' real IP addresses, which are
often shared and dynamic, and makes them accessible through a configured set of TCP and UDP ports.

Traffic forwarding is based on *WireGuard* VPN and *Netfilter*. Therefore, all the work is done in
the kernel, and the proxying is correspondingly efficient.

The entire server configuration is declarative and configurable. A bootable ISO image for
installation can be generated with a single command. The configuration is not intended to be changed
manually once installed. Instead, this configuration source code should be changed and reapplied.

## Core Technology
The basis for this project is the [Pyromaniac][pyromaniac] framework along with the [Pyromaniac
Basics Library][lib]. They allow the desired server state to be declared in a modular, flexible, and
clear way, and provide common building blocks to speed up the process.

Since, in the end, *Pyromaniac* just produces configurations and images for [Fedora CoreOS][coreos],
you get a self-maintaining system with sensible security defaults and minimal maintenance
requirements.

# System Architecture
The configuration specifies everything required, from storage and networking to *SSHD* and VPN
setup. It is rather self-explanatory if you have a basic understanding of *CoreOS*'s [Butane
format][butane]. Simply start by reading the *main.pyro* file and follow the referenced modules in
the *modules* directory and the [Basics Library][lib].

In addition to the partition containing the root filesystem, an optional swap partition and a
persistent storage partition are automatically created on the boot disk during installation. You can
configure their sizes in the *config.toml* file, along with everything else.

No secrets are exposed through the configuration. Instead, the *SSHD* and *WireGuard* keys are
automatically generated on first boot and persisted on the persistent storage partition, where they
remain even across reprovisionings of the machine. You can find the *WireGuard* public key in the
*~/vpn-proxy/wireguard.pub* file after *SSH*ing into the installed server.

The server is expected to have a single IPv4 address and an entire subnet of IPv6 addresses. On the
IPv4 address, each port can be assigned to only a single client, and Network Address Translation is
performed to place all clients behind that address. For IPv6, every client is directly assigned an
individual globally routed IPv6 address from the corresponding subnet, and the server simply acts as
a router, delivering the traffic through the *WireGuard* interface.

[pyromaniac]: https://github.com/salatfreak/pyromaniac
[lib]: https://github.com/salatfreak/pyromaniac-lib
[coreos]: https://fedoraproject.org/coreos/
[butane]: https://coreos.github.io/butane/config-fcos-v1_7/

## Installation
To install the configuration on your own server, first copy the *config.toml.tmpl* file to
*config.toml* and adapt it to your needs. After [installing *Pyromaniac*][pyromaniac-install], you
can now generate an *Ignition* configuration by running `pyromaniac . > config.ign`, or even a
bootable installer image for installing the system, for example to */dev/vda*, by executing
`pyromaniac --iso-disk /dev/vda . > installer.iso`.

Now simply (virtually) insert the installer media into your fresh machine and boot from it. If
everything goes well, you should have a readily deployed proxy server after a couple of minutes.
Consult the [CoreOS documentation][coreos-install] for details on installing the system on bare
metal or a variety of cloud platforms.

[pyromaniac-install]: https://salatfreak.github.io/pyromaniac/installation.html
[coreos-install]: https://docs.fedoraproject.org/en-US/fedora-coreos/bare-metal/

## Adding Peers
Management of peers/clients is done through *JSON* files in */mnt/persist/vpn-config/peers*, which,
through a symlink in the *core* user's home directory, can also be referenced as
*~/vpn-config/peers*. You can either add these files manually to the persistent partition via an SSH
session or change this *Pyromaniac* configuration to add them declaratively.

Given a server listening on 100.0.0.42:6969 with local IP 10.0.0.1/24 on its *WireGuard* interface
and the global IPv6 subnet 2003:1337::/64 routed to it, a client's *WireGuard* configuration could
look as follows.

```ini
[Interface]
Address = 10.0.0.101/32, 2003:1337::4269/128
DNS = 9.9.9.9
PrivateKey = sF508795/cghbfWsLIMHZfOI5k6D66ZydQAynJVUEHw=

[Peer]
Endpoint = 100.0.0.42:6969
PublicKey = 9eTDtGUCS2MB4wm3JCs2apaUnnUuOoTVJDBB1WHhDlQ=
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

On the *WireGuard* server, a file ending in *.json* with contents like the following can then be
placed in *~/vpn-proxy/peers* and applied by running `systemctl reload vpn-config`.

```json
{
  "ipv4": "10.0.0.101",
  "ipv6": "2003:1337::4269",
  "key": "NiiuDDb5AlGUeqcg+XcjqW61u9cXAcgNKjxvNjx4Rn8=",
  "ports_v4": [80, 443],
  "ports_v6": [80, 443, "12345/udp"]
}
```

This would cause IPv4 traffic to the *WireGuard* server's public IPv4 address on ports 80/tcp and
443/tcp to be forwarded and masqueraded to 10.0.0.101 through the *WireGuard* interface. IPv6
traffic on ports 80/tcp, 443/tcp, and 12345/udp to the public IPv6 address 2003:1337::4269 would be
directly forwarded to the client through the *WireGuard* interface.
