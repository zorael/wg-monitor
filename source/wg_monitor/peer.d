/**
    Peer representations and operations.

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor.peer;

public:


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
        Whether or not the peer has never been seen before.
     */
    bool wasNeverSeen;

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
        All peers that are currently present and have been so for at least one
        cycle, unless the program was just started, in which case all present
        peers are considered to be present.
     */
    Peer[] present;

    /**
        All peers that are considered to have been lost for at least one cycle.
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
        Whether or not all peers are present, including those that just returned.

        Returns:
            `true` if all peers are present; `false` otherwise.
     */
    auto allPresent() const
    {
        return ((this.stillLost.length == 0) && (this.justLost.length == 0));
    }

    /**
        Constructor. Sorts the peers into the five arrays, one for each [Peer.State|State].

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

            case Peer.State.unset:
                // Not in the peer list, ignore
                break;
            }
        }

        alias pred = (Peer a, Peer b) => a.hash.lessThan(b.hash);

        if (this.present.length > 0) this.present = this.present.sort!pred.release();
        if (this.justReturned.length > 0) this.justReturned = this.justReturned.sort!pred.release();
        if (this.stillLost.length > 0) this.stillLost = this.stillLost.sort!pred.release();
        if (this.justLost.length > 0) this.justLost = this.justLost.sort!pred.release();
    }
}


// step
/**
    Steps a peer's state, advancing it (in terms of a handshake cycle).

    Params:
        peer = The peer to step the state of.
        timedOut = Whether or not the peer has a handshake whose timestamp is
            above the timeout.

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
            // Became lost last cycle, still lost
            peer.state = stillLost;
            break;

        case unset:
            // Program startup
            peer.state = stillLost;
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
                /*
                    These have to match the tokens used in the translations.txt file.
                 */
                enum ReplaceTokens
                {
                    phaseName = "$phaseName",
                    phaseNumber = "$phaseNumber",
                }

                return this.phaseDescriptionPattern
                    .replace(cast(string)ReplaceTokens.phaseName, this.name.capitalize())
                    .replace(cast(string)ReplaceTokens.phaseNumber, this.phase.to!string);
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

        if ((slice.length > 0) && slice[0].isDigit)
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
    else
    {
        import std.typecons : Flag, No, Yes;
        peerRep.name = slice.advancePast('/', Yes.inherit);
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
        {
            enum hash = "Nian//A7bVbTv2OVM3jzx2PeHw7EldrkyB8tkz31Oi0=";
            const peer = getNameFromHash(hash, string.init);
            assert((peer.name == "Nian"), peer.name);
            assert(!peer.phase, peer.phase.to!string);
        }
    }
}
