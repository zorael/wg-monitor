/**
    Common things that don't fit anywhere else.

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor.common;

public:


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


// NeedSudoException
/**
    Exception thrown when a command fails due to lack of permissions.

    This is used instead of a normal [object.Exception|Exception] so as not to
    rely on magic strings to discern the cause of a failure.
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

    Embeds the string name of the missing interface.

    This is used instead of a normal [object.Exception|Exception] so as not to
    rely on magic strings to discern the cause of a failure.
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

    This is used instead of a normal [object.Exception|Exception] so as not to
    rely on magic strings to discern the cause of a failure.
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


// ShellReturnValue
/**
    Return values for the program.

    See_Also:
        https://tldp.org/LDP/abs/html/exitcodes.html
        https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#Process%20Exit%20Codes
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
    getoptFailure = 8,

    /**
        A generic exception was thrown.
     */
    exception = 9,

    /**
        A Batsign and/or peer file was missing.
     */
    missingFiles = 10,

    /**
        An invalid language was specified.
     */
    invalidLanguage = 11,

    /**
        Notification command not found.
     */
    commandNotFound = 12,

    /**
        Network error.
     */
    networkError = 13,

    /**
        Some other error occurred with regards to permissions.
     */
    otherPermissionsError = 14,
}
