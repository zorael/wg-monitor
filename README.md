# wg-monitor

Monitors other peers in a [Wireguard VPN](https://www.wireguard.com) and sends a notification if contact with a peer is lost.

The main purpose of this is to monitor Internet-connected locations for power outages, using Wireguard handshakes as a way for locations to phone home. Each location needs an always-on, always-connected computer to act as a Wireguard peer, for which something like a [Raspberry Pi Zero 2W](https://www.raspberrypi.com/products/raspberry-pi-zero-2-w) is more than sufficient.

In a hub-and-spoke Wireguard configuration, this should be run on the hub server, ideally with an additional instance on one (or more) of the other peers to monitor the hub. In other configurations, it can be run on any peer with visibility of other peers, but a secondary instance monitoring the first is recommended in any setup.

Peers should have a `PersistentKeepalive` setting in their Wireguard configuration set lower than the peer timeout in this program. This is **10 minutes** by default, but can be overridden via a command-line switch.

Notifications are send as short emails via [Batsign](https://batsign.me), or by invocation of a specified command.

**This program is Posix-only until such time a console `wg` tool exists for Windows.**

## tl;dr

```
-i           --interface  Wireguard interface name
-p               --peers  Peer list file
-b             --batsign  Batsign URL file
-c             --command  Custom command to use to send notifications
-t             --timeout  Peer timeout in seconds
-s               --sleep  Sleep between peer checks in seconds
-r              --report  How long to wait before repeating a notification
    --wait-for-interface  Wait for the Wireguard interface to show up
-P            --progress  Print progress messages
-l            --language  Notification language, default english
               --dry-run  Don't send notifications

Available languages: english, swedish, japanese, english-minimal
```

A `peers.list` and a `batsign.url` file will be created on first run.

The peer file should contain a list of public keys of Wireguard peers, one per line. These can be obtained from the output of `wg show`.

```shell
$ sudo wg show [interface] peers
```

### Batsign

The `batsign.url` file should contain one or more [Batsign](https://batsign.me) URLs. Batsign is a free service with which you can send brief emails to yourself by issuing a simple HTTP request. See [the homepage](https://batsign.me) for more information on how to sign up.

### Notification commands

A custom command can be specified to be run instead of sending a Batsign when a peer is lost. Note however that the command will be run from within the `wg-monitor` process, and as such by the same user it was started as. This will in all likelihood be `root`, since the program calls itself with `sudo` if it is missing permissions to access the Wireguard interface. This imposes some limitations on what the command can do.

Batsign URLs are not necessary if a custom command is used for notifications.

## systemd service

The program is preferably run as a systemd service, to have it be automatically started upon restoration of power. To facilitate this, a basic systemd service file is included in the repository. It will have to be copied to `/etc/systemd/system/` and modified so the `ExecStart` and `WorkingDirectory` lines points to the correct location of the `wg-monitor` binary.

```shell
$ sudo systemctl enable --now wg-monitor@[interface]
```

It is meant to play well with `wg-quick@.service`. If other methods of setting up a Wireguard network are used, the service file may have to be modified accordingly.

## roadmap

* configuration file

## built with

* [**D**](https://dlang.org)
* [`dub`](https://code.dlang.org)

## license

This project is licensed under the **Boost Software License 1.0** - see the [LICENSE](LICENSE) file for details.
