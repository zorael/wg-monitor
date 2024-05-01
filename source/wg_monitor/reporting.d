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
    Runs an external command to send a notification.

    It will be invoked with the body of the notification as its first argument,
    the number of iterations the main loop has run (starting from 0) as its second,
    and then four strings of space-separated peer hashes as arguments 3-6.

    In order;

    1. notification body
    2. main loop iteration number (integer)
    3. peers just lost
    4. peers just returned
    5. peers still lost (reminder notification)
    6. peers present

    Params:
        command = The command to run.
        body_ = The body of the notification.
        loopIteration = The current loop iteration (counter).
        sortedPeers = The current state of the Wireguard peers, sorted by connection state.

    Returns:
        The Voldemort returned by [std.process.execute].
 */
auto runCommand(
    const string executable,
    const string body_,
    const size_t loopIteration,
    const SortedPeers sortedPeers)
{
    import wg_monitor.peer : Peer;
    import std.conv : to;
    import std.process : execute;

    static auto concatenate(const Peer[] peers)
    {
        import std.algorithm.iteration : map;
        import std.array : join;

        enum separator = ' ';

        return peers
            .map!(peer => peer.hash)
            .join(separator);
    }

    const string[7] command =
    [
        executable,
        body_,
        loopIteration.to!string,
        concatenate(sortedPeers.justLost),
        concatenate(sortedPeers.justReturned),
        concatenate(sortedPeers.stillLost),
        concatenate(sortedPeers.present),
    ];

    return execute(command[]);
}


// composeNotificationBody
/**
    Composes the lines of the notification body, as an array of strings.
    Use [std.array.join|join] to concatenate them into a single string.

    Params:
        context = The context struct.
        sortedPeers = The current state of the Wireguard peers, sorted by connection state.
        loopIteration = The current loop iteration (counter).

    Returns:
        An array of strings, each representing a line in the notification body.
 */
auto composeNotificationBody(
    const Context context,
    const SortedPeers sortedPeers,
    const size_t loopIteration)
{
    import wg_monitor.peer : Peer, getNameFromHash;
    import std.array : Appender;

    /*
        These have to match the tokens used in the translations.txt file.

        $phaseName and $phaseNumber are used in the .toString() of the Voldemort
        returned by getNameFromHash, not here.
     */
    enum ReplaceTokens
    {
        numPeers = "$numPeers",
        peerNoun = "$peerNoun",
        peerList = "$peerList",
        timestamp = "$timestamp",
        serverName = "$serverName",
    }

    Appender!(string[]) sink;
    sink.reserve(32);  // number of peers + upward of 7 extra lines

    void putMessage(
        const string translationLine,
        const size_t numPeers)
    {
        import lu.string : plurality;
        import std.algorithm.iteration : map;
        import std.algorithm.sorting : sort;
        import std.array : array, join, replace;
        import std.conv : to;
        import std.string : indexOf;

        const peerNoun = numPeers.plurality(
            context.translation.peerSingular,
            context.translation.peerPlural);
        const numPeersString = numPeers.to!string;
        const peerList = (translationLine.indexOf(cast(string)ReplaceTokens.peerList) != -1) ?
            context.peerList
                .byKey
                .map!(hash => getNameFromHash(hash, context.translation.phaseDescription))
                .array
                .map!(peer => peer.toString())
                .array
                .sort()
                .release()
                .join(", ") :
            string.init;

        auto message = translationLine
            .replace(cast(string)ReplaceTokens.numPeers, numPeersString)
            .replace(cast(string)ReplaceTokens.peerNoun, peerNoun)
            .replace(cast(string)ReplaceTokens.peerList, peerList);

        sink.put(message);
        sink.put(string.init);
    }

    void putPeerTable(
        const Peer[] peers,
        const string wording)
    {
        import std.array : replace;
        import std.format : format;

        foreach (const peer; peers)
        {
            enum pattern = "    %s, %s";

            if (peer.wasNeverSeen)
            {
                const line = pattern.format(
                    getNameFromHash(peer.hash, context.translation.phaseDescription),
                    context.translation.notSeenSinceRestart);
                sink.put(line);
            }
            else
            {
                enum datePattern = "%d-%02d-%02d %02d:%02d";
                const timestamp = datePattern.format(
                    peer.timestamp.year, cast(uint)peer.timestamp.month, peer.timestamp.day,
                    peer.timestamp.hour, peer.timestamp.minute);
                const line = pattern.format(
                    getNameFromHash(peer.hash, context.translation.phaseDescription),
                    wording.replace(cast(string)ReplaceTokens.timestamp, timestamp));
                sink.put(line);
            }
        }
    }

    if (loopIteration == 0)
    {
        if (context.translation.powerRestored.length)
        {
            import std.array : replace;

            // No need to go through the whole putMessage rigmarole for this one
            const message = context.translation.powerRestored
                .replace(cast(string)ReplaceTokens.serverName, context.serverName);
            sink.put(message);
        }
        return sink.data;
    }

    if (sortedPeers.justLost.length && context.translation.justLostContactWith.length)
    {
        putMessage(
            context.translation.justLostContactWith,
            sortedPeers.justLost.length);
        putPeerTable(
            sortedPeers.justLost,
            context.translation.lastSeen);
    }

    if (sortedPeers.justReturned.length && context.translation.justRegainedContactWith.length)
    {
        if (sink.data.length) sink.put(string.init);

        putMessage(
            context.translation.justRegainedContactWith,
            sortedPeers.justReturned.length);
        putPeerTable(
            sortedPeers.justReturned,
            context.translation.back);
    }

    if (sortedPeers.stillLost.length && context.translation.stillMissingContactWith.length)
    {
        if (sink.data.length) sink.put(string.init);

        putMessage(
            context.translation.stillMissingContactWith,
            sortedPeers.stillLost.length);
        putPeerTable(
            sortedPeers.stillLost,
            context.translation.lastSeen);
    }

    if (sortedPeers.allPresent && context.translation.nowHasContactWithAll.length)
    {
        /*if (sink.data.length)*/ sink.put(string.init);
        putMessage(
            context.translation.nowHasContactWithAll,
            sortedPeers.stillLost.length);
    }

    return sink.data;
}


public:


// report
/**
    Compiles a report of missing peers and sends a notification via Batsign,
    or by invoking an external command (if defined).

    If this is a dry run, the report is printed to the terminal instead.

    Params:
        context = The context struct.
        sortedPeers = The current state of the Wireguard peers, sorted by connection state.
        loopIteration = The current loop iteration (counter).
 */
auto report(
    const Context context,
    const SortedPeers sortedPeers,
    const size_t loopIteration)
{
    import wg_monitor.cout;
    import wg_monitor.peer : Peer;
    import std.array : join;
    import std.stdio : stdout, writeln;

    static auto getShortPeerRange(const Peer[] peers)
    {
        import wg_monitor.common : shortHashLength;
        import std.algorithm.iteration : joiner, map;

        return peers
            .map!(peer => peer.hash[0..shortHashLength])
            .joiner(", ");
    }

    if (sortedPeers.justLost.length)
    {
        auto range = getShortPeerRange(sortedPeers.justLost);
        printError("just lost: ", range);
    }

    if (sortedPeers.justReturned.length)
    {
        auto range = getShortPeerRange(sortedPeers.justReturned);
        printInfo("just returned: ", range);
    }

    if (sortedPeers.stillLost.length)
    {
        auto range = getShortPeerRange(sortedPeers.stillLost);
        printError("still lost: ", range);
    }

    if (sortedPeers.allPresent)
    {
        printInfo("all present");
    }

    const body_ = composeNotificationBody(context, sortedPeers, loopIteration).join('\n');

    if (context.dryRun)
    {
        if (body_.length)
        {
            writeln(' ');
            writeln(body_);
            writeln(' ');
            stdout.flush();
        }
        return true;
    }

    bool commandSuccess;

    if (context.command.length)
    {
        const result = runCommand(context.command, body_, loopIteration, sortedPeers);
        commandSuccess = (result.status == 0);

        if (commandSuccess)
        {
            printInfo("notification command successful");
            //writeln(result.output.chomp());
            //stdout.flush();
        }
        else /*if (!success)*/
        {
            import std.string : chomp;
            printError("notification command failed with status ", result.status);
            writeln(result.output.chomp());
            stdout.flush();
        }

        // If bothNotificationMethods is set, continue to send a batsign too.
        // Conversely, if it is not set, return here
        if (!context.bothNotificationMethods) return commandSuccess;
    }

    const batsignFailures = sendBatsign(context, body_);

    if (!batsignFailures.length)
    {
        printInfo("notification post successful");
        return context.command.length ?
            commandSuccess :  // bothNotificationMethods is set
            true;
    }

    foreach (const failure; batsignFailures)
    {
        if (failure.exceptionText.length)
        {
            printError("notification post failed: ", failure.exceptionText);
            continue;
        }

        printError("notification post returned status ", failure.code);

        if (failure.code == 404)
        {
            printQuery("is the URL correct?");
        }
        else if (failure.responseBody.length)
        {
            writeln(failure.responseBody);
            stdout.flush();
        }
    }

    return false;
}
