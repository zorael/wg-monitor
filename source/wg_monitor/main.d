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
import wg_monitor.peer : SortedPeers;

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
void mainLoop(const Context context)
{
    import wg_monitor.peer : Peer;
    import wg_monitor.wg : getHandshakes, getRawHandshakeString;
    import wg_monitor.common : NoSuchInterfaceException;
    import lu.string : plurality;
    import std.datetime.systime : SysTime;
    import std.format : format;
    import std.stdio : stdout, writeln;

    try
    {
        // Try it out once to see if it works. We may be missing permissions.
        // It throws if it fails.
        getRawHandshakeString(context.iface);
    }
    catch (NoSuchInterfaceException e)
    {
        if (!context.waitForInterface) throw e;

        writeln("[!] ", e.msg);
        writeln("[+] waiting for interface to show up");
        stdout.flush();

        waitLoop:
        while (true)
        {
            try
            {
                // Keep trying
                getRawHandshakeString(context.iface);

                // If we're here, it didn't throw
                writeln("[+] interface found");
                break waitLoop;
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

    if (context.dryRun)
    {
        writeln("[+] dry run: not sending notifications");
    }

    // Print message *after* we know permissions are ok.
    enum monitorMessagePattern = "[+] monitoring %d %s, probing every %s.";

    const message = monitorMessagePattern.format(
        context.peerList.length,
        context.peerList.length.plurality("peer", "peers"),
        context.durations.sleepBetweenChecks);

    writeln(message);

    if (context.progress)
    {
        import std.range : repeat;
        // Only print the separator if we're also printing progress messages.
        enum separatorSign = '=';
        writeln(separatorSign.repeat(message.length));
    }

    stdout.flush();

    Peer[string] peers;
    SysTime lastReportTimestamp;

    while (true)
    {
        import std.datetime.systime : Clock;
        import core.thread : Thread;
        import core.time : Duration;

        scope(success) Thread.sleep(context.durations.sleepBetweenChecks);

        try
        {
            getHandshakes(peers, context.iface);
        }
        catch (NoSuchInterfaceException e)
        {
            import std.stdio : stdout, writeln;

            writeln("[!] ", e.msg);
            writeln("[+] waiting for interface to return");
            stdout.flush();

            inner:
            while (true)
            {
                try
                {
                    // Keep trying
                    getHandshakes(peers, context.iface);

                    // If we're here, it didn't throw
                    writeln("[+] interface found");
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
            writeln("[!] ", e.msg);
            stdout.flush();
            continue;
        }

        auto now = Clock.currTime;
        now.fracSecs = Duration.zero;
        bool somethingChanged;

        foreach (ref peer; peers)
        {
            import wg_monitor.peer : step;

            if (peer.hash !in context.peerList) continue;

            const delta = (now - peer.timestamp);
            const timedOut = (delta > context.durations.peerTimeout);
            const thisChanged = peer.step(timedOut);
            somethingChanged |= thisChanged;

            if (context.progress)
            {
                import wg_monitor.common : shortHashLength;
                import std.stdio : writefln;

                enum peerReportPattern = "peer:%s | when:%d-%02d-%02d %02d:%02d | diff:%s%s%s";

                writefln(
                    peerReportPattern,
                    peer.hash[0..shortHashLength],
                    peer.timestamp.year, cast(uint)peer.timestamp.month, peer.timestamp.day,
                    peer.timestamp.hour, peer.timestamp.minute,
                    delta,
                    timedOut ? " (!)" : string.init,
                    thisChanged ? " (NEW)" : string.init);
            }
        }

        if (context.progress) stdout.flush();

        const sortedPeers = SortedPeers(peers);
        const shouldReport =
            somethingChanged ||
            (!sortedPeers.allPresent &&
            ((now - lastReportTimestamp) > context.durations.reminderPeriodicity));

        if (shouldReport)
        {
            import wg_monitor.reporting : report;
            const success = report(context, sortedPeers);
            if (success) lastReportTimestamp = now;
        }
    }

    assert(0, "unreachable");
}


// printProgramVersion
/**
    Prints the program version.
 */
void printProgramVersion() @safe
{
    import wg_monitor.semver : WgMonitorSemVer;
    import std.stdio : writefln, writeln;

    enum sourceURL = "https://github.com/zorael/wg-monitor";

    alias v = WgMonitorSemVer;
    writefln("wireguard monitor v%d.%d.%d | copyright 2024 jr", v.major, v.minor, v.patch);
    writeln("$ git clone " ~ sourceURL ~ ".git");
}


// run
/**
    Entrypoint.

    Params:
        args = Command-line arguments passed to the program.

    Returns:
        A [wg_monitor.common.ShellReturnValue|ShellReturnValue], indicating the
        program's success or failure.
 */
auto run(string[] args)
{
    import wg_monitor.common :
        CommandNotFoundException,
        NeedSudoException,
        NetworkException,
        ShellReturnValue;
    import wg_monitor.config : handleGetopt, parseBatsignFile, parsePeerFile;
    import std.getopt : GetOptException;
    import std.stdio : stdout, writefln, writeln;

    static void printIntro()
    {
        printProgramVersion();
        writeln(' ');
    }

    static void printError(const string message)
    {
        writeln("[!] ", message);
        writeln("[+] see --help for more information");
    }

    static void printIntroError(const string message)
    {
        printIntro();
        printError(message);
    }

    scope(exit) stdout.flush();

    Context context;

    try
    {
        const getoptResults = handleGetopt(args, context);

        if (getoptResults.helpWanted)
        {
            import wg_monitor.translation : allTranslationLanguageNames;
            import std.getopt : Option;

            static void customGetoptPrinter(
                const Option[] options,
                const string pattern = "%*s  %*s  %s")
            {
                size_t distanceShort;
                size_t distanceLong;

                static auto shouldSkipFlag(const Option opt)
                {
                    import std.algorithm.comparison : among;

                    return
                        (opt.optShort == "-h") ||
                        opt.optLong.among!(
                            "--reexec",
                            "--version",
                            "--cacert",
                            "--both");
                }

                foreach (const opt; options)
                {
                    import std.algorithm.comparison : max;

                    if (shouldSkipFlag(opt)) continue;

                    distanceShort = max(distanceShort, opt.optShort.length);
                    distanceLong = max(distanceLong, opt.optLong.length);
                }

                foreach (const opt; options)
                {
                    if (shouldSkipFlag(opt)) continue;

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

            printIntro();
            customGetoptPrinter(getoptResults.options);
            writeln(' ');
            writefln(languagePattern, allTranslationLanguageNames);
            return ShellReturnValue.success;
        }
    }
    catch (GetOptException e)
    {
        printIntroError(e.msg);
        return ShellReturnValue.getoptFailure;
    }

    if (context.showVersionAndExit)
    {
        printProgramVersion();
        return ShellReturnValue.success;
    }

    if (!context.reexecuted) printIntro();

    try
    {
        import std.conv : text;
        import std.file : exists, isDir;
        import std.path : extension;
        import std.stdio : File;
        import core.sys.posix.unistd : getuid;

        const userIsRoot = (getuid() == 0);

        bool peerFileExists;
        bool commandExists;
        bool batsignFileExists;

        peerFileExists = context.peerFile.exists;

        if (!peerFileExists)
        {
            enum globalEtcPeerFile = "/etc/wg-monitor/" ~ Context.init.peerFile;
            const etcPeerFile = text(
                "/etc/wg-monitor/",
                context.iface,
                Context.init.peerFile.extension);  // ".list"

            if (etcPeerFile.exists)
            {
                context.peerFile = etcPeerFile;
                peerFileExists = true;
            }
            else if (globalEtcPeerFile.exists)
            {
                context.peerFile = globalEtcPeerFile;
                peerFileExists = true;
            }
            else if (userIsRoot)
            {
                writeln("[!] missing peer file");
                writeln("[+] suggested location is ", globalEtcPeerFile);
            }
            else
            {
                enum emptyFileContents = "# add peer hashes here, one per line.";
                File(context.peerFile, "w").writeln(emptyFileContents);
                writefln("[+] %s created. add peer hashes to it.", context.peerFile);
                stdout.flush();
            }
        }

        if (context.command.length)
        {
            import std.path : isAbsolute;

            commandExists = (context.command.exists && !context.command.isDir);

            if (!commandExists)
            {
                writefln("[!] notification command '%s' not found", context.command);
                return ShellReturnValue.commandNotFound;
            }

            if (!context.command.isAbsolute)
            {
                // Workaround to support being passed --command=script.sh
                context.command = "./" ~ context.command;
            }
        }
        else
        {
            batsignFileExists = context.batsignFile.exists;

            if (!batsignFileExists)
            {
                enum globalEtcBatsignFile = "/etc/wg-monitor/" ~ Context.init.batsignFile;
                const etcBatsignFile = text(
                    "/etc/wg-monitor/",
                    context.iface,
                    Context.init.batsignFile.extension);  // ".url"

                if (etcBatsignFile.exists)
                {
                    context.batsignFile = etcBatsignFile;
                    batsignFileExists = true;
                }
                else if (globalEtcBatsignFile.exists)
                {
                    context.batsignFile = globalEtcBatsignFile;
                    batsignFileExists = true;
                }
                else if (userIsRoot)
                {
                    writeln("[!] missing batsign file");
                    writeln("[+] suggested location is ", globalEtcBatsignFile);
                }
                else
                {
                    enum emptyFileContents = "# add batsign URLs here, one per line.";
                    File(context.batsignFile, "w").writeln(emptyFileContents);
                    writefln("[+] %s created. add one or more batsign URLs to it.", context.batsignFile);
                    writeln("    (see https://batsign.me for more information)");
                }
                stdout.flush();
            }
        }

        const languageFound = context.translation.inherit(context.language);

        if (!languageFound)
        {
            import wg_monitor.translation : allTranslationLanguageNames;
            writefln("[!] language '%s' not found", context.language);
            writefln("[+] available languages: %-(%s, %)", allTranslationLanguageNames);
            return ShellReturnValue.invalidLanguage;
        }

        if (context.caBundleFile.length && (!context.caBundleFile.exists || context.caBundleFile.isDir))
        {
            writefln("[!] cacert file '%s' not found", context.caBundleFile);
            return ShellReturnValue.missingFiles;
        }

        if (!peerFileExists || (!batsignFileExists && !commandExists))
        {
            if (context.command.length && !commandExists)
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

        if (peerFileHashes.invalid.length)
        {
            foreach (hash; peerFileHashes.invalid)
            {
                writeln("[!] invalid hash ignored: ", hash);
            }
            stdout.flush();
        }

        context.peerList = peerFileHashes.valid;

        if (!context.peerList.length)
        {
            writefln("[!] %s is empty. add peer hashes to it.", context.peerFile);
            stdout.flush();
        }

        if (context.command.length)
        {
            // No need to parse batsign file if we're using a custom command
        }
        else
        {
            context.batsignURLs = parseBatsignFile(context.batsignFile);

            if (!context.batsignURLs.length)
            {
                writefln("[!] %s is empty. add one or more batsign URLs to it.", context.batsignFile);
                stdout.flush();
            }
        }

        // as above, exit here to allow for both messages to be displayed
        if (!context.peerList.length || (!context.batsignURLs.length && !commandExists))
        {
            return ShellReturnValue.emptyFiles;
        }

        if (!context.iface.length)
        {
            // intro already printed
            printError("no interface provided");
            return ShellReturnValue.getoptFailure;
        }

        if (!context.reexecuted)
        {
            writeln("[+] using ", context.peerFile);
            writeln("[+] using ", context.batsignFile);
            writeln(' ');

            enum ifacePattern = "interface:     %s";
            writefln(ifacePattern, context.iface);

            if (context.command.length)
            {
                enum commandPattern = "command:       %s";
                writefln(commandPattern, context.command);
            }
            else
            {
                import lu.string : plurality;

                enum batsignPattern = "batsigns:      %d %s";

                writefln(
                    batsignPattern,
                    context.batsignURLs.length,
                    context.batsignURLs.length.plurality("url", "urls"));

                if (context.caBundleFile.length)
                {
                    // Only print if a CA bundle file was actually specified
                    writeln("cacert:        ", context.caBundleFile);
                }
            }

            writeln("language:      ", context.language);
            writeln(' ');
            stdout.flush();
        }

        mainLoop(context);
    }
    catch (NeedSudoException e)
    {
        import std.process : environment, execvp;

        if (context.reexecuted)
        {
            writeln("[!] still fails; exiting");
            return ShellReturnValue.otherPermissionsError;
        }

        writeln("[!] ", e.msg);
        writeln("[+] re-executing with sudo.");
        stdout.flush();

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

        writeln("[!] ", e.msg);

        if (wgOverridden)
        {
            writeln("[+] /usr/bin/wg is overridden by the WG environment variable");
        }
        else
        {
            writeln("[?] is wireguard-tools (or equivalent) installed?");
        }
        return ShellReturnValue.commandNotFound;
    }
    catch (NetworkException e)
    {
        writeln("[!] ", e.msg);
        return ShellReturnValue.networkError;
    }
    catch (Exception e)
    {
        writeln("[!] ", e.msg);
        return ShellReturnValue.exception;
    }

    assert(0, "unreachable");
}


public:


// tryRun
/**
    Calls [run] in a try-catch, so exceptions thrown that were not internally
    caught are still printed to the screen.

    Params:
        args = Command-line arguments passed to the program.

    Returns:
        A [wg_monitor.common.ShellReturnValue|ShellReturnValue], indicating the
        program's success or failure, as thrown by [run].
 */
auto tryRun(string[] args)
{
    try
    {
        return run(args);
    }
    catch (Exception e)
    {
        import wg_monitor.common : ShellReturnValue;
        import std.stdio : writeln;

        writeln("[!] ", e.msg);
        return ShellReturnValue.exception;
    }
}
