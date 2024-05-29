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
        context = out-reference to a [wg_monitor.context.Context|Context] struct.

    Returns:
        The results of [std.getopt.getopt|getopt].
 */
auto handleGetopt(const string[] args, out Context context)
{
    import core.time : seconds;
    static import std.getopt;

    // Integers to hold durations
    int peerTimeout = -1;
    int sleepBetweenChecks = -1;
    int firstReminder = -1;
    int secondReminder = -1;
    int thirdReminder = -1;
    int fourthReminder = -1;
    int furtherReminders = -1;
    auto mutArgs = args.dup;

    auto result = std.getopt.getopt(mutArgs,
        std.getopt.config.caseSensitive,
        //std.getopt.config.required,  // manually enforced later
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
        "first-reminder",
            string.init, //"First notification reminder delay in seconds",
            &firstReminder,
        "second-reminder",
            string.init, //"Second notification reminder delay in seconds",
            &secondReminder,
        "third-reminder",
            string.init, //"Third notification reminder delay in seconds",
            &thirdReminder,
        "fourth-reminder",
            string.init, //"Fourth notification reminder delay in seconds",
            &fourthReminder,
        "further-reminders",
            string.init, //"Further notification reminder delay in seconds",
            &furtherReminders,
        "wait-for-interface",
            "Wait for the Wireguard interface to show up",
            &context.waitForInterface,
        "P|progress",
            "Print progress messages",
            &context.progress,
        "l|language",
            "Notification language, default " ~ context.language,  // context is Context.init
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

    if (firstReminder > 0)
    {
        context.durations.firstReminder = firstReminder.seconds;
    }

    if ((secondReminder > 0) && (secondReminder > firstReminder))
    {
        context.durations.secondReminder = secondReminder.seconds;
    }

    if ((thirdReminder > 0) && (thirdReminder > secondReminder))
    {
        context.durations.thirdReminder = thirdReminder.seconds;
    }

    if ((fourthReminder > 0) && (fourthReminder > thirdReminder))
    {
        context.durations.fourthReminder = fourthReminder.seconds;
    }

    if ((furtherReminders > 0) && (furtherReminders > fourthReminder))
    {
        context.durations.furtherReminders = furtherReminders.seconds;
    }
    return result;
}


// parsePeerFile
/**
    Parses the peer list file and returns a Voldemort containing a `bool[string]`
    representing the peers listed inside; random bools keyed by peer hashes.

    Params:
        peerFile = Path to the peer list file.

    Returns:
        A Voldemort result struct.
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

        if ((hash.length == 0) || (hash[0] == '#')) continue;
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
        .filter!(a => (a.length > 0) && (a[0] != '#'))
        .array;
}


// resolveFilename
/**
    Resolves the filename of a configuration file.

    The order of precedence is:

    1. The current filename as passed by ref `filename`.
    2. The file in the current working directory named after the Wireguard interface
       (e.g. `wg0.list` and `wg0.url` for the `wg0` interface)
    3. The base file in the current working directory (e.g. `peers.list` and `batsign.url`)
    4. The file in `/etc/wg-monitor/` named after the Wireguard interface (as above).
    5. The base file in `/etc/wg-monitor/` (also as above).

    Matching is stopped as soon as a file is found.

    Params:
        filename = Reference to the filename to resolve. May already have a
            user-supplied value (via getopt).
        iface = The name of the Wireguard interface.
        defaultFilename = The default filename of the file to resolve.

    Returns:
        `true` if the file was found and the `filename` parameter was assigned
        to it; `false` otherwise.
 */
auto resolveFilename(
    ref string filename,
    const string iface,
    const string defaultFilename)
{
    import std.conv : text;
    import std.file : exists;
    import std.path : extension;

    if (filename.exists) return true;

    const filenameExtension = defaultFilename.extension;  // cache it

    const cwdIfaceFile = text(
        iface,
        filenameExtension);

    alias cwdBaseFile = defaultFilename;

    const etcIfaceFile = text(
        "/etc/wg-monitor/",
        iface,
        filenameExtension);

    const etcBaseFile = text(
        "/etc/wg-monitor/",
        defaultFilename);

    const string[4] allFilesInOrder =
    [
        cwdIfaceFile,
        cwdBaseFile,
        etcIfaceFile,
        etcBaseFile,
    ];

    foreach (const thisFilename; allFilesInOrder[])
    {
        if (thisFilename.exists)
        {
            // File found; return true
            filename = thisFilename;
            return true;
        }
    }

    // If we're here, no file was found
    return false;
}
