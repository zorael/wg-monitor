/**
    Terminal output functions.

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor.cout;

public:


// printProgramVersion
/**
    Prints the program version.
 */
void printProgramVersion() @safe
{
    import wg_monitor.semver : WgMonitorSemVer, WgMonitorSemVerPreRelease;
    import std.stdio : writefln, writeln;

    enum sourceURL = "https://github.com/zorael/wg-monitor";

    alias v = WgMonitorSemVer;
    alias vPre = WgMonitorSemVerPreRelease;
    enum pre = vPre.length ? "-" ~ vPre : string.init;

    writefln("wireguard monitor v%d.%d.%d%s | copyright 2024 jr", v.major, v.minor, v.patch, pre);
    writeln("$ git clone " ~ sourceURL ~ ".git");
}


// printImpl
/**
    Internal function for printing messages to the terminal.

    Params:
        sign = The character to prefix the message with (inside brackets).
        args = The variadic arguments to print.
 */
void printImpl(Args...)(const char sign, const Args args)
{
    import std.stdio : stdout, writeln;
    writeln('[', sign, "] ", args);
    stdout.flush();
}


// printInfo
/**
    Prints information messages to the terminal.

    Params:
        args = The variadic arguments to print.

    See_Also:
        [printImpl]
 */
void printInfo(Args...)(const Args args)
{
    printImpl('+', args);
}


// printQuery
/**
    Prints query messages to the terminal.

    Params:
        args = The variadic arguments to print.

    See_Also:
        [printImpl]
 */
void printQuery(Args...)(const Args args)
{
    printImpl('?', args);
}


// printError
/**
    Prints error messages to the terminal.

    Params:
        args = The variadic arguments to print.

    See_Also:
        [printImpl]
 */
void printError(Args...)(const Args args)
{
    printImpl('!', args);
}


// printIndented
/**
    Prints messages to the terminal, indented by four spaces.

    Params:
        args = The variadic arguments to print.
 */
void printIndented(Args...)(const Args args)
{
    import std.stdio : stdout, writeln;
    writeln("    ", args);
    stdout.flush();
}
