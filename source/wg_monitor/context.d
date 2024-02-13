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
    import core.time : Duration, hours, minutes, seconds;

    /**
        Default language to use for notifications.

        This is the language used if no language is specified with the `-l` flag.
        It must be one of the languages in [allTranslations], and thus one of the
        languages in `translations.txt`.

        See_Also:
            [allTranslations]

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
    string language = defaultLanguage;

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
    bool skipIntro = false;

    /**
        Whether or not to perform a dry run.
     */
    bool dryRun = false;

    /**
        Whether to wait for a Wireguard interface to show up, or to abotr and
        exit if it doesn't exist during start-up.
     */
    bool waitForInterface = false;

    /**
        Whether or not the program was re-executed with `exec`.
     */
    bool reexecuted = false;
}
