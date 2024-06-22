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
        `true` if all notifications were sent successfully; `false` if not.

    See_Also:
        https://batsign.me
 */
auto sendBatsign(const Context context, const string body_)
{
    import lu.conv : toAlpha;

    static string[string] headers;
    headers["Content-Length"] = body_.length.toAlpha();

    /**
        Whether batsigns could be sent to each URL.
        Must begin as true.
     */
    bool success = true;

    /*
        Walk through each Batsign URL and issue a POST request.
        Save failed attempts in `failures` to be returned.
     */
    nextURL:
    foreach (const url; context.batsignURLs)
    {
        import wg_monitor.cout;
        import requests : Request;
        import core.time : seconds;

        static immutable postTimeout = 10.seconds;  // hardcoded

        printInfo("sending notification to ", url);

        auto req = Request();
        //req.verbosity = 1;
        req.keepAlive = false;
        req.timeout = postTimeout;
        req.addHeaders(headers);
        if (context.caBundleFile.length > 0) req.sslSetCaCert(context.caBundleFile);

        enum numRetries = 10;

        foreach (immutable retry; 0..numRetries)
        {
            try
            {
                auto res = req.post(url, body_);

                if ((res.code >= 200) && (res.code < 300))
                {
                    printInfo("post success");
                    //success &= true;  // mark success (no need)
                    continue nextURL;
                }
                else /*if ((res.code < 200) || (res.code >= 300))*/
                {
                    // Unexpected response code
                    printError("post received status ", res.code);

                    if (res.code == 404)
                    {
                        // 404 Not Found
                        printQuery("is the URL correct?");
                        continue nextURL;
                    }
                    else
                    {
                        import std.stdio : stdout, writeln;
                        import std.string : chomp;

                        const responseBody = cast(string)res.responseBody;
                        writeln(responseBody.chomp());
                        stdout.flush();
                    }
                }

                // Drop down to delay
            }
            catch (Exception e)
            {
                // Can't resolve name when connect to batsign.me:443: getaddrinfo error: Temporary failure in name resolution
                // Can't connect to batsign.me:443
                printError("post failed with exception: ", e.msg);
            }

            // Delay before retry unless we're on the last attempt
            if (retry < numRetries-1)
            {
                import core.thread : Thread;
                static immutable retryDelay = 5.seconds;
                Thread.sleep(retryDelay);
            }
            else
            {
                // Last retry
                // Successful cases will have already continued the loop
                // ergo, this is a failure
                printError("notification failed after ", numRetries, " attepmts");
                success = false;
            }
        }
    }

    return success;
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
        `true` if the command executed successfully; `false` if not.
 */
auto runCommand(
    const string executable,
    const string body_,
    const size_t loopIteration,
    const SortedPeers sortedPeers)
{
    import wg_monitor.cout;
    import wg_monitor.peer : Peer;
    import std.conv : to;
    import std.process : execute;

    /**
        Concatenates the hashes of the peers into a single string, separated by spaces.
     */
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

    const result = execute(command[]);
    const success = (result.status == 0);

    if (success)
    {
        printInfo("notification command successful");
        //writeln(result.output.chomp());
        //stdout.flush();
    }
    else /*if (!success)*/
    {
        import std.stdio : stdout, writeln;
        import std.string : chomp;

        printError("notification command failed with status ", result.status);
        writeln(result.output.chomp());
        stdout.flush();
    }

    return success;
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

    /**
        Puts a message into the sink, replacing tokens with the appropriate values.
     */
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

    /**
        Puts a table of peers into the sink, with timestamps, replacing tokens
        with the appropriate values.
     */
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
                const notSeenSinceRestart = context.translation.notSeenSinceRestart
                    .replace(cast(string)ReplaceTokens.serverName, context.serverName);
                const line = pattern.format(
                    getNameFromHash(peer.hash, context.translation.phaseDescription),
                    notSeenSinceRestart);
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
        // First loop; program just started
        if (context.translation.powerRestored.length > 0)
        {
            import std.array : replace;

            // No need to go through the whole of putMessage
            const message = context.translation.powerRestored
                .replace(cast(string)ReplaceTokens.serverName, context.serverName);
            sink.put(message);
        }
        return sink.data;
    }

    if ((sortedPeers.justLost.length > 0) && (context.translation.justLostContactWith.length > 0))
    {
        // Some peers were just lost
        putMessage(
            context.translation.justLostContactWith,
            sortedPeers.justLost.length);
        putPeerTable(
            sortedPeers.justLost,
            context.translation.lastSeen);
    }

    if ((sortedPeers.justReturned.length > 0) && (context.translation.justRegainedContactWith.length > 0))
    {
        // Some peers just returned
        if (sink.data.length > 0) sink.put(string.init);

        putMessage(
            context.translation.justRegainedContactWith,
            sortedPeers.justReturned.length);
        putPeerTable(
            sortedPeers.justReturned,
            context.translation.back);
    }

    if ((sortedPeers.stillLost.length > 0) && (context.translation.stillMissingContactWith.length > 0))
    {
        // Some peers are still lost
        if (sink.data.length > 0) sink.put(string.init);

        putMessage(
            context.translation.stillMissingContactWith,
            sortedPeers.stillLost.length);
        putPeerTable(
            sortedPeers.stillLost,
            context.translation.lastSeen);
    }

    if (sortedPeers.allPresent && (context.translation.nowHasContactWithAll.length > 0))
    {
        // All are present
        /*if (sink.data.length > 0)*/ sink.put(string.init);  // at least one returned, sink cannot be empty
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

    Returns:
        `true` if all notifications were sent successfully; `false` if not.
 */
auto report(
    const Context context,
    const SortedPeers sortedPeers,
    const size_t loopIteration)
{
    import wg_monitor.cout;
    import wg_monitor.peer : Peer;
    import std.array : join, replace;
    import std.conv : text;
    import std.stdio : stdout, writeln;

    /**
        Formats an array of peers into a comma-separated range of shortened hashes.
     */
    static auto getShortPeerRange(const Peer[] peers)
    {
        import wg_monitor.common : shortHashLength;
        import std.algorithm.iteration : joiner, map;

        return peers
            .map!(peer => peer.hash[0..shortHashLength])
            .joiner(", ");
    }

    if (sortedPeers.justLost.length > 0)
    {
        auto range = getShortPeerRange(sortedPeers.justLost);
        printError("just lost: ", range);
    }

    if (sortedPeers.justReturned.length > 0)
    {
        auto range = getShortPeerRange(sortedPeers.justReturned);
        printInfo("just returned: ", range);
    }

    if (sortedPeers.stillLost.length > 0)
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
        // Dry run, so print the notification to the terminal instead
        if (body_.length > 0)
        {
            writeln(' ');
            writeln(body_);
            writeln(' ');
            stdout.flush();
        }
        return true;
    }

    bool commandSuccess;

    if (context.command.length > 0)
    {
        commandSuccess = runCommand(context.command, body_, loopIteration, sortedPeers);
        if (!context.bothNotificationMethods) return commandSuccess;
    }

    const subject = context.translation.subject.replace("$serverName", context.serverName);
    const subjectedBody = text("Subject: ", subject, '\n', body_);
    const batsignSuccess = sendBatsign(context, subjectedBody);

    return (context.command.length > 0) ?
        (batsignSuccess && commandSuccess) :  // bothNotificationMethods is set or we wouldn't be here
        batsignSuccess;
}
