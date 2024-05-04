# wg-monitor

Monitors other peers in a [Wireguard VPN](https://www.wireguard.com) and sends a notification if contact with a peer is lost.

The main purpose of this is to monitor Internet-connected locations for power outages, using Wireguard handshakes as a way for sites to phone home. Each needs an always-on, always-connected computer to act as a Wireguard peer, for which something like a [Raspberry Pi Zero 2W](https://www.raspberrypi.com/products/raspberry-pi-zero-2-w) is cheap and more than sufficient. ([example hardware setup](https://github.com/zorael/wg-monitor/wiki/Example-hardware-setup))

In a hub-and-spoke Wireguard configuration, this should be run on the hub server, ideally with an additional instance on (at least) one other geographically disconnected peer to monitor the hub. In other configurations, it can be run on any peer with visibility of other peers, but a secondary instance monitoring the first is recommended in any setup.

Peers must have a `PersistentKeepalive` setting in their Wireguard configuration with a value *comfortably lower* than the peer timeout of this program. This timeout is **600 seconds** by default, but can be overridden via a command-line switch.

Notifications are sent as short emails via [**Batsign**](#batsign), or by invocation of an external command.

Peers are referred to in notifications by [a representation](https://github.com/zorael/wg-monitor/wiki/Humanly%E2%80%90readable-peers) of their public keys. Use of a vanity key generator is recommended to make these more easily recognisable. [Here](https://github.com/axllent/wireguard-vanity-keygen) is one, [here](https://github.com/warner/wireguard-vanity-address) is another.

**This program is Posix-only until such time a console `wg` tool exists for Windows.**

## tl;dr

You require a [**D**](https://dlang.org) compiler. The program supports being built with compilers of all three vendors; the reference compiler [**dmd**](https://dlang.org/download.html), the LLVM-based [**ldc**](https://github.com/ldc-developers/ldc#installation), and the GCC-based [**gdc**](https://gdcproject.org). The first is very fast to compile and is always the most recent in terms of compiler development, but the latter two are also available from most package repositories, produce faster code, and have the additional advantage of being able to compile for non-x86 architectures (e.g. ARM). Generally **ldc** is the go-to choice there. Some version restrictions apply; notably for **gdc** your require at least release series **12**.

If no compilers are available from your normal software sources, you can install one using the official [`install.sh`](https://dlang.org/install.html) script. (**gdc** is not available via this method.)

The [**dub**](https://dub.pm/cli-reference/dub) package manager is used to facilitate compilation and dependency management. It is included with the compiler if installed via the script, and is otherwise commonly available as a separate package in most repositories.

```shell
$ dub build
```

## usage

```
wireguard monitor x.y.z | copyright 2024 jr
$ git clone https://github.com/zorael/wg-monitor.git

-i           --interface  Wireguard interface name
-p               --peers  Peer list file
-b             --batsign  Batsign URL file
-c             --command  Notification command
-t             --timeout  Peer handshake timeout in seconds
    --wait-for-interface  Wait for the Wireguard interface to show up
-l            --language  Notification language, default english

Available languages: english, swedish, japanese, english-minimal
```

A `peers.list` and a `batsign.url` file will be created on the first run.

### peers

The peer file should contain a list of public keys of Wireguard peers, one per line. These can be obtained from the output of `wg show`.

```shell
$ sudo wg show [interface] peers > peers.list
```

### batsign

The `batsign.url` file should contain one or more [**Batsign**](https://batsign.me) URLs. Batsign is a free (gratis) service with which you can send brief emails to yourself by issuing simple HTTP requests. Requires registration.

### notification commands

An external command can be supplied to be run instead of sending a batsign when a peer is lost. It will be invoked with the body of the notification as its first argument, the number of iterations the main loop has run (starting from 0) as its second, and then four strings of space-separated peer hashes as arguments 3-6.

In order;

1. notification body
2. main loop iteration number (integer)
3. peers just lost
4. peers just returned
5. peers still lost (reminder notification)
6. peers present

Note that the command will be called by the `wg-monitor` process, and as such by the same user that was started as. This will in all likelihood be **root**, since the program calls itself with `sudo` if it is missing permissions to access the Wireguard interface. This imposes some limitations on what kind of commands can be used without environment variable gymnastics.

To help with this, an [`as-gui-user.sh`](as-gui-user.sh) helper shell script is included in the repository, which can be used to run a command on all currently-running graphical environment displays. This makes it possible to send desktop notifications, and an additional [`notify-send.sh`](notify-send.sh) script is included that does just that, using the command-line `notify-send` tool. Other methods of notification that can be similarly triggered by running a command can probably trivially be added as separate scripts leveraging `as-gui-user.sh` the same way.

Batsign URLs are not necessary if a command is used for notifications.

### systemd

The program is preferably run as a **systemd** service, to have it be automatically restarted upon restoration of power. To facilitate this, a service unit file is provided in the repository. It will have to be copied (or symlinked) into `/etc/systemd/system`, after which you can use `systemctl edit` to create a drop-in file for the service that overrides the `ExecStart` directive to point to the actual location of the `wg-monitor` binary. (The default path is `/usr/local/bin/wg-monitor`.)

```shell
$ sudo cp wg-monitor@.service /etc/systemd/system
$ sudo systemctl edit wg-monitor@.service
```

```ini
### Editing /etc/systemd/system/wg-monitor@.service.d/override.conf
### Anything between here and the comment below will become the contents of the drop-in file

[Service]
ExecStart=
ExecStart=/home/user/src/wg-monitor/wg-monitor --interface=%i --progress=false --wait-for-interface --language=swedish
WorkingDirectory=/home/user/src/wg-monitor

### Edits below this comment will be discarded
# [...]
```

An empty `ExecStart=` must be used to clear the value set in the original file, as `Exec` directives are additive.

The program will look for `peers.list` and `batsign.url` files in `/etc/wg-monitor` if a `WorkingDirectory` is not supplied. Please run the program manually once first to create these files, then populate them with the necessary data and optionally move them to a more suitable location (such as `/etc/wg-monitor`) before attempting to start the service.

If no `WorkingDirectory` is declared, external notification commands that make use of `as-gui-user.sh` (such as `notify-send.sh`) must be modified to refer to it by its full path.

```shell
$ sudo systemctl enable --now wg-monitor@[interface]
```

It is meant to work well with `wg-quick@.service`. If a different method of setting up the Wireguard network is used, the service file may have to be modified accordingly, or skipped altogether in favour of other solutions.

## roadmap

* nothing planned. fairly feature-complete. ideas welcome.

## license

This project is licensed under the **Boost Software License 1.0**; see the [`LICENSE`](LICENSE) file for details.
