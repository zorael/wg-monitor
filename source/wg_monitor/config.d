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


// parseGetopt
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
auto parseGetopt(const string[] args, out Context context)
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
            &context.shouldShowVersionAndExit);

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


// parseFileIntoStringArray
/**
    Helper function to parse a file into an array of strings.

    Commented and empty lines are skipped. Mid-line comments are also cropped out.

    Params:
        filename = Path to the file to parse.

    Returns:
        An array of strings.
 */
auto parseFileIntoStringArray(const string filename)
{
    import std.algorithm.iteration : splitter;
    import std.file : readText;
    import std.string : chomp;

    string[] entries;

    auto range = filename
        .readText()
        .chomp()
        .splitter('\n');

    foreach (const line; range)
    {
        import lu.string : advancePast, stripped;
        import std.typecons : Flag, No, Yes;

        string slice = line.stripped;  // mutable
        if ((slice.length == 0) || (slice[0] == '#')) continue;  // empty line or comment

        // Advance past any mid-line comment octothorpes
        const entry = slice.advancePast('#', Yes.inherit).stripped;
        entries ~= entry;
    }

    return entries;
}


public:


// handleGetopt
/**
    Parses command-line arguments and sets up the program.

    Params:
        args = Command-line arguments passed to the program.

    Returns:
        A Voldemort struct containing a [wg_monitor.context.Context][Context]
        and an optional return value.

    See_Also:
        [parseGetopt]
 */
auto handleGetopt(const string[] args)
{
    import wg_monitor.common : ShellReturnValue;
    import wg_monitor.cout;
    import std.getopt : GetOptException;
    import std.stdio : stdout, writefln, writeln;

    /**
        Voldemort.
     */
    static struct GetoptResults
    {
        /**
            Context struct to populate with values from the passed arguments.
         */
        Context context;

        /**
            Return value to exit the program with, if it should exit.
         */
        ShellReturnValue retval;

        /**
            Whether the program should exit.
         */
        bool shouldExit;

        /**
            Whether the program should show the version string and exit.

            The bool is inside [context], so wrap it.
         */
        auto shouldShowVersionAndExit() const
        {
            return context.shouldShowVersionAndExit;
        }
    }

    scope(exit) stdout.flush();

    GetoptResults results;

    try
    {
        const getoptResults = parseGetopt(args, results.context);

        if (results.context.shouldShowVersionAndExit)
        {
            results.retval = ShellReturnValue.success;
            results.shouldExit = true;
            return results;
        }

        if (getoptResults.helpWanted)
        {
            import wg_monitor.translation : allTranslationLanguageNames;
            import std.getopt : Option;

            /**
                Prints the `--help` screen.
             */
            static void printGetoptHelpScreen(
                const Option[] allOptions,
                const string pattern = "%*s  %*s  %s")
            {
                size_t distanceShort;
                size_t distanceLong;

                /**
                    Returns true if the passed flag should be omitted from the `--help` screen.
                 */
                static auto shouldSkipFlag(const Option opt)
                {
                    import std.algorithm.comparison : among;
                    import std.algorithm.searching : endsWith;

                    return
                        (opt.optShort == "-h") ||
                        opt.optLong.among!(
                            "--reexec",
                            "--version",
                            "--cacert",
                            "--both") ||
                        opt.optLong.endsWith("-reminder") ||
                        opt.optLong.endsWith("-reminders");
                }

                Option[] options;
                options.reserve(allOptions.length);

                /**
                    Calculate the maximum format string distance for the short
                    and long flags. This is used to align the flags in the output.

                    Additionally populate the `options` array with the flags that
                    should actually be printed.
                 */
                foreach (const opt; allOptions)
                {
                    import std.algorithm.comparison : max;

                    if (shouldSkipFlag(opt)) continue;

                    options ~= opt;
                    distanceShort = max(distanceShort, opt.optShort.length);
                    distanceLong = max(distanceLong, opt.optLong.length);
                }

                foreach (const opt; options)
                {
                    writefln(
                        pattern,
                        distanceShort,
                        opt.optShort,
                        distanceLong,
                        opt.optLong,
                        opt.help);
                }
            }

            enum languagePattern = "Available languages: %-(%s, %)";

            printProgramVersion();
            writeln(' ');
            printGetoptHelpScreen(getoptResults.options);
            writeln(' ');
            writefln(languagePattern, allTranslationLanguageNames);
            results.retval = ShellReturnValue.success;
            results.shouldExit = true;
        }
    }
    catch (GetOptException e)
    {
        // Some other getopt error, such as an invalid flag passed
        printProgramVersion();
        writeln(' ');
        printError(e.msg);
        printGetoptInfo();
        results.retval = ShellReturnValue.getoptFailure;
        results.shouldExit = true;
    }

    return results;
}


// parsePeerFile
/**
    Parses the peer list file and returns a Voldemort containing a `bool[string]`
    representing the peers listed inside; random bools keyed by peer hashes.

    Params:
        peerFile = Path to the peer list file.

    Returns:
        A Voldemort result struct.

    See_Also:
        [parseFileIntoStringArray]
 */
auto parsePeerFile(const string peerFile)
{
    /**
        Voldemort.
     */
    static struct PeerFileHashes
    {
        bool[string] valid;
        string[] invalid;
    }

    PeerFileHashes result;
    const peerLines = parseFileIntoStringArray(peerFile);

    /*
        Walk all lines and validate them as peer hashes.
        Add them to result.valid if they are, otherwise to result.invalid.
     */
    foreach (const line; peerLines)
    {
        if ((line.length == 44) && (line[43] == '='))
        {
            // Seems to possibly be a hash?
            result.valid[line] = true;
        }
        else
        {
            // Definitely not a hash
            result.invalid ~= line;
        }
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
        [parseFileIntoStringArray]
 */
auto parseBatsignFile(const string batsignFile)
{
    return parseFileIntoStringArray(batsignFile);
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
