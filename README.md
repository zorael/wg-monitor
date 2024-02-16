# wg-monitor

Monitors other peers in a [Wireguard VPN](https://www.wireguard.com) and sends a notification if contact with a peer is lost.

The main purpose of this is to monitor Internet-connected locations for power outages, using Wireguard handshakes as a way for locations to phone home. Each location needs an always-on, always-connected computer to act as a Wireguard peer, for which something like a [Raspberry Pi Zero 2W](https://www.raspberrypi.com/products/raspberry-pi-zero-2-w) is cheap and more than sufficient.

In a hub-and-spoke Wireguard configuration, this should be run on the hub server, ideally with an additional instance on (at least) one other geographically disconnected peer to monitor the hub. In other configurations, it can be run on any peer with visibility of other peers, but a secondary instance monitoring the first is recommended in any setup.

Peers must have a `PersistentKeepalive` setting in their Wireguard configuration with a value *lower* than the peer timeout of this program. This is **600 seconds** by default, but can be overridden via a command-line switch.

Notifications are sent as short emails via [**Batsign**](https://batsign.me), or by invocation of a specified command.

**This program is Posix-only until such time a console `wg` tool exists for Windows.**

## tl;dr

```
-i           --interface  Wireguard interface name
-p               --peers  Peer list file
-b             --batsign  Batsign URL file
-c             --command  Custom command to use to send notifications
-t             --timeout  Peer timeout in seconds
    --wait-for-interface  Wait for the Wireguard interface to show up
-l            --language  Notification language, default english

Available languages: english, swedish, japanese, english-minimal
```

A `peers.list` and a `batsign.url` file will be created on first run.

The peer file should contain a list of public keys of Wireguard peers, one per line. These can be obtained from the output of `wg show`.

```shell
$ sudo wg show [interface] peers
```

### Batsign

The `batsign.url` file should contain one or more [Batsign](https://batsign.me) URLs. Batsign is a free service with which you can send brief emails to yourself by issuing simple HTTP requests. See [the homepage](https://batsign.me) for more information. (Requires registration.)

### Notification commands

A custom command can be specified to be run instead of sending a batsign when a peer is lost. Note however that the command will be invoked by the `wg-monitor` process, and as such by the same user it was started as. This will in all likelihood be **root**, since the program calls itself with `sudo` if it is missing permissions to access the Wireguard interface. This imposes some limitations on what kind of commands can be used.

> Batsign URLs are not necessary if a custom command is used for notifications.

## systemd service

The program is preferably run as a systemd service, to have it be automatically restarted upon restoration of power. To facilitate this, a systemd service unit file is provided in the repository. It will have to be copied into `/etc/systemd/system`, after which you can use `systemctl edit` to create a drop-in file for the service that overrides the `ExecStart` and `WorkingDirectory` lines to point to the correct location of the `wg-monitor` binary.

```shell
$ sudo cp wg-monitor@.service /etc/systemd/system
$ sudo systemctl edit wg-monitor@.service
```

```ini
### Editing /etc/systemd/system/wg-monitor@.service.d/override.conf
### Anything between here and the comment below will become the contents of the drop-in file

[Service]
ExecStart=
ExecStart=/main/src/wg-monitor/wg-monitor --interface=%i --progress=false --wait-for-interface --language=swedish
WorkingDirectory=/main/src/wg-monitor

### Edits below this comment will be discarded
# [...]
```

```shell
$ sudo systemctl enable --now wg-monitor@[interface]
```

It is meant to work well with `wg-quick@.service`. If other methods of setting up the Wireguard network are used, the service file may have to be modified accordingly, or skipped altogether.

## roadmap

* configuration file?

## built with

* [**D**](https://dlang.org)

## license

This project is licensed under the **Boost Software License 1.0**; see the [`LICENSE`](LICENSE) file for details.
