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
    int reportPeriodicity = -1;

    auto result = std.getopt.getopt(args,
        std.getopt.config.caseSensitive,
        std.getopt.config.required,
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
            "Custom command to use to send notifications",
            &context.command,
        "cacert",
            string.init, //"Certificate authority bundle file",
            &context.caBundleFile,
        "t|timeout",
            "Peer timeout in seconds",
            &peerTimeout,
        "s|sleep",
            "Sleep between peer checks in seconds",
            &sleepBetweenChecks,
        "r|report",
            "How long to wait before repeating a notification",
            &reportPeriodicity,
        "wait-for-interface",
            "Wait for the Wireguard interface to show up",
            &context.waitForInterface,
        "P|progress",
            "Print progress messages",
            &context.progress,
        "l|language",
            "Notification language, default " ~ context.language,
            &context.language,
        "skip-intro",
            string.init, //"Skip the intro message (used internally)",
            &context.skipIntro,
        "reexec",
            string.init,
            &context.reexecuted,
        "dry-run",
            "Don't send notifications",
            &context.dryRun);

    if (peerTimeout >= 0) context.durations.peerTimeout = peerTimeout.seconds;
    if (sleepBetweenChecks > 0) context.durations.sleepBetweenChecks = sleepBetweenChecks.seconds;
    if (reportPeriodicity >= 0) context.durations.reportPeriodicity = reportPeriodicity.seconds;

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
