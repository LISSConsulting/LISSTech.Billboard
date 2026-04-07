using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Documents;

namespace LISSTech.Billboard.Services;

public static class MarkdownParser
{
    // Combined regex: escape sequences first, then bold (**...**), links ([text](url)), italic (*...*), code (`...`)
    private static readonly Regex InlinePattern = new Regex(
        @"\\([*_\[\]()`#|\\])|\*\*(.+?)\*\*|\[([^\]]+)\]\(([^)]+)\)|\*(.+?)\*|`([^`]+)`",
        RegexOptions.Compiled);

    public static IEnumerable<Inline> Parse(string text)
    {
        if (string.IsNullOrEmpty(text))
            yield break;

        int pos = 0;
        foreach (Match match in InlinePattern.Matches(text))
        {
            // Emit plain text before this match
            if (match.Index > pos)
            {
                yield return new Run(text.Substring(pos, match.Index - pos));
            }

            if (match.Groups[1].Success)
            {
                // Escaped character: \* → *, \[ → [, etc.
                yield return new Run(match.Groups[1].Value);
            }
            else if (match.Groups[2].Success)
            {
                // Bold: **...**
                var bold = new Bold();
                bold.Inlines.Add(new Run(match.Groups[2].Value));
                yield return bold;
            }
            else if (match.Groups[3].Success)
            {
                // Link: [text](url)
                var linkText = match.Groups[3].Value;
                var url = match.Groups[4].Value;

                if (!Uri.TryCreate(url, UriKind.Absolute, out var parsedUri) ||
                    (parsedUri.Scheme != "http" && parsedUri.Scheme != "https"))
                {
                    // Malformed or non-HTTP URL — render as plain text
                    yield return new Run(linkText);
                }
                else
                {
                    var hyperlink = new Hyperlink(new Run(linkText))
                    {
                        NavigateUri = parsedUri
                    };
                    hyperlink.RequestNavigate += (sender, e) =>
                    {
                        try
                        {
                            Process.Start(new ProcessStartInfo(e.Uri.AbsoluteUri)
                            {
                                UseShellExecute = true
                            });
                        }
                        catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"Billboard: failed to open URL: {ex.Message}"); }
                        e.Handled = true;
                    };
                    yield return hyperlink;
                }
            }
            else if (match.Groups[5].Success)
            {
                // Italic: *...*
                var italic = new Italic();
                italic.Inlines.Add(new Run(match.Groups[5].Value));
                yield return italic;
            }
            else if (match.Groups[6].Success)
            {
                // Code span: `...`
                var code = new Span(new Run(match.Groups[6].Value))
                {
                    FontFamily = new System.Windows.Media.FontFamily("Consolas, Courier New")
                };
                yield return code;
            }

            pos = match.Index + match.Length;
        }

        // Emit any remaining plain text
        if (pos < text.Length)
        {
            yield return new Run(text.Substring(pos));
        }
    }

    public static IEnumerable<Block> ParseBlocks(string text)
    {
        if (string.IsNullOrEmpty(text))
            yield break;

        var lines = text.Split('\n');
        var paragraphLines = new List<string>();
        List? currentList = null;

        foreach (var rawLine in lines)
        {
            var line = rawLine.TrimEnd('\r');

            if (line.StartsWith("- "))
            {
                // Flush pending paragraph text first
                if (paragraphLines.Count > 0)
                {
                    var paragraph = BuildParagraph(paragraphLines);
                    paragraphLines.Clear();
                    yield return paragraph;
                }

                // Add to bullet list
                if (currentList == null)
                {
                    currentList = new List();
                }

                var itemText = line.Substring(2);
                var listItem = new ListItem(new Paragraph());
                var itemParagraph = (Paragraph)listItem.Blocks.FirstBlock;
                foreach (var inline in Parse(itemText))
                {
                    itemParagraph.Inlines.Add(inline);
                }
                currentList.ListItems.Add(listItem);
            }
            else
            {
                // Flush pending list
                if (currentList != null)
                {
                    yield return currentList;
                    currentList = null;
                }

                // Blank line = paragraph break; flush accumulated lines
                if (string.IsNullOrWhiteSpace(line))
                {
                    if (paragraphLines.Count > 0)
                    {
                        yield return BuildParagraph(paragraphLines);
                        paragraphLines.Clear();
                    }
                }
                else
                {
                    paragraphLines.Add(line);
                }
            }
        }

        // Flush remaining
        if (currentList != null)
        {
            yield return currentList;
        }
        else if (paragraphLines.Count > 0)
        {
            yield return BuildParagraph(paragraphLines);
        }
    }

    private static Paragraph BuildParagraph(List<string> lines)
    {
        var paragraph = new Paragraph();
        var combined = string.Join("\n", lines);
        foreach (var inline in Parse(combined))
        {
            paragraph.Inlines.Add(inline);
        }
        return paragraph;
    }
}
