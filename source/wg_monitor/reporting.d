/**
    Reporting bits.

    See_Also:
        https://batsign.me

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor.reporting;

private:

import wg_monitor.context : Context;
import wg_monitor.peer : SortedPeers;


// getNameFromHash
/**
    Parses a peer hash and returns a Voldemort struct that represents it in terms
    of naming.

    Params:
        fullHash = The full peer hash.
        phaseDescriptionPattern = The pattern to use for phase descriptions.

    Returns:
        A Voldemort representation of a peer in terms of naming.
 */
auto getNameFromHash(const string fullHash, const string phaseDescriptionPattern)
{
    import wg_monitor.common : shortHashLength;
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
                    .replace("$phaseName", this.name.capitalize())
                    .replace("$phaseNumber", this.phase.to!string);
            }
            else
            {
                return this.name.capitalize();
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
unittest
{
    import wg_monitor.common : shortHashLength;

    static if (shortHashLength >= 6)
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
}


// sendBatsign
/**
    Sends a notification via Batsign.

    Params:
        context = The context struct.
        body_ = The body of the notification.

    Returns:
        An array of Voldemort structs representing any failures.

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

    static struct Failure
    {
        int code;
        string responseBody;
        string exceptionText;

        this(int code, string responseBody)
        {
            this.code = code;
            this.responseBody = responseBody;
        }

        this(string exceptionText)
        {
            this.exceptionText = exceptionText;
        }
    }

    Failure[] failures;

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
                import std.string : chomp;
                const responseBody = cast(string)res.responseBody;
                failures ~= Failure(res.code, responseBody.chomp());
            }
        }
        catch (Exception e)
        {
            failures ~= Failure(e.msg);
        }
    }

    return failures;
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


public:


// report
/**
    Compiles a report of missing peers and sends a notification via Batsign,
    or by invoking a custom command (if defined).

    If this is a dry run, the report is printed to the terminal instead.

    Params:
        context = The context struct.
        sortedPeers = The current state of the Wireguard peers, sorted by connection state.
 */
auto report(
    const Context context,
    const SortedPeers sortedPeers)
{
    import wg_monitor.peer : Peer;
    import std.array : Appender, join;
    import std.stdio : stdout, writeln;

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
        import wg_monitor.common : shortHashLength;
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

    scope(exit) stdout.flush();

    stdout.flush();
    const body_ = sink.data.join('\n');

    if (context.dryRun)
    {
        writeln();
        writeln(body_);
        writeln();
        return true;
    }

    if (context.command.length)
    {
        const result = runCommand(context.command, body_);
        const success = (result.status == 0);

        if (success)
        {
            writeln("[+] notification command successful");
            //writeln(result.output.chomp());
        }
        else if (!success)
        {
            import std.string : chomp;
            writeln("[!] notification command failed with status ", result.status);
            writeln(result.output.chomp());
        }

        return success;
    }
    else
    {
        const failures = sendBatsign(context, body_);

        if (!failures.length)
        {
            writeln("[+] notification post successful");
            return true;
        }

        foreach (const failure; failures)
        {
            if (failure.exceptionText.length)
            {
                writeln("[!] notification post failed: ", failure.exceptionText);
            }
            else
            {
                writeln("[!] notification post returned status ", failure.code);

                if (failure.code == 404)
                {
                    writeln("    (is the URL correct?)");
                }
                else
                {
                    if (failure.responseBody.length) writeln(failure.responseBody);
                }
            }
        }

        return false;
    }
}
