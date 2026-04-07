using System.Linq;
using System.Windows.Documents;
using LISSTech.Billboard.Services;
using Xunit;

namespace Billboard.Tests;

public class MarkdownParserTests
{
    [StaFact]
    public void Parse_PlainText_ReturnsSingleRun()
    {
        var inlines = MarkdownParser.Parse("Hello world").ToList();
        Assert.Single(inlines);
        Assert.IsType<Run>(inlines[0]);
        Assert.Equal("Hello world", ((Run)inlines[0]).Text);
    }

    [StaFact]
    public void Parse_Bold_ReturnsBoldRun()
    {
        var inlines = MarkdownParser.Parse("Hello **world**").ToList();
        Assert.Equal(2, inlines.Count);
        Assert.Equal("Hello ", ((Run)inlines[0]).Text);
        var bold = (Bold)inlines[1];
        Assert.Equal("world", ((Run)bold.Inlines.First()).Text);
    }

    [StaFact]
    public void Parse_Italic_ReturnsItalicRun()
    {
        var inlines = MarkdownParser.Parse("Hello *world*").ToList();
        Assert.Equal(2, inlines.Count);
        var italic = (Italic)inlines[1];
        Assert.Equal("world", ((Run)italic.Inlines.First()).Text);
    }

    [StaFact]
    public void Parse_Link_ReturnsHyperlink()
    {
        var inlines = MarkdownParser.Parse("Visit [LISS](https://lisstech.com)").ToList();
        Assert.Equal(2, inlines.Count);
        var link = (Hyperlink)inlines[1];
        Assert.Equal("https://lisstech.com", link.NavigateUri.OriginalString);
        Assert.Equal("LISS", ((Run)link.Inlines.First()).Text);
    }

    [StaFact]
    public void Parse_CodeSpan_ReturnsMonospaceSpan()
    {
        var inlines = MarkdownParser.Parse("Check `code.exe` here").ToList();
        Assert.Equal(3, inlines.Count);
        Assert.Equal("Check ", ((Run)inlines[0]).Text);
        var code = Assert.IsType<Span>(inlines[1]);
        Assert.Equal("code.exe", ((Run)code.Inlines.First()).Text);
        Assert.Equal("Consolas, Courier New", code.FontFamily.Source);
        Assert.Equal(" here", ((Run)inlines[2]).Text);
    }

    [StaFact]
    public void ParseBlocks_BulletList_ReturnsParagraphAndList()
    {
        var text = "Items:\n- First\n- Second\n- Third";
        var blocks = MarkdownParser.ParseBlocks(text).ToList();
        Assert.True(blocks.Count >= 2);
        Assert.IsType<List>(blocks[1]);
        var list = (List)blocks[1];
        Assert.Equal(3, list.ListItems.Count);
    }

    [StaFact]
    public void ParseBlocks_BlankLineSeparation_ProducesTwoParagraphs()
    {
        var text = "First paragraph\n\nSecond paragraph";
        var blocks = MarkdownParser.ParseBlocks(text).ToList();
        Assert.Equal(2, blocks.Count);
        Assert.IsType<Paragraph>(blocks[0]);
        Assert.IsType<Paragraph>(blocks[1]);
    }

    [StaFact]
    public void ParseBlocks_MultipleBlankLines_ProducesOneParagraphPerSegment()
    {
        var text = "Alpha\n\n\nBeta";
        var blocks = MarkdownParser.ParseBlocks(text).ToList();
        Assert.Equal(2, blocks.Count);
        Assert.IsType<Paragraph>(blocks[0]);
        Assert.IsType<Paragraph>(blocks[1]);
    }

    [StaFact]
    public void Parse_EscapedAsterisk_RendersLiteral()
    {
        var inlines = MarkdownParser.Parse(@"not \*italic\*").ToList();
        // Should be: "not ", "*", "italic", "*" — all plain Runs, no Italic
        Assert.All(inlines, i => Assert.IsType<Run>(i));
        var text = string.Concat(inlines.OfType<Run>().Select(r => r.Text));
        Assert.Equal("not *italic*", text);
    }

    [StaFact]
    public void Parse_EscapedBacktick_RendersLiteral()
    {
        var inlines = MarkdownParser.Parse(@"price \`5\`").ToList();
        Assert.All(inlines, i => Assert.IsType<Run>(i));
        var text = string.Concat(inlines.OfType<Run>().Select(r => r.Text));
        Assert.Equal("price `5`", text);
    }

    [StaFact]
    public void Parse_EscapedBracket_RendersLiteral()
    {
        var inlines = MarkdownParser.Parse(@"\[not a link\]").ToList();
        Assert.All(inlines, i => Assert.IsType<Run>(i));
        var text = string.Concat(inlines.OfType<Run>().Select(r => r.Text));
        Assert.Equal("[not a link]", text);
    }

    [StaFact]
    public void Parse_EscapedBackslash_RendersLiteral()
    {
        var inlines = MarkdownParser.Parse(@"path\\file").ToList();
        Assert.All(inlines, i => Assert.IsType<Run>(i));
        var text = string.Concat(inlines.OfType<Run>().Select(r => r.Text));
        Assert.Equal(@"path\file", text);
    }

    [StaFact]
    public void Parse_EmptyString_ReturnsEmpty()
    {
        var inlines = MarkdownParser.Parse("").ToList();
        Assert.Empty(inlines);
    }

    [StaFact]
    public void ParseBlocks_EmptyString_ReturnsEmpty()
    {
        var blocks = MarkdownParser.ParseBlocks("").ToList();
        Assert.Empty(blocks);
    }

    [StaFact]
    public void Parse_MalformedUrl_RendersLinkTextAsPlainText()
    {
        // ftp:// is not http/https — should render as plain text, not a hyperlink
        var inlines = MarkdownParser.Parse("[click here](ftp://invalid.com)").ToList();
        Assert.Single(inlines);
        Assert.IsType<Run>(inlines[0]);
        Assert.Equal("click here", ((Run)inlines[0]).Text);
    }

    [StaFact]
    public void ParseBlocks_ListBetweenParagraphs_ProducesThreeBlocks()
    {
        var text = "Before list\n- Item 1\n- Item 2\nAfter list";
        var blocks = MarkdownParser.ParseBlocks(text).ToList();
        Assert.Equal(3, blocks.Count);
        Assert.IsType<Paragraph>(blocks[0]);
        Assert.IsType<List>(blocks[1]);
        Assert.IsType<Paragraph>(blocks[2]);
    }

    [StaFact]
    public void ParseBlocks_ListItemWithBold_RendersBoldInline()
    {
        var text = "- **important** item";
        var blocks = MarkdownParser.ParseBlocks(text).ToList();
        Assert.Single(blocks);
        var list = Assert.IsType<List>(blocks[0]);
        Assert.Single(list.ListItems);
        var itemParagraph = (Paragraph)list.ListItems.Cast<ListItem>().First().Blocks.FirstBlock;
        // Should contain a Bold inline, not just a plain Run
        Assert.Contains(itemParagraph.Inlines, i => i is Bold);
    }

    [StaFact]
    public void ParseBlocks_ListItemWithCode_RendersMonospaceSpan()
    {
        var text = "- Run `setup.exe` first";
        var blocks = MarkdownParser.ParseBlocks(text).ToList();
        var list = Assert.IsType<List>(blocks[0]);
        var itemParagraph = (Paragraph)list.ListItems.Cast<ListItem>().First().Blocks.FirstBlock;
        // Should contain a Span (code) inline
        Assert.Contains(itemParagraph.Inlines, i => i is Span span &&
            span.FontFamily.Source == "Consolas, Courier New");
    }

    [StaFact]
    public void ParseBlocks_ListItemWithLink_RendersHyperlink()
    {
        var text = "- Visit [docs](https://docs.example.com) for more";
        var blocks = MarkdownParser.ParseBlocks(text).ToList();
        var list = Assert.IsType<List>(blocks[0]);
        var itemParagraph = (Paragraph)list.ListItems.Cast<ListItem>().First().Blocks.FirstBlock;
        Assert.Contains(itemParagraph.Inlines, i => i is Hyperlink);
    }

    [StaFact]
    public void Parse_ConsecutiveBoldAndItalic_RendersBothElements()
    {
        var inlines = MarkdownParser.Parse("**bold** and *italic*").ToList();
        // Expect: Bold, Run(" and "), Italic
        Assert.Equal(3, inlines.Count);
        Assert.IsType<Bold>(inlines[0]);
        Assert.IsType<Run>(inlines[1]);
        Assert.Equal(" and ", ((Run)inlines[1]).Text);
        Assert.IsType<Italic>(inlines[2]);
    }

    [StaFact]
    public void Parse_BoldCodeAndPlainText_RendersAllElements()
    {
        // "**bold** then `code` done" → Bold, Run(" then "), Span("code"), Run(" done")
        var inlines = MarkdownParser.Parse("**bold** then `code` done").ToList();
        Assert.Equal(4, inlines.Count);
        Assert.IsType<Bold>(inlines[0]);
        Assert.Equal(" then ", ((Run)inlines[1]).Text);
        Assert.IsType<Span>(inlines[2]);
        Assert.Equal(" done", ((Run)inlines[3]).Text);
    }

    [StaFact]
    public void Parse_LinkFollowedByText_RendersHyperlinkAndRun()
    {
        var inlines = MarkdownParser.Parse("See [here](https://example.com) for details").ToList();
        Assert.Equal(3, inlines.Count);
        Assert.Equal("See ", ((Run)inlines[0]).Text);
        Assert.IsType<Hyperlink>(inlines[1]);
        Assert.Equal(" for details", ((Run)inlines[2]).Text);
    }
}
