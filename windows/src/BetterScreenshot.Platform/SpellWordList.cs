using System.Runtime.InteropServices;

namespace BetterScreenshot.Platform;

/// <summary>
/// The offline Windows spell checker (<c>ISpellCheckerFactory</c>, Windows 8+) as Capture Text's English word list —
/// the Windows stand-in for the Mac's <c>/usr/share/dict/words</c> (see <see cref="BetterScreenshot.Capture.WordList"/>).
/// Created on first use; null when no English dictionary is installed. Never touches the network.
/// </summary>
public static class SpellWordList
{
    private static readonly object Lock = new();
    private static ISpellChecker? _checker;
    private static bool _tried;

    /// <summary>A lookup for <see cref="BetterScreenshot.Capture.WordList.Lookup"/>, or null when unavailable.</summary>
    public static Func<string, bool>? Create() => Checker() is null ? null : IsWord;

    private static ISpellChecker? Checker()
    {
        lock (Lock)
        {
            if (_tried) return _checker;
            _tried = true;
            try
            {
                var factory = (ISpellCheckerFactory)new SpellCheckerFactoryClass();
                foreach (var tag in new[] { "en-US", "en-GB" })
                {
                    if (factory.IsSupported(tag) != 0) { _checker = factory.CreateSpellChecker(tag); break; }
                }
            }
            catch (Exception ex) when (ex is COMException or InvalidCastException or NotSupportedException)
            {
                _checker = null;
            }
            return _checker;
        }
    }

    private static bool IsWord(string word)
    {
        if (word.Length == 0 || !word.All(char.IsLetter)) return false;
        lock (Lock)
        {
            if (_checker is not { } checker) return false;
            try
            {
                var errors = checker.Check(word);
                return errors.Next(out var error) != 0 || error is null; // S_FALSE: no misspelling
            }
            catch (COMException)
            {
                return false;
            }
        }
    }

    [ComImport, Guid("7AB36653-1796-484B-BDFA-E74F1DB7C1DC")]
    private class SpellCheckerFactoryClass { }

    [ComImport, Guid("8E018A9D-2415-4677-BF08-794EA61F94BB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ISpellCheckerFactory
    {
        [return: MarshalAs(UnmanagedType.Interface)] object SupportedLanguages();
        int IsSupported([MarshalAs(UnmanagedType.LPWStr)] string languageTag);
        ISpellChecker CreateSpellChecker([MarshalAs(UnmanagedType.LPWStr)] string languageTag);
    }

    [ComImport, Guid("B6FD0B71-E2BC-4653-8D05-F197E412770B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ISpellChecker
    {
        [return: MarshalAs(UnmanagedType.LPWStr)] string LanguageTag();
        IEnumSpellingError Check([MarshalAs(UnmanagedType.LPWStr)] string text);
    }

    [ComImport, Guid("803E3BD4-2828-4410-8290-418D1D73C762"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IEnumSpellingError
    {
        [PreserveSig] int Next([MarshalAs(UnmanagedType.Interface)] out object? value);
    }
}
