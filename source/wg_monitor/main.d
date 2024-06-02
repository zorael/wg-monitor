/**
    Main module.

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor.main;

private:

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
    import std.datetime.systime : Clock, SysTime;
    import std.stdio : stdout;
    import core.time : Duration;

    /**
        Prints the starting message.
     */
    void printPreamble()
    {
        import lu.string : plurality;
        import std.format : format;

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

    /**
        The reminder durations, in order of appearance in the report.
     */
    const Duration[5] reportReminders =
    [
        context.durations.firstReminder,
        context.durations.secondReminder,
        context.durations.thirdReminder,
        context.durations.fourthReminder,
        context.durations.furtherReminders,
    ];

    /**
        Returns the reminder delay for the given reminder counter.
     */
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

        // Don't sleep if there were errors; otherwise sleep after each iteration
        scope(success) Thread.sleep(context.durations.sleepBetweenChecks);

        try
        {
            // This throws on failure
            getHandshakes(peers, context.iface);
        }
        catch (NoSuchInterfaceException e)
        {
            printError(e.msg);
            printInfo("waiting for interface to return");

            inner:
            while (true)
            {
                import core.thread : Thread;
                import core.time : seconds;

                static immutable retryDelay = 10.seconds;

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
                    Thread.sleep(retryDelay);
                    //continue inner;
                }
                catch (Exception e)
                {
                    printError(e.msg);
                    Thread.sleep(retryDelay);
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
        bool somethingChanged;
        bool onlyReturns = true;  /// The only change were of returning peers

        peerStepLoop:
        foreach (ref peer; peers)
        {
            import wg_monitor.peer : step;

            // Skip peers not in the list
            if (peer.hash !in context.peerList) continue peerStepLoop;

            if (peer.wasNeverSeen)
            {
                // Peer has not yet been seen. Override the timestamp to that of the loop start
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
                // Ignore
                break;

            case justReturned:
                // Confirm onlyReturns
                onlyReturns &= true;
                break;

            case stillLost:
            case justLost:
                // Falsify onlyReturns
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

        // Falsify onlyReturns if there actually were no returns (since the variable is default true)
        onlyReturns &= (sortedPeers.justReturned.length > 0);

        if (shouldReport)
        {
            import wg_monitor.reporting : report;

            const success = report(context, sortedPeers, loopIteration);

            if (onlyReturns)
            {
                // The only change was of peers returning
                // Keep lastReportTimestamp and reminderCounter as-is
            }
            else
            {
                if (success) lastReportTimestamp = now;

                // Do the following even if the report failed (success false)
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
    interface shows up (if necessary).

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
        // Rethrow if we weren't passed --wait-for-interface
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
    /*catch (Exception _)
    {
        // Let exceptions pass
    }*/
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
        // Only print the start up message on the initial run (reexecuted false)
        printProgramVersion();
        writeln(' ');
    }

    try
    {
        import wg_monitor.config : resolveFilename;
        import std.file : exists, isDir;
        import std.stdio : File;
        import core.sys.posix.unistd : getuid;

        bool commandExists;
        bool batsignFileExists;
        const peerFileExists = resolveFilename(context.peerFile, context.iface, Context.init.peerFile);
        const userIsRoot = (getuid() == 0);

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

            // An external command was supplied, which overrides the batsign file
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
            // No external command was supplied; check for batsign file
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

        // Resolve translations, if possible
        const languageFound = context.translation.inherit(context.language);

        if (!languageFound)
        {
            import wg_monitor.translation : allTranslationLanguageNames;
            import std.format : format;

            // It wasn't.
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

            // cacert.pem supplied but it doesn't exist or is a directory
            enum notFoundPattern = "cacert file '%s' not found";
            const notFoundMessage = notFoundPattern.format(context.caBundleFile);
            printError(notFoundMessage);
            return ShellReturnValue.missingFiles;
        }

        if (!peerFileExists || (!batsignFileExists && !commandExists))
        {
            // Insufficient files to proceed
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
            // Print invalid hashes, but continue
            foreach (hash; peerFileHashes.invalid)
            {
                printError("invalid hash ignored: ", hash);
            }
        }

        context.peerList = peerFileHashes.valid;

        if (context.peerList.length == 0)
        {
            // The peer list is effectively empty and we cannot proceed.
            // Print error here, return later to allow for more messages to be displayed
            printError(context.peerFile, " is empty. add peer hashes to it.");
        }

        if (context.command.length > 0)
        {
            // An external command was provided
            // No need to parse batsign file
        }
        else /*if (context.batsignFile.length > 0)*/
        {
            // No external command; parse batsign file
            context.batsignURLs = parseBatsignFile(context.batsignFile);

            if (context.batsignURLs.length == 0)
            {
                // Print error here, return below
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
            // Print the configuration
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
            else /*if (context.command.length == 0)*/
            {
                import lu.string : plurality;

                // Print the number of batsign URLs
                enum batsignPattern = "%*s%d %s";

                writefln(
                    batsignPattern,
                    -width,
                    "batsign:",
                    context.batsignURLs.length,
                    context.batsignURLs.length.plurality("url", "urls"));

                if (context.caBundleFile.length > 0)
                {
                    // Only print cacert filename if one was actually provided
                    writefln(pattern, -width, "cacert:", context.caBundleFile);
                }
            }

            writefln(pattern, -width, "language:", context.language);
            writeln(' ');
            stdout.flush();
        }

        // Resolve the Wireguard peer representation of this server peer
        // It blocks until it succeeds, or throws if it fails
        blockResolvingServerName(context);

        if (context.dryRun)
        {
            printInfo("dry run: not sending notifications");
        }

        // Finally, start main loop
        mainLoop(context);
    }
    catch (NeedSudoException e)
    {
        import std.process : environment, execvp;

        // Superuser permissions are required
        if (context.reexecuted)
        {
            printError("still fails; exiting");
            return ShellReturnValue.otherPermissionsError;
        }

        // exec with sudo
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

        // The wg command was not found
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
        // A non-specific network error occurred
        printError(e.msg);
        return ShellReturnValue.networkError;
    }
    catch (UTFException e)
    {
        // There were issues reading the peer or batsign file as UTF-8 text
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


public:


// tryRun
/**
    Calls [wg_monitor.config.handleGetopt] and [run] in a try-catch, so exceptions
    thrown that were not internally caught are still printed to the screen.

    Params:
        args = Command-line arguments passed to the program.

    Returns:
        A [wg_monitor.common.ShellReturnValue|ShellReturnValue], indicating the
        program's success or failure, as thrown by
        [wg_monitor.config.handleGetopt|handleGetopt] or [run].
 */
auto tryRun(const string[] args)
{
    try
    {
        import wg_monitor.config : handleGetopt;

        auto results = handleGetopt(args);

        if (results.shouldShowVersionAndExit) printProgramVersion();
        if (results.shouldExit) return results.retval;

        return run(args, results.context);
    }
    catch (Exception e)
    {
        import wg_monitor.common : ShellReturnValue;

        printError(e.msg);
        return ShellReturnValue.exception;
    }
}
