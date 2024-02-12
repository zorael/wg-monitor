/**
    Wireguard peer monitor.

    Calls a Wireguard command to get the latest handshake timestamps of all peers.

    A notification is sent if a peer hasn't been seen for a while, or if a peer
    returns after having been lost. Notifications can be sent via
    [Batsign](https://batsign.me), or by invoking a custom command.

    See_Also:
        https://batsign.me

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor.main;

private:

import std.stdio : stdout, writefln, writeln;


// shortHashLength
/**
    How many letters to use in the shorter representation form of a hash.

    Example:
    ---
    string hash = "44aN+J6y0BDf6hO8nbxlsKXVt+W9lra5KBaS7aUtgba="
    enum shortHash = hash[0..shortHashLength];
    // hash is now "44aN+J6"
    ---
 */
enum shortHashLength = 7;


// Translation
/**
    Translation strings for a language.

    String members should have a default value that refers to itself, to make
    it easier to spot missing translations.
 */
struct Translation
{
    /**
        Language name.
     */
    string language;

    /**
        Translation for "peer", in singular form.
     */
    string peerSingular = "peerSingular";

    /**
        Translation for "peer", in plural form.
     */
    string peerPlural = "peerPlural";

    /**
        Translation for the string used to describe a phase.
     */
    string phaseDescription = "phaseDescription";

    /**
        Translation for the string used when power has been restored but there
        were peers lost.
     */
    string powerBackAndContactLostWith = "powerBackAndContactLostWith";

    /**
        Translation for the string used when contact was just lost with a number
        of peers.
     */
    string justLostContactWith = "justLostContactWith";

    /**
        Translation for the string used when contact was just regained with a
        number of peers.
     */
    string justRegainedContactWith = "justRegainedContactWith";

    /**
        Translation for the string used when contact is still missing with a
        number of peers.
     */
    string stillMissingContactWith = "stillMissingContactWith";

    /**
        Translation for the string used when a peer hasn't been seen since the
        program was started.
     */
    string notSeenSinceRestart = "notSeenSinceRestart";

    /**
        Translation for the string used along with a timestamp when a peer was
        last seen. Inserted before the timestamp.
     */
    string lastSeenPre = "lastSeenPre";

    /**
        Translation for the string used along with a timestamp when a peer was
        last seen. Inserted after the timestamp.
     */
    string lastSeenPost = "lastSeenPost";

    /**
        Translation for the string used along with a timestamp when a peer has
        returned. Inserted before the timestamp.
     */
    string backPre = "backPre";

    /**
        Translation for the string used along with a timestamp when a peer has
        returned. Inserted after the timestamp.
     */
    string backPost = "backPost";

    /**
        Translation for the string used when all peers are present.
     */
    string nowHasContactWithAll = "nowHasContactWithAll";

    /**
        Inherits lines from the translations statically imported (and parsed)
        from the `translations.txt` file.

        Params:
            language = The language to inherit lines for.

        Returns:
            `true` if the specified language was found; `false` otherwise.

        See_Also:
            [allTranslations]

            `translations.txt` in the project root.
     */
    auto inherit(const string language)
    {
        foreach (const translation; this.allTranslations)
        {
            if (translation.language == language)
            {
                this = translation;
                return true;
            }
        }
        return false;
    }

    /**
        Translations statically imported from the `translations.txt` file.

        See_Also:
            [Translation]

            `translations.txt` in the project root.
     */
    static immutable allTranslations = ()
    {
        import std.algorithm.iteration : splitter;

        enum translationsOnFile = cast(string)import("translations.txt");

        Translation[] translations;
        auto translationRange = translationsOnFile.splitter("\n\n");

        foreach (const translationEntry; translationRange)
        {
            auto lineRange = translationEntry.splitter('\n');
            Translation translation;
            uint i;

            foreach (const line; lineRange)
            {
                import lu.string : AdvanceException, advancePast, stripped;
                import lu.objmanip : setMemberByName;
                import std.format : format;

                ++i;

                string slice = line.stripped;  // mutable
                if (!slice.length || (slice[0] == '#')) continue;

                try
                {
                    const key = slice.advancePast('=');
                    const success = translation.setMemberByName(key, slice);

                    if (!success)
                    {
                        enum pattern = `Translation error (%s) unknown key on %d:"%s"`;
                        const message = pattern.format(translation.language, i, key);
                        assert(0, message);
                    }
                }
                catch (AdvanceException e)
                {
                    enum pattern = `Translation error (%s) possibly missing '=' on %d:"%s"`;
                    const message = pattern.format(translation.language, i, slice);
                    assert(0, message);
                }
                catch (Exception e)
                {
                    enum pattern = `Translation error (%s) generic exception on %d:"%s"`;
                    const message = pattern.format(translation.language, i, slice);
                    assert(0, message);
                }
            }

            if (translation.language.length) translations ~= translation;
        }

        return translations;
    }();

    /**
        Returns an array of all language names found in `translations.txt`.

        Returns:
            An array of language names.

        See_Also:
            `translations.txt` in the project root.
     */
    static auto allLanguageNames()
    {
        string[] languageNames;

        foreach (const translation; Translation.allTranslations)
        {
            if (translation.language == "debug") continue;  // omit debug language
            languageNames ~= translation.language;
        }

        return languageNames;
    }
}


// Context
/**
    Context struct.
 */
struct Context
{
private:
    import core.time : Duration, hours, minutes, seconds;

public:
    /**
        Aggregate of durations used in the program.

        These are just defaults and may be overridden with getopt flags.
     */
    static struct Durations
    {
        /**
            A peer is considered lost after this amount of time has passed
            since last Wireguard handshake.
        */
        Duration peerTimeout = 10.minutes;

        /**
            How long to sleep between Wireguard handshake checks.
        */
        Duration sleepBetweenChecks = 1.minutes;

        /**
            How long to wait before repeating a notification.
        */
        Duration reportPeriodicity = 6.hours;
    }

    /**
        Wireguard interface.
     */
    string iface;

    /**
        File of Batsign URLs.

        See_Also:
            https://batsign.me
     */
    string batsignFile = "batsign.url";

    /**
        Batsign URLs parsed from [batsignFile].
     */
    string[] batsignURLs;

    /**
        File of Wireguard peer hashes.
     */
    string peerFile = "peers.list";

    /**
        Custom command to run to send notifications, instead of using Batsign.
     */
    string command;

    /**
        Certificate authority bundle filename.
     */
    string caBundleFile;

    /**
        Durations used in the program.
     */
    Durations durations;

    /**
        Language to use for notifications. Must be one of the languages in
        [allTranslations], and thus one of the languages in `translations.txt`.

        See_Also:
            [allTranslations]

            `translations.txt` in the project root.
     */
    string language = "english";

    /**
        Translation struct for the current language.
     */
    Translation translation;

    /**
        Associative array of peer hashes.
     */
    bool[string] peerList;

    /**
        Whether or not to print progress messages.
     */
    bool progress = true;

    /**
        Whether or not to skip the intro message.
     */
    bool skipIntro;

    /**
        Whether or not to perform a dry run.
     */
    bool dryRun;

    /**
        Whether to wait for a Wireguard interface to show up, or to abotr and
        exit if it doesn't exist during start-up.
     */
    bool waitForInterface = false;
}


// Peer
/**
    Embodies the notion of a Wireguard peer.
 */
struct Peer
{
private:
    import std.datetime.systime : SysTime;

public:
    /**
        Various states the peer may be in.
     */
    enum State
    {
        /**
            Init state; invalid.
         */
        unset,

        /**
            Peer has a handshake whose timestamp is *below* the timeout and has
            been such for at least one cycle.
         */
        present,

        /**
            Peer has a handshake whose timestamp is *above* the timeout and has
            been such for at least one cycle.
         */
        stillLost,

        /**
            Peer has a handshake whose timestamp is *below* the timeout but was
            above it last cycle.
         */
        justReturned,

        /**
            Peer has a handshake whose timestamp is *above* the timeout but was
            below it last cycle.
         */
        justLost,

        /**
            The program was just (re)started and the peer has a handshake whose
            timestamp is *above* the timeout.
         */
        lostOnStartup,
    }

    /**
        The public hash of the Wireguard peer in question.
     */
    string hash;

    /**
        The state of the peer.
     */
    State state;

    /**
        The timestamp of the peer's latest handshake; when it was last seen.
     */
    SysTime timestamp;

    /**
        Constructor.

        Params:
            hash = The public hash of the Wireguard peer.
     */
    this(const string hash)
    {
        this.hash = hash;
    }
}


// SortedPeers
/**
    A struct containing the current state of the Wireguard peers, sorted by
    connection state.
 */
struct SortedPeers
{
    /**
        All peers currently present, and have been so for at least one cycle.
     */
    Peer[] present;

    /**
        All peers considered to have been lost for at least one cycle.
     */
    Peer[] stillLost;

    /**
        All peers that just returned this cycle.
     */
    Peer[] justReturned;

    /**
        All peers that we just lost contact with this cycle.
     */
    Peer[] justLost;

    /**
        All peers that were lost at program start.
     */
    Peer[] lostOnStartup;

    /**
        Whether or not all peers are present, including those that just returned.

        Returns:
            `true` if all peers are present; `false` otherwise.
     */
    auto allPresent() const
    {
        return
            //this.present.length &&
            !this.stillLost.length &&
            //!this.justReturned.length &&
            !this.justLost.length &&
            !this.lostOnStartup.length;
    }

    /**
        Sorts the peers into the five arrays, one for each [Peer.State].

        Params:
            peers = The original associative array of [Peer]s.
     */
    this(const Peer[string] peers) pure @safe
    {
        import std.algorithm.sorting : sort;
        import std.functional : lessThan;

        foreach (peer; peers)
        {
            final switch (peer.state)
            {
            case Peer.State.present:
                this.present ~= peer;
                break;

            case Peer.State.justReturned:
                this.justReturned ~= peer;
                break;

            case Peer.State.stillLost:
                this.stillLost ~= peer;
                break;

            case Peer.State.justLost:
                this.justLost ~= peer;
                break;

            case Peer.State.lostOnStartup:
                this.lostOnStartup ~= peer;
                break;

            case Peer.State.unset:
                // Not in the peer list, ignore
                break;
            }
        }

        alias pred = (Peer a, Peer b) => a.hash.lessThan(b.hash);

        if (this.present.length) this.present = this.present.sort!pred.release();
        if (this.justReturned.length) this.justReturned = this.justReturned.sort!pred.release();
        if (this.stillLost.length) this.stillLost = this.stillLost.sort!pred.release();
        if (this.justLost.length) this.justLost = this.justLost.sort!pred.release();
        if (this.lostOnStartup.length) this.lostOnStartup = this.lostOnStartup.sort!pred.release();
    }
}


// ShellReturnValue
/**
    Return values for the program.
 */
enum ShellReturnValue
{
    /**
        Success.
     */
    success = 0,

    /**
        Unspecific failure.
     */
    failure = 1,

    /**
        Failure during getopt-parsing.
     */
    getoptFailure = 2,

    /**
        An exception was thrown.
     */
    exception = 3,

    /**
        A Batsign and/or peer file was missing.
     */
    missingFiles = 4,

    /**
        An invalid language was specified.
     */
    invalidLanguage = 5,

    /**
        Notification command not found.
     */
    commandNotFound = 6,

    /**
        Network error.
     */
    networkError = 7,
}


// getRawHandshakeString
/**
    Executes a Wireguard `latest-handshakes` command and returns the raw output.

    Params:
        iface = The string name of the Wireguard interface.

    Returns:
        The `chomp`ed output of the Wireguard command.

    Throws:
        [object.NeedSudoException|NeedSudoException] if `sudo` permissions are
        needed to execute the command.

        [object.Exception|Exception] on other errors.
 */
auto getRawHandshakeString(const string iface)
{
    import std.process : execute;
    import std.string : chomp;

    const string[4] wgCommand =
    [
        "/usr/bin/wg",
        "show",
        iface,
        "latest-handshakes",
    ];

    const result = execute(wgCommand[]);
    const output = result.output.chomp;

    if (result.status != 0)
    {
        enum sudoError = "Unable to access interface: Operation not permitted";
        enum ifaceError = "Unable to access interface: No such device";
        enum afError = "Unable to access interface: Address family not supported by protocol";

        switch (output)
        {
        case sudoError:
            throw new NeedSudoException(output);

        case ifaceError:
            throw new NoSuchInterfaceException(output, iface);

        case afError:
            throw new NetworkException(output);

        default:
            throw new Exception(output);
        }
    }

    return output;
}


// NeedSudoException
/**
    Exception thrown when a command fails due to lack of permissions.
 */
final class NeedSudoException : Exception
{
    /**
        Constructor.
     */
    this(
        const string message,
        const string file = __FILE__,
        const size_t line = __LINE__,
        Throwable nextInChain = null) pure nothrow @nogc @safe
    {
        super(message, file, line, nextInChain);
    }
}


// NoSuchInterfaceException
/**
    Exception thrown when a `wg` command fails due to a non-existent interface supplied.
 */
final class NoSuchInterfaceException : Exception
{
    /**
        Interface name.
     */
    string iface;

    /**
        Constructor.
     */
    this(
        const string message,
        const string iface,
        const string file = __FILE__,
        const size_t line = __LINE__,
        Throwable nextInChain = null) pure nothrow @nogc @safe
    {
        this.iface = iface;
        super(message, file, line, nextInChain);
    }
}


// NetworkException
/**
    Exception thrown when a `wg` command fails due to other network errors.
 */
final class NetworkException : Exception
{
    /**
        Constructor.
     */
    this(
        const string message,
        const string file = __FILE__,
        const size_t line = __LINE__,
        Throwable nextInChain = null) pure nothrow @nogc @safe
    {
        super(message, file, line, nextInChain);
    }
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
        [object.NeedSudoException|NeedSudoException] if `sudo` permissions are
        needed to execute the command (via [getRawHandshakeString]).

        [object.Exception|Exception] on other errors (via [getRawHandshakeString]).
 */
void getHandshakes(ref Peer[string] peers, const string iface)
{
    import std.algorithm.iteration : splitter;

    string rawHandshakes;  // mutable

    try
    {
        rawHandshakes = getRawHandshakeString(iface);
    }
    catch (NoSuchInterfaceException e)
    {
        writeln("[!] ", e.msg);
        writeln("[+] waiting for interface to return");
        stdout.flush();

        waitLoop:
        while (true)
        {
            try
            {
                // Keep trying
                rawHandshakes = getRawHandshakeString(iface);

                // If we're here, it didn't throw
                writeln("[+] interface found");
                break waitLoop;
            }
            catch (NoSuchInterfaceException _)
            {
                import core.thread : Thread;
                import core.time : seconds;

                static immutable wait = 10.seconds;
                Thread.sleep(wait);
            }
        }
    }

    auto handshakes = rawHandshakes.splitter('\n');

    foreach (const line; handshakes)
    {
        import std.conv : to;
        import std.datetime.systime : SysTime;
        import std.string : indexOf;

        const tabPos = line.indexOf('\t');
        if (tabPos == -1) continue;

        const hash = line[0..tabPos];
        auto peer = hash in peers;

        if (!peer)
        {
            peers[hash] = Peer(hash);
            peer = hash in peers;
        }

        peer.timestamp = SysTime.fromUnixTime(line[tabPos+1..$].to!long);
    }
}


// parsePeerList
/**
    Parses the peer list file and returns a `bool[string]` representing the peers
    listed inside; random bools keyed by peer hashes.

    Params:
        peerFile = The peer list file.

    Returns:
        A `bool[string]` associative array with keys of peer hashes.
 */
auto parsePeerList(const string peerFile)
{
    import std.algorithm.iteration : splitter;
    import std.file : readText;
    import std.string : chomp;

    bool[string] peerList;
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
            writeln("[!] invalid hash ignored: ", hash);
        }

        peerList[hash] = true;
    }

    return peerList;
}


// parseBatsignFile
/**
    Reads the Batsign file, parses the URLs therein, and returns it as a `string[]`.

    Params:
        batsignFile = The Batsign file.

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


// mainLoop
/**
    The main loop.

    Params:
        context = The context struct.
 */
void mainLoop(const Context context)
{
    import lu.string : plurality;
    import std.datetime.systime : SysTime;
    import std.format : format;

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

                static immutable wait = 10.seconds;
                Thread.sleep(wait);
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
            // Subsequent failures are considered recoverable.
            getHandshakes(peers, context.iface);
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
            if (peer.hash !in context.peerList) continue;

            const delta = (now - peer.timestamp);
            const timedOut = (delta > context.durations.peerTimeout);
            const thisChanged = peer.step(timedOut);
            somethingChanged |= thisChanged;

            if (context.progress)
            {
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
            const success = report(context, sortedPeers);
            if (success) lastReportTimestamp = now;
        }
    }

    assert(0, "unreachable");
}


// report
/**
    Compiles a report of missing peers and sends a notification via Batsign,
    or by invoking a custom command (if defined).

    Params:
        context = The context struct.
        sortedPeers = The current state of the Wireguard peers, sorted by connection state.
 */
auto report(
    const Context context,
    const SortedPeers sortedPeers)
{
    import std.array : Appender, join;

    Appender!(string[]) sink;
    sink.reserve(32);  // number of peers + upward of 7 extra lines

    void putMessage(
        const string translationLine,
        const size_t numPeers)
    {
        import lu.string : plurality;
        import std.array : replace;
        import std.conv : to;

        const peerNoun = numPeers.plurality(
            context.translation.peerSingular,
            context.translation.peerPlural);
        const numPeersString = numPeers.to!string;

        const message = translationLine
            .replace("$numPeers", numPeersString)
            .replace("$peerNoun", peerNoun);

        sink.put(message);
        sink.put(string.init);
    }

    void putPeerTable(
        const Peer[] peers,
        const string wordingPreTimestamp,
        const string wordingPostTimestamp)
    {
        import std.format : format;

        foreach (const peer; peers)
        {
            if (peer.timestamp.toUnixTime == 0)
            {
                enum pattern = "    %s, %s";
                const line = pattern.format(
                    getNameFromHash(peer.hash, context.translation.phaseDescription),
                    context.translation.notSeenSinceRestart);
                sink.put(line);
            }
            else
            {
                enum pattern = "    %s, %s%s%d-%02d-%02d %02d:%02d%s%s";
                const line = pattern.format(
                    getNameFromHash(peer.hash, context.translation.phaseDescription),
                    wordingPreTimestamp,
                    wordingPreTimestamp.length ? " " : string.init,
                    peer.timestamp.year, cast(uint)peer.timestamp.month, peer.timestamp.day,
                    peer.timestamp.hour, peer.timestamp.minute,
                    wordingPostTimestamp.length ? " " : string.init,
                    wordingPostTimestamp);
                sink.put(line);
            }
        }
    }

    auto getShortPeerRange(const Peer[] peers)
    {
        import std.algorithm.iteration : joiner, map;
        return peers
            .map!(peer => peer.hash[0..shortHashLength])
            .joiner(", ");
    }

    if (sortedPeers.lostOnStartup.length)
    {
        putMessage(
            context.translation.powerBackAndContactLostWith,
            sortedPeers.lostOnStartup.length);
        putPeerTable(
            sortedPeers.lostOnStartup,
            context.translation.lastSeenPre,
            context.translation.lastSeenPost);

        auto range = getShortPeerRange(sortedPeers.lostOnStartup);
        writeln("[!] lost on startup: ", range);
    }

    if (sortedPeers.justLost.length)
    {
        //if (sink.data.length) sink.put(string.init);

        putMessage(
            context.translation.justLostContactWith,
            sortedPeers.justLost.length);
        putPeerTable(
            sortedPeers.justLost,
            context.translation.lastSeenPre,
            context.translation.lastSeenPost);

        auto range = getShortPeerRange(sortedPeers.justLost);
        writeln("[!] just lost: ", range);
    }

    if (sortedPeers.justReturned.length)
    {
        if (sink.data.length) sink.put(string.init);

        putMessage(
            context.translation.justRegainedContactWith,
            sortedPeers.justReturned.length);
        putPeerTable(
            sortedPeers.justReturned,
            context.translation.backPre,
            context.translation.backPost);

        auto range = getShortPeerRange(sortedPeers.justReturned);
        writeln("[+] just returned: ", range);
    }

    if (sortedPeers.stillLost.length)
    {
        if (sink.data.length) sink.put(string.init);

        putMessage(
            context.translation.stillMissingContactWith,
            sortedPeers.stillLost.length);
        putPeerTable(
            sortedPeers.stillLost,
            context.translation.lastSeenPre,
            context.translation.lastSeenPost);

        auto range = getShortPeerRange(sortedPeers.stillLost);
        writeln("[!] still lost: ", range);
    }

    if (sortedPeers.allPresent)
    {
        /*if (sink.data.length)*/ sink.put(string.init);

        const message = context.translation.nowHasContactWithAll;
        sink.put(message);
        writeln("[+] all present");
    }

    stdout.flush();
    const body_ = sink[].join('\n');

    if (context.dryRun)
    {
        writeln();
        writeln(body_);
        writeln();
        stdout.flush();
        return true;
    }

    if (context.command.length)
    {
        const result = runCommand(context.command, body_);
        const success = (result.status == 0);

        if (success)
        {
            writeln("[+] notification command successful");
            //writeln(result.output.chomp);
        }
        else if (!success)
        {
            import std.string : chomp;
            writeln("[!] notification command failed with status ", result.status);
            writeln(result.output.chomp);
        }

        stdout.flush();
        return success;
    }
    else
    {
        const success = sendBatsign(context, body_);

        if (success)
        {
            writeln("[+] notification post successful");
        }
        /*else
        {
            // sendBatsign outputs errors internally
            writeln("[!] notification post failed");
            stdout.flush();
        }*/

        stdout.flush();
        return success;
    }
}


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
        "dry-run",
            "Don't send notifications",
            &context.dryRun);

    if (peerTimeout >= 0) context.durations.peerTimeout = peerTimeout.seconds;
    if (sleepBetweenChecks > 0) context.durations.sleepBetweenChecks = sleepBetweenChecks.seconds;
    if (reportPeriodicity >= 0) context.durations.reportPeriodicity = reportPeriodicity.seconds;

    return result;
}


// getNameFromHash
/**
    Parses a peer hash and returns a Voldemort struct that represents it in terms
    of naming.

    Params:
        fullHash = The full peer hash.
        phaseDescriptionPattern = The pattern to use for phase descriptions.

    Returns:
        A Voldemort representation of a peer.
 */
auto getNameFromHash(const string fullHash, const string phaseDescriptionPattern)
{
    import lu.string : advancePast;
    import std.string : indexOf;

    static struct PeerRepresentation
    {
        string name;
        string hash;
        uint phase;

        string phaseDescriptionPattern;

        auto toString() const
        {
            import std.array : replace;
            import std.conv : to;
            import std.string : capitalize;

            if (phase)
            {
                return this.phaseDescriptionPattern
                    .replace("$phaseName", this.name.capitalize)
                    .replace("$phaseNumber", this.phase.to!string);
            }
            else
            {
                return this.name.capitalize;
            }
        }
    }

    PeerRepresentation peerRep;
    peerRep.hash = fullHash;
    peerRep.phaseDescriptionPattern = phaseDescriptionPattern;
    string slice = fullHash[0..shortHashLength];

    if (slice.indexOf('+') != -1)
    {
        import std.ascii : isDigit;

        peerRep.name = slice.advancePast('+');

        if (slice.length && slice[0].isDigit)
        {
            enum asciiNumberOffset = 48;
            peerRep.phase = (slice[0] - asciiNumberOffset);

            if ((peerRep.phase < 1) || (peerRep.phase > 3))
            {
                // phases are 1-3; reset to 0 if invalid
                peerRep.phase = 0;
            }
        }
    }
    else if (slice.indexOf('/') != -1)
    {
        peerRep.name = slice.advancePast('/');
    }
    else
    {
        peerRep.name = slice;
    }

    return peerRep;
}

///
static if (shortHashLength >= 6)
unittest
{
    import std.conv : to;

    {
        enum hash = "44aN+J6y0BDf6hO8nbxlsKXVt+W9lra5KBaS7aUtgba=";
        const peer = getNameFromHash(hash, string.init);
        assert((peer.name == "44aN"), peer.name);
        assert(!peer.phase, peer.phase.to!string);
    }
    {
        enum hash = "44AN+1/fHCM12yay8WUitW1S3bxvRtulWnSQdHDeGab=";
        const peer = getNameFromHash(hash, string.init);
        assert((peer.name == "44AN"), peer.name);
        assert((peer.phase == 1), peer.phase.to!string);
    }
}


// sendBatsign
/**
    Sends a notification via Batsign.

    Params:
        context = The context struct.
        body_ = The body of the notification.

    Returns:
        `true` on full success; `false` on at least one failure.

    See_Also:
        https://batsign.me
 */
auto sendBatsign(const Context context, const string body_)
{
    import lu.conv : toAlpha;
    import core.time : seconds;

    static immutable postTimeout = 10.seconds;  // hardcoded

    static string[string] headers;
    headers["Content-Length"] = body_.length.toAlpha();

    bool success = true;

    foreach (const url; context.batsignURLs)
    {
        import requests : Request;

        auto req = Request();
        //req.verbosity = 1;
        req.keepAlive = false;
        req.timeout = postTimeout;
        req.addHeaders(headers);
        if (context.caBundleFile.length) req.sslSetCaCert(context.caBundleFile);

        try
        {
            auto res = req.post(url, body_);

            if ((res.code < 200) || (res.code >= 300))
            {
                writefln("[!] notification post returned status %s", res.code);
                //writeln(cast(string)res.responseBody);
                stdout.flush();
                success = false;
            }
        }
        catch (Exception e)
        {
            writefln("[!] notification post failed: %s", e.msg);
            stdout.flush();
            success = false;
        }
    }

    return success;
}


// runCommand
/**
    Runs a custom command to send a notification.

    Params:
        command = The command to run.
        body_ = The body of the notification.

    Returns:
        The Voldemort returned by [std.process.execute].
 */
auto runCommand(const string executable, const string body_)
{
    import std.process : execute;

    const string[2] command =
    [
        executable,
        body_,
    ];

    return execute(command[]);
}


// step
/**
    Steps a peer's state, advances it (in terms of a handshake cycle).

    Params:
        peer = The peer to step the state of.
        timedOut = Whether or not the peer has timed out.

    Returns:
        `true` if the state changed; `false` otherwise.
 */
auto step(
    ref Peer peer,
    const bool timedOut)
{
    if (timedOut)
    {
        // Peer is lost
        with (Peer.State)
        final switch (peer.state)
        {
        case present:
        case justReturned:
            // Was present, now lost
            peer.state = justLost;
            return true;

        case stillLost:
            // Leave as is
            break;

        case justLost:
        case lostOnStartup:
            // Became lost last cycle, still lost
            peer.state = stillLost;
            break;

        case unset:
            // Program startup
            peer.state = lostOnStartup;
            return true;
        }
    }
    else
    {
        // Peer is present
        with (Peer.State)
        final switch (peer.state)
        {
        case present:
            // Leave as is
            break;

        case stillLost:
        case justLost:
        case lostOnStartup:  // Program startup
            // Was lost, now present
            peer.state = justReturned;
            return true;

        case justReturned:
        case unset:
            // Became present last cycle, still present
            peer.state = present;
            break;
        }
    }

    return false;
}

///
unittest
{
    import lu.conv : enumToString;

    Peer peer;
    bool changed;
    assert((peer.state == Peer.State.unset), enumToString(peer.state));

    changed = peer.step(true);
    assert(changed);
    assert((peer.state == Peer.State.lostOnStartup), enumToString(peer.state));

    changed = peer.step(true);
    assert(!changed);
    assert((peer.state == Peer.State.stillLost), enumToString(peer.state));

    changed = peer.step(false);
    assert(changed);
    assert((peer.state == Peer.State.justReturned), enumToString(peer.state));

    changed = peer.step(false);
    assert(!changed);
    assert((peer.state == Peer.State.present), enumToString(peer.state));

    changed = peer.step(true);
    assert(changed);
    assert((peer.state == Peer.State.justLost), enumToString(peer.state));

    changed = peer.step(true);
    assert(!changed);
    assert((peer.state == Peer.State.stillLost), enumToString(peer.state));

    changed = peer.step(true);
    assert(!changed);
    assert((peer.state == Peer.State.stillLost), enumToString(peer.state));

    changed = peer.step(false);
    assert(changed);
    assert((peer.state == Peer.State.justReturned), enumToString(peer.state));

    changed = peer.step(false);
    assert(!changed);
    assert((peer.state == Peer.State.present), enumToString(peer.state));
}


// printProgramVersion
/**
    Prints the program version.
 */
void printProgramVersion() @safe
{
    alias v = WgMonitorSemVer;
    writefln("wireguard monitor v%d.%d.%d | copyright 2024 jr", v.major, v.minor, v.patch);
    writeln("$ git clone https://github.com/zorael/wg-monitor");
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
    import std.getopt : GetOptException;

    Context context;

    try
    {
        const getoptResults = handleGetopt(args, context);

        if (getoptResults.helpWanted)
        {
            import std.format : format;
            import std.getopt : Option;

            static void customGetoptPrinter(
                const Option[] opt,
                const string style = "%*s   %*s%*s%s")
            {
                import std.algorithm.comparison : max;

                size_t ls;
                size_t ll;
                bool hasRequired;

                auto shouldSkipFlag(const Option it)
                {
                    return
                        (it.optShort == "-h") ||
                        (it.optLong == "--skip-intro") ||
                        (it.optLong == "--cacert");
                }

                foreach (it; opt)
                {
                    if (shouldSkipFlag(it)) continue;
                    ls = max(ls, it.optShort.length);
                    ll = max(ll, it.optLong.length);
                    hasRequired |= it.required;
                }

                enum requiredText = "  (Required)  ";

                foreach (const it; opt)
                {
                    if (shouldSkipFlag(it)) continue;

                    writefln(
                        style,
                        ls,
                        it.optShort,
                        ll,
                        it.optLong,
                        hasRequired ? requiredText.length : 1,
                        it.required ? requiredText : " ",
                        it.help);
                }
            }

            enum languagePattern = "Available languages: %-(%s, %)";

            printProgramVersion();
            writeln();
            customGetoptPrinter(getoptResults.options);
            writeln();
            writefln(languagePattern, Translation.allLanguageNames);
            stdout.flush();
            return ShellReturnValue.success;
        }
    }
    catch (GetOptException e)
    {
        printProgramVersion();
        writeln(' ');
        writeln("[!] ", e.msg);
        writeln("[+] see --help for more information");
        stdout.flush();
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
                stdout.flush();
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
            writefln("[!] language '%s' not found", context.language);
            writefln("[+] available languages: %-(%s, %)", Translation.allLanguageNames);
            stdout.flush();
            return ShellReturnValue.invalidLanguage;
        }

        context.peerList = parsePeerList(context.peerFile);

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

        writeln("[!] ", e.msg);
        writeln("[+] re-executing with sudo.");
        stdout.flush();

        const reexecCommand =
        [
            "/usr/bin/sudo",
            args[0],
            "--skip-intro",
        ]  ~ args[1..$];

        execvp(reexecCommand[0], reexecCommand);
        assert(0, "reexec failed");  // It either execs successfully or throws
    }
    catch (NetworkException e)
    {
        writeln("[!] ", e.msg);
        stdout.flush();
        return ShellReturnValue.networkError;
    }
    catch (Exception e)
    {
        writeln("[!] ", e.msg);
        stdout.flush();
        return ShellReturnValue.exception;
    }

    assert(0, "unreachable");
}


// WgMonitorSemVer
/**
    SemVer versioning of this build.
 */
enum WgMonitorSemVer
{
    /**
        SemVer major version of the program.
     */
    major = 0,

    /**
        SemVer minor version of the program.
     */
    minor = 0,

    /**
        SemVer patch version of the program.
     */
    patch = 1,
}
