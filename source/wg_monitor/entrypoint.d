/++
    Dummy file so the real [wg_monitor.main] gets tested by dub.
 +/
module wg_monitor.entrypoint;

public:


// main
/++
    Entrypoint.

    Params:
        args = Command line arguments passed to the program.

    Returns:
        `0` on success, non-`0` on failure, as [wg_monitor.main.run] returns.

    See_Also:
        [wg_monitor.main.ShellReturnValue]
 +/
auto main(string[] args)
{
    import wg_monitor.main : run;
    return int(run(args));
}
