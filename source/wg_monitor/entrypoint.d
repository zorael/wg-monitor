/**
    Dummy file so the real [wg_monitor.main] gets tested by dub.

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor.entrypoint;

public:


// main
/**
    Entrypoint.

    Params:
        args = Command line arguments passed to the program.

    Returns:
        `0` on success, non-`0` on failure, as [wg_monitor.main.run] returns.
        If it instead throws and doesn't internally catch the exception,
        [wg_monitor.common.ShellReturnValue.exception|ShellReturnValue.exception]
        is returned.

    See_Also:
        [wg_monitor.common.ShellReturnValue]
 */
int main(string[] args)
{
    try
    {
        import wg_monitor.main : run;
        return int(run(args));
    }
    catch (Exception e)
    {
        import wg_monitor.common : ShellReturnValue;
        import std.stdio : writeln;

        writeln("[!] ", e.msg);
        return ShellReturnValue.exception;
    }
}
