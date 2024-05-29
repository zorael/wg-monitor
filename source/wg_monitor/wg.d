/**
    Wrappers around the `wg` command to get Wireguard handshake data.

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor.wg;

private:

import wg_monitor.peer : Peer;

public:


// runWGCommand
/**
    Executes a Wireguard `wg` command and returns the raw output.

    If there were errors, a relevant exception is thrown.

    Params:
        iface = The string name of the Wireguard interface.
        command = The command to execute.

    Returns:
        The `chomp`ed output of the Wireguard command.

    Throws:
        [wg_monitor.common.NeedSudoException] if `sudo` permissions are needed to execute the command.
        [wg_monitor.common.NoSuchInterfaceException] if the specified interface doesn't exist.
        [wg_monitor.common.NetworkException] on other network errors.
        [wg_monitor.common.CommandNotFoundException] if the `wg` command wasn't found.
        [object.Exception|Exception] on other more generic errors.
 */
private auto runWGCommand(const string iface, const string command)
{
    import wg_monitor.common : NeedSudoException, NetworkException, NoSuchInterfaceException;
    import std.process : ProcessException, environment, execute;
    import std.string : chomp;

    const string[4] wgCommand =
    [
        environment.get("WG", "/usr/bin/wg"),
        "show",
        iface,
        command,
    ];

    try
    {
        const result = execute(wgCommand[]);
        const output = result.output.chomp();

        if (result.status == 0) return output;

        enum sudoError = "Unable to access interface: Operation not permitted";
        enum ifaceError = "Unable to access interface: No such device";
        enum afError = "Unable to access interface: Address family not supported by protocol";

        switch (output)
        {
        case sudoError:
            throw new NeedSudoException(output, wgCommand[]);

        case ifaceError:
            throw new NoSuchInterfaceException(output, iface);

        case afError:
            throw new NetworkException(output);

        default:
            throw new Exception(output);
        }
    }
    catch (ProcessException e)
    {
        import wg_monitor.common : CommandNotFoundException;
        import std.algorithm.searching : startsWith;

        enum commandNotFoundHead = "Executable file not found:";
        throw e.msg.startsWith(commandNotFoundHead) ?
            new CommandNotFoundException(e.msg, wgCommand[]) :
            e;
    }

    // Let other Exceptions pass
}


// getOwnPublicKey
/**
    Executes a Wireguard `public-key` command and returns the raw output.

    If there were errors, a relevant exception is thrown.

    Params:
        iface = The string name of the Wireguard interface.

    Returns:
        A public key string.
 */
auto getOwnPublicKey(const string iface)
{
    return runWGCommand(iface, "public-key");
}


// getRawHandshakeString
/**
    Executes a Wireguard `latest-handshakes` command and returns the raw output.

    If there were errors, a relevant exception is thrown.

    Params:
        iface = The string name of the Wireguard interface.

    Returns:
        A list of handshake strings.
 */
auto getRawHandshakeString(const string iface)
{
    return runWGCommand(iface, "latest-handshakes");
}


// getHandshakes
/**
    Executes a Wireguard `latest-handshakes` command and parses the output.

    Creates [Peer]s that represent the peers in the output, and stores them in
    the `peers` associative array, passed by ref.

    Params:
        peers = A reference to the associative array of [Peer]s.
        iface = The string name of the Wireguard interface.

    Throws:
        Whatever [getRawHandshakeString] throws.
 */
void getHandshakes(ref Peer[string] peers, const string iface)
{
    import wg_monitor.common : NoSuchInterfaceException;
    import std.algorithm.iteration : splitter;

    const rawHandshakes = getRawHandshakeString(iface);
    auto handshakes = rawHandshakes.splitter('\n');

    foreach (const line; handshakes)
    {
        import std.conv : to;
        import std.datetime.systime : SysTime;
        import std.string : indexOf;

        const tabPos = line.indexOf('\t');
        if (tabPos == -1) continue;  // why?

        const hash = line[0..tabPos];
        auto peer = hash in peers;

        if (!peer)
        {
            peers[hash] = Peer(hash);
            peer = hash in peers;
        }

        const timeString = line[tabPos+1..$];
        if (timeString.length == 0) continue;  // when?

        if (timeString[0] == '0')
        {
            // Unset timestamp.
            peer.wasNeverSeen = true;
            continue;
        }
        else
        {
            peer.wasNeverSeen = false;
            peer.timestamp = SysTime.fromUnixTime(timeString.to!long);
        }
    }
}
