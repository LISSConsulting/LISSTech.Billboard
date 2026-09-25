using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Documents;

namespace LISSTech.Billboard.Services;

public static class MarkdownParser
{
    // Images are rendered as safe alt text; artwork is loaded only through BillboardConfig.Illustration.
    private static readonly Regex InlinePattern = new Regex(
        @"\\(?<escape>[*_\[\]()`#|\\])|!\[(?<imageAlt>[^\]]*)\]\((?<imageUrl>[^)]+)\)|\*\*(?<bold>.+?)\*\*|\[(?<linkText>[^\]]+)\]\((?<linkUrl>[^)]+)\)|\*(?<italic>.+?)\*|`(?<code>[^`]+)`|(?<autoUrl>https://[^\s<>()\[\]]*[^\s<>()\[\].,;:!?])",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public static IEnumerable<Inline> Parse(string text)
    {
        if (string.IsNullOrEmpty(text))
            yield break;

        int pos = 0;
        foreach (Match match in InlinePattern.Matches(text))
        {
            if (match.Index > pos)
                yield return CreateRun(text.Substring(pos, match.Index - pos));

            if (match.Groups["escape"].Success)
            {
                yield return CreateRun(match.Groups["escape"].Value);
            }
            else if (match.Groups["imageAlt"].Success)
            {
                var alt = match.Groups["imageAlt"].Value.Trim();
                yield return CreateRun(alt.Length == 0 ? "[image]" : $"[Image: {alt}]");
            }
            else if (match.Groups["bold"].Success)
            {
                var bold = new Bold();
                bold.Inlines.Add(CreateRun(match.Groups["bold"].Value));
                yield return bold;
            }
            else if (match.Groups["linkText"].Success)
            {
                yield return CreateLinkOrText(
                    match.Groups["linkText"].Value,
                    match.Groups["linkUrl"].Value);
            }
            else if (match.Groups["italic"].Success)
            {
                var italic = new Italic();
                italic.Inlines.Add(CreateRun(match.Groups["italic"].Value));
                yield return italic;
            }
            else if (match.Groups["code"].Success)
            {
                yield return new Span(CreateRun(match.Groups["code"].Value))
                {
                    FontFamily = new System.Windows.Media.FontFamily("Consolas, Courier New")
                };
            }
            else if (match.Groups["autoUrl"].Success)
            {
                var url = match.Groups["autoUrl"].Value;
                yield return CreateLinkOrText(url, url);
            }

            pos = match.Index + match.Length;
        }

        if (pos < text.Length)
            yield return CreateRun(text.Substring(pos));
    }

    private static Run CreateRun(string text)
    {
        return new Run(text)
        {
            FlowDirection = TextDirectionService.GetFlowDirection(text),
            Language = TextDirectionService.GetLanguage(text)
        };
    }

    private static Inline CreateLinkOrText(string label, string url)
    {
        if (url.Length > 2048 ||
            !Uri.TryCreate(url, UriKind.Absolute, out var parsedUri) ||
            (parsedUri.Scheme != Uri.UriSchemeHttp && parsedUri.Scheme != Uri.UriSchemeHttps) ||
            !string.IsNullOrEmpty(parsedUri.UserInfo))
            return CreateRun(label);

        var hyperlink = new Hyperlink(CreateRun(label))
        {
            NavigateUri = parsedUri,
            ToolTip = parsedUri.Host
        };
        hyperlink.RequestNavigate += (_, e) =>
        {
            try
            {
                Process.Start(new ProcessStartInfo(e.Uri.AbsoluteUri)
                {
                    UseShellExecute = true
                });
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Billboard: failed to open URL: {ex.Message}");
            }
            e.Handled = true;
        };
        return hyperlink;
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
                var listItem = new ListItem(new Paragraph
                {
                    FlowDirection = TextDirectionService.GetFlowDirection(itemText),
                    Language = TextDirectionService.GetLanguage(itemText)
                });
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
        var combined = string.Join("\n", lines);
        var paragraph = new Paragraph
        {
            FlowDirection = TextDirectionService.GetFlowDirection(combined),
            Language = TextDirectionService.GetLanguage(combined)
        };
        foreach (var inline in Parse(combined))
        {
            paragraph.Inlines.Add(inline);
        }
        return paragraph;
    }
}
