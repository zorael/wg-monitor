/**
    Wireguard peer monitor.

    Calls a Wireguard command to get the latest handshake timestamps of all peers.

    A notification is sent if a peer hasn't been seen for a while, occassionally
    as a reminder, and/or if a peer returns after having been lost.
    Notifications can be sent via [Batsign](https://batsign.me), or by invoking
    a custom command.

    See_Also:
        https://batsign.me

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor;
