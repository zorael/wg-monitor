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
            ((now - lastReportTimestamp) > context.durations.reportPeriodicity));

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


public:


// run
/**
    Entrypoint.

    Params:
        args = Command-line arguments passed to the program.

    Returns:
        A [ShellReturnValue], indicating the program's success or failure.
 */
auto run(string[] args)
{
    import wg_monitor.common : NeedSudoException, NetworkException, ShellReturnValue;
    import wg_monitor.config : handleGetopt, parseBatsignFile, parsePeerFile;
    import std.getopt : GetOptException;
    import std.stdio : stdout, writefln, writeln;

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
                import std.algorithm.comparison : max;

                size_t distanceShort;
                size_t distanceLong;

                static auto shouldSkipFlag(const Option opt)
                {
                    return
                        (opt.optShort == "-h") ||
                        (opt.optLong == "--skip-intro") ||
                        (opt.optLong == "--cacert") ||
                        (opt.optLong == "--reexec");
                }

                foreach (opt; options)
                {
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

            printProgramVersion();
            writeln();
            customGetoptPrinter(getoptResults.options);
            writeln();
            writefln(languagePattern, allTranslationLanguageNames);
            return ShellReturnValue.success;
        }
    }
    catch (GetOptException e)
    {
        printProgramVersion();
        writeln(' ');
        writeln("[!] ", e.msg);
        writeln("[+] see --help for more information");
        return ShellReturnValue.getoptFailure;
    }

    if (!context.skipIntro)
    {
        printProgramVersion();
        writeln(' ');
    }

    try
    {
        import std.file : exists;
        import std.stdio : File;

        const peerFileExists = context.peerFile.exists;
        bool commandExists;
        bool batsignFileExists;

        if (!peerFileExists)
        {
            File(context.peerFile, "w").writeln();
            writefln("[+] %s created. add peer hashes to it.", context.peerFile);
            stdout.flush();
        }

        if (context.command.length)
        {
            import std.file : isDir;

            commandExists = (context.command.exists && !context.command.isDir);

            if (!commandExists)
            {
                writefln("[!] notification command '%s' not found", context.command);
                return ShellReturnValue.commandNotFound;
            }
        }
        else
        {
            batsignFileExists = context.batsignFile.exists;

            if (!batsignFileExists)
            {
                File(context.batsignFile, "w").writeln();
                writefln("[+] %s created. add one or more batsign URLs to it.", context.batsignFile);
                writeln("    (see https://batsign.me for more information)");
                stdout.flush();
            }

            if (!batsignFileExists) return ShellReturnValue.success;
        }

        if (!peerFileExists) return ShellReturnValue.success;

        const languageFound = context.translation.inherit(context.language);

        if (!languageFound)
        {
            import wg_monitor.translation : allTranslationLanguageNames;
            writefln("[!] language '%s' not found", context.language);
            writefln("[+] available languages: %-(%s, %)", allTranslationLanguageNames);
            return ShellReturnValue.invalidLanguage;
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

        context.batsignURLs = parseBatsignFile(context.batsignFile);

        if (!context.batsignURLs.length)
        {
            writefln("[!] %s is empty. add one or more batsign URLs to it.", context.batsignFile);
            stdout.flush();
        }

        // as above, exit here to have both messages printed
        if (!context.peerList.length || !context.batsignURLs.length) return ShellReturnValue.missingFiles;

        if (!context.skipIntro)
        {
            enum ifacePattern = "interface:           %s";
            writefln(ifacePattern, context.iface);

            enum peerPattern = "peer file exists:    %s (%d)";
            writefln(peerPattern, peerFileExists, context.peerList.length);

            if (context.command.length)
            {
                enum commandPattern = "command exists:      %s";
                writefln(commandPattern, commandExists);
            }
            else
            {
                enum batsignPattern = "batsign file exists: %s (%d)";
                writefln(batsignPattern, batsignFileExists, context.batsignURLs.length);

                if (context.caBundleFile.length)
                {
                    // Only print if a CA bundle file was specified
                    writeln("cacert.pem exists:   ", context.caBundleFile.exists);
                }
            }

            writeln("language set to:     ", context.language);
            writeln(' ');
            stdout.flush();
        }

        mainLoop(context);
    }
    catch (NeedSudoException e)
    {
        import std.process : execvp;

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
            "/usr/bin/sudo",
            args[0],
            "--skip-intro",
            "--reexec",
        ]  ~ args[1..$];

        execvp(reexecCommand[0], reexecCommand);
        assert(0, "exec failed");  // It either execs successfully or throws
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
