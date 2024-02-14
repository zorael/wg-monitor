/**
    Translation bits.

    Copyright: [JR](https://github.com/zorael)
    License: [Boost Software License 1.0](https://www.boost.org/users/license.html)

    Authors:
        [JR](https://github.com/zorael)
 */
module wg_monitor.translation;

public:


// Translation
/**
    Translation strings for a language.

    String members should have a default value that refers to itself, to make
    it easier to spot missing translations. The exception being
    [Translation.language|language], which should have an empty default value.
 */
struct Translation
{
    /**
        Language name.
     */
    string language = string.init;

    /**
        Translation for "peer", in singular form.
     */
    string peerSingular = "peerSingular";

    /**
        Translation for "peer", in plural form.
     */
    string peerPlural = "peerPlural";

    /**
        Translation for the string used to describe a phase.
     */
    string phaseDescription = "phaseDescription";

    /**
        Translation for the string used when power has been restored but there
        were peers lost.
     */
    string powerBackAndContactLostWith = "powerBackAndContactLostWith";

    /**
        Translation for the string used when contact was just lost with a number
        of peers.
     */
    string justLostContactWith = "justLostContactWith";

    /**
        Translation for the string used when contact was just regained with a
        number of peers.
     */
    string justRegainedContactWith = "justRegainedContactWith";

    /**
        Translation for the string used when contact is still missing with a
        number of peers.
     */
    string stillMissingContactWith = "stillMissingContactWith";

    /**
        Translation for the string used when a peer hasn't been seen since the
        program was started.
     */
    string notSeenSinceRestart = "notSeenSinceRestart";

    /**
        Translation for the string used along with a timestamp when a peer was
        last seen. Inserted before the timestamp.
     */
    string lastSeenPre = "lastSeenPre";

    /**
        Translation for the string used along with a timestamp when a peer was
        last seen. Inserted after the timestamp.
     */
    string lastSeenPost = "lastSeenPost";

    /**
        Translation for the string used along with a timestamp when a peer has
        returned. Inserted before the timestamp.
     */
    string backPre = "backPre";

    /**
        Translation for the string used along with a timestamp when a peer has
        returned. Inserted after the timestamp.
     */
    string backPost = "backPost";

    /**
        Translation for the string used when all peers are present.
     */
    string nowHasContactWithAll = "nowHasContactWithAll";

    /**
        Inherits lines from the translations statically imported (and parsed)
        from the `translations.txt` file.

        Params:
            language = The language to inherit lines for.

        Returns:
            `true` if the specified language was found; `false` otherwise.

        See_Also:
            [allTranslations]
            `translations.txt` in the project root.
     */
    auto inherit(const string language)
    {
        foreach (const translation; .allTranslations)
        {
            if (translation.language == language)
            {
                this = translation;
                return true;
            }
        }

        return false;
    }
}


// allTranslations
/**
    Translations statically imported from the `translations.txt` file.

    See_Also:
        [Translation]
        [allTranslationLanguageNames]
        `translations.txt` in the project root.
 */
static immutable allTranslations = ()
{
    import std.algorithm.iteration : splitter;

    enum translationsOnFile = cast(string)import("translations.txt");

    Translation[] translations;
    auto translationRange = translationsOnFile.splitter("\n\n");

    foreach (const translationEntry; translationRange)
    {
        auto lineRange = translationEntry.splitter('\n');
        Translation translation;
        uint i;

        foreach (const line; lineRange)
        {
            import lu.string : AdvanceException, advancePast, stripped;
            import lu.objmanip : setMemberByName;
            import std.format : format;

            ++i;

            string slice = line.stripped;  // mutable
            if (!slice.length || (slice[0] == '#')) continue;

            try
            {
                const key = slice.advancePast('=');
                const success = translation.setMemberByName(key, slice);

                if (!success)
                {
                    enum pattern = `Translation error (%s) unknown key on %d:"%s"`;
                    const message = pattern.format(translation.language, i, key);
                    assert(0, message);
                }
            }
            catch (AdvanceException e)
            {
                enum pattern = `Translation error (%s) possibly missing '=' on %d:"%s"`;
                const message = pattern.format(translation.language, i, slice);
                assert(0, message);
            }
            catch (Exception e)
            {
                enum pattern = `Translation error (%s) generic exception on %d:"%s"`;
                const message = pattern.format(translation.language, i, slice);
                assert(0, message);
            }
        }

        if (translation.language.length) translations ~= translation;
    }

    return translations;
}();


// allTranslationLanguageNames
/**
    Array of the names of all languages found in `translations.txt`.

    See_Also:
        [Translation]
        [allTranslations]
        `translations.txt` in the project root.
 */
static immutable allTranslationLanguageNames =
{
    string[] languageNames;

    foreach (const translation; .allTranslations)
    {
        if (translation.language == "debug") continue;  // omit debug language from list
        languageNames ~= translation.language;
    }

    return languageNames;
}();
