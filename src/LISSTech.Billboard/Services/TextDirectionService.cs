using System.Globalization;
using System.Windows;
using System.Windows.Markup;

namespace LISSTech.Billboard.Services;

internal static class TextDirectionService
{
    private static readonly XmlLanguage ArabicLanguage = XmlLanguage.GetLanguage("ar-SA");
    private static readonly XmlLanguage HebrewLanguage = XmlLanguage.GetLanguage("he-IL");
    private static readonly XmlLanguage DefaultLanguage = XmlLanguage.GetLanguage("en-US");

    internal static FlowDirection GetFlowDirection(string? text)
    {
        if (string.IsNullOrEmpty(text))
            return FlowDirection.LeftToRight;

        foreach (var character in text!)
        {
            if (IsRightToLeft(character))
                return FlowDirection.RightToLeft;

            var category = char.GetUnicodeCategory(character);
            if (category is UnicodeCategory.UppercaseLetter or
                UnicodeCategory.LowercaseLetter or
                UnicodeCategory.TitlecaseLetter or
                UnicodeCategory.ModifierLetter or
                UnicodeCategory.OtherLetter)
                return FlowDirection.LeftToRight;
        }

        return FlowDirection.LeftToRight;
    }

    internal static XmlLanguage GetLanguage(string? text)
    {
        if (string.IsNullOrEmpty(text))
            return DefaultLanguage;

        foreach (var character in text!)
        {
            if (character >= '\u0590' && character <= '\u05FF')
                return HebrewLanguage;
            if (IsArabic(character))
                return ArabicLanguage;
        }

        return DefaultLanguage;
    }

    private static bool IsRightToLeft(char character) =>
        (character >= '\u0590' && character <= '\u08FF') ||
        (character >= '\uFB1D' && character <= '\uFDFF') ||
        (character >= '\uFE70' && character <= '\uFEFF');

    private static bool IsArabic(char character) =>
        (character >= '\u0600' && character <= '\u08FF') ||
        (character >= '\uFB50' && character <= '\uFDFF') ||
        (character >= '\uFE70' && character <= '\uFEFF');
}
