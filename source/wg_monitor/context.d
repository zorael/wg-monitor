/**
    Context struct, used to aggregate state and configuration.

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor.context;

public:


// Context
/**
    Context struct.
 */
struct Context
{
private:
    import wg_monitor.translation : Translation;

    /**
        Default language to use for notifications.

        This is the language used if no language is specified with the `-l` flag.
        Must be one of the languages in
        [wg_monitor.translation.allTranslations|allTranslations], and thus one
        of the languages in `translations.txt`.

        See_Also:
            [wg_monitor.translation.allTranslations]
            `translations.txt` in the project root.
     */
    enum defaultLanguage = "english";

public:
    /**
        Aggregate of durations used in the program.

        These are just defaults and may be overridden with getopt flags.
     */
    static struct Durations
    {
        import core.time : Duration, hours, minutes, seconds;

        /**
            A peer is considered lost after this amount of time has passed
            since the last successful Wireguard handshake.
         */
        Duration peerTimeout = 10.minutes;

        /**
            How long to sleep between Wireguard handshake attempts.
         */
        Duration sleepBetweenChecks = 1.minutes;

        /**
            How long to wait before repeating a notification, even if there were
            no new peers lost or returned.
         */
        Duration reminderPeriodicity = 6.hours;
    }

    /**
        Wireguard interface name.
     */
    string iface;

    /**
        Filename of the Batsign URL file.

        See_Also:
            [batsignURLs]
            [wg_monitor.config.parseBatsignFile]
            [wg_monitor.reporting.sendBatsign]
            https://batsign.me
     */
    string batsignFile = "batsign.url";

    /**
        Batsign URLs parsed from [batsignFile].

        See_Also:
            [batsignFile]
            [wg_monitor.config.parseBatsignFile]
            [wg_monitor.reporting.sendBatsign]
            https://batsign.me
     */
    string[] batsignURLs;

    /**
        Filename of file of Wireguard peer hashes.

        See_Also:
            [wg_monitor.peer.Peer]
            [peerList]
            [wg_monitor.config.parsePeerFile]
     */
    string peerFile = "peers.list";

    /**
        Custom command to run to send notifications, instead of using Batsign.

        If this is set, [batsignFile] and [batsignURLs] are ignored.

        The command will be fed six string arguments. See the `README.md` file
        for more information.
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
        [wg_monitor.translation.allTranslations|allTranslations], and thus one
        of the languages in `translations.txt`.

        See_Also:
            [wg_monitor.translation.allTranslations]
            `translations.txt` in the project root.
     */
    string language = defaultLanguage;

    /**
        Translation strings for the current language.

        See_Also:
            [wg_monitor.translation.Translation]
            [wg_monitor.translation.allTranslations]
     */
    Translation translation;

    /**
        Associative array of peer hashes.

        See_Also:
            [wg_monitor.peer.Peer]
            [peerFile]
            [wg_monitor.config.parsePeerFile]
     */
    bool[string] peerList;

    /**
        Hostname to use in notifications.
     */
    string hostname; // = Socket.hostName;  // must naturally be set at runtime

    /**
        Whether or not to print verbose progress messages.
     */
    bool progress = true;

    /**
        Whether or not to perform a dry run; to not actually send any notifications.
     */
    bool dryRun = false;

    /**
        Whether to wait for a Wireguard interface to show up, or to abort and
        exit if it doesn't exist during start-up.
     */
    bool waitForInterface = false;

    /**
        Whether or not the program was re-executed with `exec`. Used internally.
     */
    bool reexecuted = false;

    /**
        Whether or not to show the version string and exit immediately.
     */
    bool showVersionAndExit = false;

    /**
        Whether or not to use both Batsign and the custom command for notifications.

        If this is set, both methods are used. If not, the custom command is
        used if defined, and Batsign otherwise.
     */
    bool bothNotificationMethods = false;
}
