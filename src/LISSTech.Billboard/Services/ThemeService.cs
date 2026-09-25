using LISSTech.Billboard.Models;

namespace LISSTech.Billboard.Services;

internal static class ThemeService
{
    internal static ThemeMode Resolve(ThemeMode requested, bool systemUsesDarkTheme)
    {
        return requested == ThemeMode.Auto
            ? systemUsesDarkTheme ? ThemeMode.Dark : ThemeMode.Light
            : requested;
    }

    internal static bool IsDark(ThemeMode theme) =>
        theme is ThemeMode.Dark or ThemeMode.StarryNight or ThemeMode.GreatWave;

    internal static bool IsArtistic(ThemeMode theme) =>
        theme is ThemeMode.StarryNight or ThemeMode.WaterLilies or ThemeMode.GreatWave;

    internal static string ContrastVariant(ThemeMode theme) => IsDark(theme) ? "Dark" : "Light";
}
