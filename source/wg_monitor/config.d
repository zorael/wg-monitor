/**
    Configuration and argument parsing bits.

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor.config;

private:

import wg_monitor.context : Context;

public:


// handleGetopt
/**
    Calls [std.getopt.getopt|getopt], parses the passed arguments and returns
    the results.

    The timeouts are separately parsed into [core.time.Duration|Duration]s.

    Params:
        args = Command line arguments passed to the program.
        context = out-reference to a [Context] struct.

    Returns:
        The results of [std.getopt.getopt|getopt].
 */
auto handleGetopt(string[] args, out Context context)
{
    import core.time : seconds;
    static import std.getopt;

    int peerTimeout = -1;
    int sleepBetweenChecks = -1;
    int reminderPeriodicity = -1;

    auto result = std.getopt.getopt(args,
        std.getopt.config.caseSensitive,
        //std.getopt.config.required,
        "i|interface",
            "Wireguard interface name",
            &context.iface,
        "p|peers",
            "Peer list file",
            &context.peerFile,
        "b|batsign",
            "Batsign URL file",
            &context.batsignFile,
        "c|command",
            "Notification command",
            &context.command,
        "both",
            string.init,  //"Use both notification methods (Batsign and command)",
            &context.bothNotificationMethods,
        "cacert",
            string.init, //"Certificate authority bundle file",
            &context.caBundleFile,
        "t|timeout",
            "Peer handshake timeout in seconds",
            &peerTimeout,
        "s|sleep",
            "Sleep between peer handshake checks in seconds",
            &sleepBetweenChecks,
        "r|reminder",
            "Notification reminder period in seconds",
            &reminderPeriodicity,
        "wait-for-interface",
            "Wait for the Wireguard interface to show up",
            &context.waitForInterface,
        "P|progress",
            "Print progress messages",
            &context.progress,
        "l|language",
            "Notification language, default " ~ context.language,
            &context.language,
        "reexec",
            string.init,
            &context.reexecuted,
        "dry-run",
            "Don't send notifications",
            &context.dryRun,
        "version",
            string.init,
            &context.showVersionAndExit);

    if (peerTimeout >= 0) context.durations.peerTimeout = peerTimeout.seconds;
    if (sleepBetweenChecks > 0) context.durations.sleepBetweenChecks = sleepBetweenChecks.seconds;
    if (reminderPeriodicity >= 0) context.durations.reminderPeriodicity = reminderPeriodicity.seconds;

    return result;
}


// parsePeerFile
/**
    Parses the peer list file and returns a Voldemort containing a `bool[string]`
    representing the peers listed inside; random bools keyed by peer hashes.

    Params:
        peerFile = Path to the peer list file.

    Returns:
        A Voldemort `Result` struct.
 */
auto parsePeerFile(const string peerFile)
{
    import std.algorithm.iteration : splitter;
    import std.file : readText;
    import std.string : chomp;

    static struct PeerFileHashes
    {
        bool[string] valid;
        string[] invalid;
    }

    PeerFileHashes result;
    auto peerLineRange = peerFile
        .readText()  // TOCTTOU
        .chomp()
        .splitter('\n');

    foreach (const hashRaw; peerLineRange)
    {
        import lu.string : stripped;

        const hash = hashRaw.stripped;

        if (!hash.length || (hash[0] == '#')) continue;
        else if ((hash.length != 44) || (hash[43] != '='))
        {
            result.invalid ~= hash;
            continue;
        }

        result.valid[hash] = true;
    }

    return result;
}


// parseBatsignFile
/**
    Reads the Batsign file, parses the URLs therein, and returns them as a `string[]`.

    Params:
        batsignFile = Path to the Batsign file.

    Returns:
        A `string[]` of Batsign URLs.

    See_Also:
        https://batsign.me
 */
auto parseBatsignFile(const string batsignFile)
{
    import lu.string : stripped;
    import std.algorithm.iteration : filter, map, splitter;
    import std.array : array;
    import std.file : readText;
    import std.string : chomp;

    return batsignFile
        .readText()
        .chomp()
        .splitter('\n')
        .map!(line => line.stripped)
        .filter!(a => a.length && (a[0] != '#'))
        .array;
}


// resolvePeerFileName
/**
    Resolves the peer list filename.

    The order of precedence is:

    1. The peer list file in the current working directory.
    2. The peer list file in `/etc/wg-monitor/` for the current Wireguard interface.
    3. The global peer list file in `/etc/wg-monitor/`.

    Params:
        context = The [Context] struct.

    Returns:
        `true` if the peer list file was found; `false` otherwise.
 */
auto resolvePeerFileName(ref Context context)
{
    import std.conv : text;
    import std.file : exists;
    import std.path : extension;

    if (context.peerFile.exists) return true;

    enum globalEtcPeerFile = "/etc/wg-monitor/" ~ Context.init.peerFile;
    const etcPeerFile = text(
        "/etc/wg-monitor/",
        context.iface,
        Context.init.peerFile.extension);  // ".list"
    const pwdPeerFile = text(
        context.iface,
        Context.init.peerFile.extension);  // as above

    if (pwdPeerFile.exists)
    {
        context.peerFile = pwdPeerFile;
        return true;
    }
    else if (etcPeerFile.exists)
    {
        context.peerFile = etcPeerFile;
        return true;
    }
    else if (globalEtcPeerFile.exists)
    {
        context.peerFile = globalEtcPeerFile;
        return true;
    }
    else
    {
        return false;
    }
}


// resolveBatsignFileName
/**
    Resolves the Batsign filename.

    The order of precedence is:

    1. The Batsign file in the current working directory.
    2. The Batsign file in `/etc/wg-monitor/` for the current Wireguard interface.
    3. The global Batsign file in `/etc/wg-monitor/`.

    Params:
        context = The [Context] struct.

    Returns:
        `true` if the Batsign file was found; `false` otherwise.
 */
auto resolveBatsignFileName(ref Context context)
{
    import std.conv : text;
    import std.file : exists;
    import std.path : extension;

    if (context.batsignFile.exists) return true;

    enum globalEtcBatsignFile = "/etc/wg-monitor/" ~ Context.init.batsignFile;
    const etcBatsignFile = text(
        "/etc/wg-monitor/",
        context.iface,
        Context.init.batsignFile.extension);  // ".url"
    const pwdBatsignFile = text(
        context.iface,
        Context.init.batsignFile.extension);  // as above

    if (pwdBatsignFile.exists)
    {
        context.batsignFile = pwdBatsignFile;
        return true;
    }
    else if (etcBatsignFile.exists)
    {
        context.batsignFile = etcBatsignFile;
        return true;
    }
    else if (globalEtcBatsignFile.exists)
    {
        context.batsignFile = globalEtcBatsignFile;
        return true;
    }
    else
    {
        return false;
    }
}


// resolveFilename
/**
    Resolves the filename of a configuration file.

    The order of precedence is:

    1. The file in the current working directory.
    2. The file in `/etc/wg-monitor/` for the current Wireguard interface.
    3. The global file in `/etc/wg-monitor/`.

    Params:
        filename = Reference to the filename to resolve.
        iface = The Wireguard interface name.
        baseFilename = The base filename to resolve.

    Returns:
        `true` if the file was found; `false` otherwise.
 */
auto resolveFilename(
    ref string filename,
    const string iface,
    const string baseFilename)
{
    import std.conv : text;
    import std.file : exists;
    import std.path : extension;

    if (filename.exists) return true;

    const filenameExtension = baseFilename.extension;

    const globalEtcFile = text(
        "/etc/wg-monitor/",
        baseFilename);

    const etcFile = text(
        "/etc/wg-monitor/",
        iface,
        filenameExtension);

    const pwdFile = text(
        iface,
        filenameExtension);

    if (pwdFile.exists)
    {
        filename = pwdFile;
        return true;
    }
    else if (etcFile.exists)
    {
        filename = etcFile;
        return true;
    }
    else if (globalEtcFile.exists)
    {
        filename = globalEtcFile;
        return true;
    }
    else
    {
        return false;
    }
}
