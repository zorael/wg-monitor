/**
    Some common stuff.

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
        A generic exception was thrown.
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

    /**
        Some other error occurred with regards to permissions.
     */
    otherPermissionsError = 8,
}
