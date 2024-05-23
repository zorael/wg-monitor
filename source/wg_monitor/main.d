/**
    Main module.

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor.main;

private:

import wg_monitor.common : ShellReturnValue;
import wg_monitor.context : Context;
import wg_monitor.cout;

version(Windows)
{
    enum message = "This program is Posix-only until such time a console `wg` tool exists for Windows.";
    static assert(0, message);
}


// mainLoop
/**
    The main loop.

    Params:
        context = The context struct.
 */
void mainLoop(/*const*/ Context context)
{
    import wg_monitor.peer : Peer, SortedPeers;
    import lu.string : plurality;
    import std.datetime.systime : Clock, SysTime;
    import std.format : format;
    import std.stdio : stdout;
    import core.time : Duration;

    void printPreamble()
    {
        enum monitorMessagePattern = "monitoring %d %s, probing every %s.";
        const monitorMessage = monitorMessagePattern.format(
            context.peerList.length,
            context.peerList.length.plurality("peer", "peers"),
            context.durations.sleepBetweenChecks);

        printInfo(monitorMessage);

        if (context.progress)
        {
            import std.range : repeat;
            import std.stdio : writeln;

            // Only print the separator if we're also printing progress messages.
            enum separatorSign = '=';
            auto separator = separatorSign.repeat(monitorMessage.length + 4);  // account for "[+] "
            writeln(separator);
            stdout.flush();
        }
    }

    const Duration[5] reportReminders =
    [
        context.durations.firstReminder,
        context.durations.secondReminder,
        context.durations.thirdReminder,
        context.durations.fourthReminder,
        context.durations.furtherReminders,
    ];

    auto getReminderDelay(const size_t reminderCounter)
    {
        import std.algorithm.comparison : min;

        enum upperBound = reportReminders.length + (-1);
        immutable i = min(reminderCounter, upperBound);
        return reportReminders[i];
    }

    Peer[string] peers;
    SysTime lastReportTimestamp;
    const loopStart = Clock.currTime;
    size_t loopIteration;
    uint reminderCounter;

    printPreamble();

    while (true)
    {
        import wg_monitor.common : NoSuchInterfaceException;
        import wg_monitor.wg : getHandshakes;
        import core.thread : Thread;
        import core.time : Duration;

        scope(success) Thread.sleep(context.durations.sleepBetweenChecks);

        try
        {
            getHandshakes(peers, context.iface);
        }
        catch (NoSuchInterfaceException e)
        {
            printError(e.msg);
            printInfo("waiting for interface to return");

            inner:
            while (true)
            {
                try
                {
                    // Keep trying
                    getHandshakes(peers, context.iface);

                    // If we're here, it didn't throw
                    printInfo("interface found");
                    break inner;
                }
                catch (NoSuchInterfaceException _)
                {
                    import core.thread : Thread;
                    import core.time : seconds;

                    static immutable suddenWaitForInterfaceWait = 10.seconds;
                    Thread.sleep(suddenWaitForInterfaceWait);
                    //continue inner;
                }
            }
        }
        catch (Exception e)
        {
            printError(e.msg);
            continue;
        }

        scope(success) ++loopIteration;

        auto now = Clock.currTime;
        now.fracSecs = Duration.zero;
        const justStarted = (loopIteration == 0);
        bool onlyReturns = true;
        bool somethingChanged;

        peerStepLoop:
        foreach (ref peer; peers)
        {
            import wg_monitor.peer : step;

            if (peer.hash !in context.peerList) continue peerStepLoop;

            if (peer.wasNeverSeen)
            {
                // Peer has not yet been seen. Set the timestamp to the loop start
                peer.timestamp = loopStart;
            }

            const delta = (now - peer.timestamp);
            const timedOut = (delta > context.durations.peerTimeout);
            const thisChanged = peer.step(timedOut);
            somethingChanged |= thisChanged;

            with (Peer.State)
            final switch (peer.state)
            {
            case present:
            case unset:
                // Do nothing
                break;

            case justReturned:
                onlyReturns &= true;
                break;

            case stillLost:
            case justLost:
                onlyReturns = false;
                break;
            }

            if (context.progress)
            {
                import wg_monitor.common : shortHashLength;
                import std.stdio : writefln;

                enum pattern = "peer:%s | when:%d-%02d-%02d %02d:%02d | diff:%s%s%s";
                const deltaString = peer.wasNeverSeen ?
                    "unknown" :
                    delta.toString();

                writefln(
                    pattern,
                    peer.hash[0..shortHashLength],
                    peer.timestamp.year, cast(uint)peer.timestamp.month, peer.timestamp.day,
                    peer.timestamp.hour, peer.timestamp.minute,
                    deltaString,
                    timedOut ? " (!)" : string.init,
                    (thisChanged && !justStarted) ? " (UPDATED)" : string.init);
            }
        }

        if (context.progress) stdout.flush();

        const sortedPeers = SortedPeers(peers);
        const timeSinceLastReport = (now - lastReportTimestamp);
        const reminderGracePeriodEnded = (timeSinceLastReport >= getReminderDelay(reminderCounter));
        const shouldRemind = (!sortedPeers.allPresent && reminderGracePeriodEnded);

        bool shouldReport;
        shouldReport |= somethingChanged;
        shouldReport |= justStarted;
        shouldReport |= shouldRemind;

        onlyReturns &= (sortedPeers.justReturned.length > 0);

        if (shouldReport)
        {
            import wg_monitor.reporting : report;

            const success = report(context, sortedPeers, loopIteration);

            if (onlyReturns)
            {
                // Keep lastReportTimestamp and reminderCounter as-is if there were only returns
            }
            else
            {
                if (success) lastReportTimestamp = now;

                // Do the following even if the report failed
                if (sortedPeers.allPresent) reminderCounter = 0;
                else if (shouldRemind) ++reminderCounter;
            }
        }
    }

    assert(0, "unreachable");
}


// blockResolvingServerName
/**
    Tries to resolve the server name from the public key, blocking until the
    interface shows up if necessary.

    Params:
        context = Reference to the [wg_monitor.context.Context|Context] struct.
 */
auto blockResolvingServerName(ref Context context)
{
    import wg_monitor.common : NoSuchInterfaceException;
    import wg_monitor.wg : getOwnPublicKey;
    import wg_monitor.peer : getNameFromHash;

    try
    {
        // Try it to see if it works. We may be missing permissions.
        // It throws if it fails.
        context.publicKey = getOwnPublicKey(context.iface);
        context.serverName = getNameFromHash(context.publicKey, context.translation.phaseDescription).toString();
    }
    catch (NoSuchInterfaceException e)
    {
        if (!context.waitForInterface) throw e;

        printError(e.msg);
        printInfo("waiting for interface to show up");

        while (true)
        {
            try
            {
                // Keep trying
                context.publicKey = getOwnPublicKey(context.iface);

                // If we're here, it didn't throw
                printInfo("interface found");
                return;  // success
            }
            catch (NoSuchInterfaceException _)
            {
                import core.thread : Thread;
                import core.time : seconds;

                static immutable initWaitForInterfaceWait = 10.seconds;
                Thread.sleep(initWaitForInterfaceWait);
            }
        }
    }
}


// applyGetopt
/**
    Parses command-line arguments and sets up the program.

    Params:
        args = Command-line arguments passed to the program.
        context = out-reference to a new [wg_monitor.context.Context|Context],
            which will be populated according to the command-line arguments.
        retval = out-reference to a [wg_monitor.common.ShellReturnValue|ShellReturnValue]
            to exit with, should it be necessary.

    Returns:
        A `bool` indicating whether the program should exit.
 */
auto applyGetopt(
    const string[] args,
    out Context context,
    out ShellReturnValue retval)
{
    import std.getopt : GetOptException;
    import std.stdio : stdout, writefln, writeln;

    scope(exit) stdout.flush();

    try
    {
        import wg_monitor.config : handleGetopt;

        const getoptResults = handleGetopt(args, context);

        if (getoptResults.helpWanted)
        {
            import wg_monitor.translation : allTranslationLanguageNames;
            import std.getopt : Option;

            static void printGetoptHelpScreen(
                const Option[] allOptions,
                const string pattern = "%*s  %*s  %s")
            {
                size_t distanceShort;
                size_t distanceLong;

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
                        opt.optLong.endsWith("-reminder");
                }

                Option[] options;
                options.reserve(allOptions.length);

                foreach (const i, const opt; allOptions)
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
            retval = ShellReturnValue.success;
            return true;
        }

        return false;
    }
    catch (GetOptException e)
    {
        printProgramVersion();
        writeln(' ');
        printError(e.msg);
        printGetoptInfo();
        retval = ShellReturnValue.getoptFailure;
        return true;
    }

    assert(0, "unreachable");
}


// run
/**
    Entrypoint.

    Params:
        args = Command-line arguments passed to the program.
        context = Reference to the [wg_monitor.context.Context|Context] struct.

    Returns:
        A [wg_monitor.common.ShellReturnValue|ShellReturnValue], indicating the
        program's success or failure.
 */
auto run(const string[] args, ref Context context)
{
    import wg_monitor.common :
        CommandNotFoundException,
        NeedSudoException,
        NetworkException,
        ShellReturnValue;
    import wg_monitor.config : parseBatsignFile, parsePeerFile;
    import std.stdio : stdout, writefln, writeln;
    import std.utf : UTFException;

    if (!context.reexecuted)
    {
        printProgramVersion();
        writeln(' ');
    }

    try
    {
        import wg_monitor.config : resolveFilename;
        import std.file : exists, isDir;
        import std.stdio : File;
        import core.sys.posix.unistd : getuid;

        const userIsRoot = (getuid() == 0);

        bool commandExists;
        bool batsignFileExists;
        const peerFileExists = resolveFilename(context.peerFile, context.iface, Context.init.peerFile);

        if (!peerFileExists)
        {
            if (userIsRoot)
            {
                enum globalEtcPeerFile = "/etc/wg-monitor/" ~ Context.init.peerFile;
                printError("missing peer file");
                printInfo("suggested location is ", globalEtcPeerFile);
            }
            else
            {
                enum emptyFileContents = "# add peer hashes here, one per line.";
                File(context.peerFile, "w").writeln(emptyFileContents);
                printInfo(context.peerFile, " created. add peer hashes to it.");
            }
        }

        if (context.command.length > 0)
        {
            import std.path : isAbsolute;

            commandExists = (context.command.exists && !context.command.isDir);

            if (!commandExists)
            {
                import std.format : format;

                enum pattern = "notification command '%s' not found";
                const message = pattern.format(context.command);
                printError(message);
                return ShellReturnValue.commandNotFound;
            }

            if (!context.command.isAbsolute)
            {
                // Workaround to support being passed --command=script.sh
                context.command = "./" ~ context.command;
            }
        }
        else /*if (context.command.length == 0)*/
        {
            batsignFileExists = resolveFilename(context.batsignFile, context.iface, Context.init.batsignFile);

            if (!batsignFileExists)
            {
                if (userIsRoot)
                {
                    enum globalEtcBatsignFile = "/etc/wg-monitor/" ~ Context.init.batsignFile;
                    printError("missing batsign file");
                    printInfo("suggested location is ", globalEtcBatsignFile);
                }
                else
                {
                    enum emptyFileContents = "# add batsign URLs here, one per line.";
                    File(context.batsignFile, "w").writeln(emptyFileContents);
                    printInfo(context.batsignFile, " created. add one or more batsign URLs to it.");
                    printIndented("(see https://batsign.me for more information)");
                }
            }
        }

        const languageFound = context.translation.inherit(context.language);

        if (!languageFound)
        {
            import wg_monitor.translation : allTranslationLanguageNames;
            import std.format : format;

            enum notFoundPattern = "language '%s' not found";
            enum availablePattern = "available languages: %-(%s, %)";
            const notFoundMessage = notFoundPattern.format(context.language);
            const availableMessage = availablePattern.format(allTranslationLanguageNames);
            printError(notFoundMessage);
            printInfo(availableMessage);
            return ShellReturnValue.invalidLanguage;
        }

        if ((context.caBundleFile.length > 0) &&
            (!context.caBundleFile.exists || context.caBundleFile.isDir))
        {
            import std.format : format;

            enum notFoundPattern = "cacert file '%s' not found";
            const notFoundMessage = notFoundPattern.format(context.caBundleFile);
            printError(notFoundMessage);
            return ShellReturnValue.missingFiles;
        }

        if (!peerFileExists || (!batsignFileExists && !commandExists))
        {
            if ((context.command.length > 0) && !commandExists)
            {
                // Command missing when supplied is always an error
                return ShellReturnValue.commandNotFound;
            }

            // Other files missing is an error only if the user is root
            return userIsRoot ?
                ShellReturnValue.missingFilesRoot :
                ShellReturnValue.success;
        }

        auto peerFileHashes = parsePeerFile(context.peerFile);

        if (peerFileHashes.invalid.length > 0)
        {
            foreach (hash; peerFileHashes.invalid)
            {
                printError("invalid hash ignored: ", hash);
            }
        }

        context.peerList = peerFileHashes.valid;

        if (context.peerList.length == 0)
        {
            printError(context.peerFile, " is empty. add peer hashes to it.");
        }

        if (context.command.length > 0)
        {
            // No need to parse batsign file if we're using an external command
        }
        else /*if (context.batsignFile.length > 0)*/
        {
            context.batsignURLs = parseBatsignFile(context.batsignFile);

            if (context.batsignURLs.length == 0)
            {
                printError(context.batsignFile, " is empty. add one or more batsign URLs to it.");
            }
        }

        // As above, exit here to allow for both messages to be displayed
        if ((context.peerList.length == 0) ||
            ((context.batsignURLs.length == 0) && !commandExists))
        {
            return ShellReturnValue.emptyFiles;
        }

        if (context.iface.length == 0)
        {
            // Intro already printed
            printError("no interface provided");
            printGetoptInfo();
            return ShellReturnValue.getoptFailure;
        }

        if (!context.reexecuted)
        {
            enum width = 16;
            enum pattern = "%*s%s";

            printInfo("using ", context.peerFile);
            printInfo("using ", context.batsignFile);
            writeln(' ');
            writefln(pattern, -width, "interface:", context.iface);

            if (context.command.length > 0)
            {
                writefln(pattern, -width, "command:", context.command);
            }
            else
            {
                import lu.string : plurality;

                enum batsignPattern = "%*s%d %s";

                writefln(
                    batsignPattern,
                    -width,
                    "batsign:",
                    context.batsignURLs.length,
                    context.batsignURLs.length.plurality("url", "urls"));

                if (context.caBundleFile.length > 0)
                {
                    // Only print if a CA bundle file was actually specified
                    writefln(pattern, -width, "cacert:", context.caBundleFile);
                }
            }

            writefln(pattern, -width, "language:", context.language);
            writeln(' ');
            stdout.flush();
        }

        blockResolvingServerName(context);

        if (context.dryRun)
        {
            printInfo("dry run: not sending notifications");
        }

        mainLoop(context);
    }
    catch (NeedSudoException e)
    {
        import std.process : environment, execvp;

        if (context.reexecuted)
        {
            printError("still fails; exiting");
            return ShellReturnValue.otherPermissionsError;
        }

        printError(e.msg);
        printInfo("re-executing with sudo.");

        const reexecCommand =
        [
            environment.get("SUDO", "/usr/bin/sudo"),
            args[0],
            "--reexec",
        ] ~ args[1..$];

        execvp(reexecCommand[0], reexecCommand);
        assert(0, "exec failed");  // It either execs successfully or throws
    }
    catch (CommandNotFoundException e)
    {
        import std.process : environment;

        const wgOverridden = (environment.get("WG", string.init).length > 0);

        printError(e.msg);

        if (wgOverridden)
        {
            printInfo("/usr/bin/wg is overridden by the WG environment variable");
        }
        else
        {
            printQuery("is wireguard-tools (or equivalent) installed?");
        }
        return ShellReturnValue.commandNotFound;
    }
    catch (NetworkException e)
    {
        printError(e.msg);
        return ShellReturnValue.networkError;
    }
    catch (UTFException e)
    {
        printError("failed to parse peer or batsign file");
        printQuery("was a non-text file read?");
        return ShellReturnValue.badFiles;
    }
    /*catch (Exception e)  // catch in tryRun
    {
        printError(e.msg);
        return ShellReturnValue.exception;
    }*/

    assert(0, "unreachable");
}


// printGetoptInfo
/**
    Prints a message to the screen, indicating that more information can be found
    by running the program with the `--help` flag.
 */
void printGetoptInfo()
{
    printInfo("see --help for more information");
}


public:


// tryRun
/**
    Calls [applyGetopt] and [run] in a try-catch, so exceptions thrown that were not
    internally caught are still printed to the screen.

    Params:
        args = Command-line arguments passed to the program.

    Returns:
        A [wg_monitor.common.ShellReturnValue|ShellReturnValue], indicating the
        program's success or failure, as thrown by [applyGetopt] or [run].
 */
auto tryRun(const string[] args)
{
    try
    {
        Context context;
        ShellReturnValue retval;
        const shouldExit = applyGetopt(args, context, retval);

        if (shouldExit) return retval;

        if (context.showVersionAndExit)
        {
            printProgramVersion();
            return ShellReturnValue.success;
        }

        return run(args, context);
    }
    catch (Exception e)
    {
        printError(e.msg);
        return ShellReturnValue.exception;
    }
}
