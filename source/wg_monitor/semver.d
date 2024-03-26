/**
    SemVer information about the current release.

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor.semver;

public:


// WgMonitorSemVer
/**
    SemVer versioning of this build.
 */
enum WgMonitorSemVer
{
    /**
        SemVer major version of the program.
     */
    major = 0,

    /**
        SemVer minor version of the program.
     */
    minor = 0,

    /**
        SemVer patch version of the program.
     */
    patch = 2,
}


// WgMonitorSemVerPreRelease
/**
    SemVer pre-release string of this build.
 */
enum WgMonitorSemVerPreRelease = string.init;
