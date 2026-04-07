using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using LISSTech.Billboard.Models;

namespace LISSTech.Billboard.Services;

public static class CliParser
{
    private static T ParseEnum<T>(string value, string fieldName) where T : struct, Enum
    {
        if (!Enum.TryParse<T>(value, ignoreCase: true, out var result))
        {
            var valid = string.Join(", ", Enum.GetNames(typeof(T)).Select(n => n.ToLowerInvariant()));
            throw new ArgumentException($"Invalid {fieldName} '{value}'. Valid values are: {valid}.");
        }
        return result;
    }

    public static bool IsHelpRequested(string[] args)
    {
        if (args.Length == 0) return true;
        foreach (var arg in args)
        {
            if (arg is "--help" or "-h" or "-?" or "/?" or "help")
                return true;
        }
        return false;
    }

    public static string GetUsage()
    {
        return """
            Billboard — LISSTech notification system

            USAGE:
              Billboard.exe --type <type> --title <text> --message <text> [options]
              Billboard.exe --json < config.json

            REQUIRED:
              --type <type>        info, warn, alert, critical, question
              --title <text>       Heading text
              --message <text>     Body text (supports **bold**, *italic*, - bullets, [links](url))

            OPTIONS:
              --timeout <seconds>  Auto-dismiss (default: 10s info/warn, 15s alert, 0 critical/question)
              --modal              Show as centered modal instead of bottom-right toast
              --theme <theme>      auto (default), light, dark
              --pipe <name>        Named pipe for IPC result (JSON)
              --buttons <spec>     Semicolon-separated Label:value:style (style: primary, danger, ghost)
              --illustration <name> Illustration name (default: auto per type; "none" to disable)
              --msp-name <text>    MSP/organization name woven into context footer
              --msp-logo <path>   Logo image file path or URL (PNG, JPG, ICO)
              --json               Read config from stdin as JSON
              --help               Show this help

            EXAMPLES:
              Billboard.exe --type info --title "Update" --message "New version available"
              Billboard.exe --type critical --title "Alert" --message "Account locked" --modal
              Billboard.exe --type question --title "Restart?" --message "Save work" \
                --buttons "Restart Now:restart:primary;Later:defer:ghost" --modal --pipe Billboard.abc123

            EXIT CODES:
              0    Button clicked
              1    Dismissed (close button or backdrop click)
              2    Timed out
              100  Error

            LISS Technologies — https://lisstech.com
            """;
    }

    public static BillboardConfig Parse(string[] args, System.IO.TextReader? stdinReader = null)
    {
        var flags = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
        var boolFlags = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        for (int i = 0; i < args.Length; i++)
        {
            if (!args[i].StartsWith("--"))
                continue;

            var key = args[i].Substring(2);
            if (i + 1 < args.Length && !args[i + 1].StartsWith("--"))
            {
                flags[key] = args[i + 1];
                i++;
            }
            else
            {
                boolFlags.Add(key);
                flags[key] = null;
            }
        }

        NotificationType? type = null;
        string? title = null;
        string? message = null;
        int? timeout = null;
        bool modal = false;
        ThemeMode theme = ThemeMode.Auto;
        string? pipeName = null;
        List<ButtonDefinition> buttons = new();
        string? illustration = null;
        string? mspName = null;
        string? mspLogo = null;

        if (boolFlags.Contains("json") || flags.ContainsKey("json"))
        {
            var reader = stdinReader ?? Console.In;
            if (stdinReader == null && !Console.IsInputRedirected)
                throw new ArgumentException("--json requires input to be piped via stdin (e.g., Billboard.exe --json < config.json).");

            var json = reader.ReadToEnd();
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            // Both PascalCase and camelCase are checked intentionally for compatibility
            // with PowerShell's ConvertTo-Json (PascalCase) and manual/JS JSON input (camelCase).
            if (root.TryGetProperty("Type", out var typeProp) || root.TryGetProperty("type", out typeProp))
                type = ParseEnum<NotificationType>(typeProp.GetString()!, "notification type");

            if (root.TryGetProperty("Title", out var titleProp) || root.TryGetProperty("title", out titleProp))
                title = titleProp.GetString();

            if (root.TryGetProperty("Message", out var messageProp) || root.TryGetProperty("message", out messageProp))
                message = messageProp.GetString();

            if (root.TryGetProperty("Timeout", out var timeoutProp) || root.TryGetProperty("timeout", out timeoutProp))
            {
                var val = timeoutProp.ValueKind == JsonValueKind.Null ? null : (int?)timeoutProp.GetInt32();
                if (val.HasValue && val.Value < 0)
                    throw new ArgumentException("Timeout must be a non-negative integer.");
                timeout = val;
            }

            if (root.TryGetProperty("Modal", out var modalProp) || root.TryGetProperty("modal", out modalProp))
                modal = modalProp.GetBoolean();

            if (root.TryGetProperty("Theme", out var themeProp) || root.TryGetProperty("theme", out themeProp))
                theme = ParseEnum<ThemeMode>(themeProp.GetString()!, "theme");

            if (root.TryGetProperty("PipeName", out var pipeProp) || root.TryGetProperty("pipeName", out pipeProp))
                pipeName = pipeProp.GetString();

            if (root.TryGetProperty("Illustration", out var illustProp) || root.TryGetProperty("illustration", out illustProp))
                illustration = illustProp.GetString();

            if (root.TryGetProperty("MspName", out var mspNameProp) || root.TryGetProperty("mspName", out mspNameProp))
                mspName = mspNameProp.GetString();

            if (root.TryGetProperty("MspLogo", out var mspLogoProp) || root.TryGetProperty("mspLogo", out mspLogoProp))
                mspLogo = mspLogoProp.GetString();

            if (root.TryGetProperty("Buttons", out var buttonsProp) || root.TryGetProperty("buttons", out buttonsProp))
            {
                foreach (var btn in buttonsProp.EnumerateArray())
                {
                    var label = (btn.TryGetProperty("Label", out var lp) || btn.TryGetProperty("label", out lp) ? lp.GetString()! : "").Trim();
                    var value = (btn.TryGetProperty("Value", out var vp) || btn.TryGetProperty("value", out vp) ? vp.GetString()! : "").Trim();
                    if (string.IsNullOrWhiteSpace(label))
                        throw new ArgumentException("Each button must have a non-empty label.");
                    if (string.IsNullOrWhiteSpace(value))
                        throw new ArgumentException("Each button must have a non-empty value.");
                    var style = ButtonStyle.Ghost;
                    if (btn.TryGetProperty("Style", out var sp) || btn.TryGetProperty("style", out sp))
                        style = ParseEnum<ButtonStyle>(sp.GetString()!, "button style");
                    buttons.Add(new ButtonDefinition { Label = label, Value = value, Style = style });
                }
            }
        }

        // Flags override JSON values
        if (flags.TryGetValue("type", out var typeStr) && typeStr != null)
            type = ParseEnum<NotificationType>(typeStr, "notification type");

        if (flags.TryGetValue("title", out var titleStr) && titleStr != null)
            title = titleStr;

        if (flags.TryGetValue("message", out var messageStr) && messageStr != null)
            message = messageStr;

        if (flags.TryGetValue("timeout", out var timeoutStr) && timeoutStr != null)
        {
            if (!int.TryParse(timeoutStr, out var timeoutVal))
                throw new ArgumentException("--timeout must be a valid integer.");
            if (timeoutVal < 0)
                throw new ArgumentException("--timeout must be a non-negative integer.");
            timeout = timeoutVal;
        }

        if (boolFlags.Contains("modal"))
            modal = true;

        if (flags.TryGetValue("theme", out var themeStr) && themeStr != null)
            theme = ParseEnum<ThemeMode>(themeStr, "theme");

        if (flags.TryGetValue("pipe", out var pipeStr) && pipeStr != null)
            pipeName = pipeStr;

        if (flags.TryGetValue("illustration", out var illustStr) && illustStr != null)
            illustration = illustStr;

        if (flags.TryGetValue("msp-name", out var mspNameStr) && mspNameStr != null)
            mspName = mspNameStr;

        if (flags.TryGetValue("msp-logo", out var mspLogoStr) && mspLogoStr != null)
            mspLogo = mspLogoStr;

        if (flags.TryGetValue("buttons", out var buttonsStr) && buttonsStr != null)
        {
            buttons = new List<ButtonDefinition>();
            foreach (var part in buttonsStr.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var segments = part.Split(':');
                var label = segments[0].Trim();
                // If the last segment is a valid style name, use it as style and join
                // the middle segments as the value (supports URLs with colons in values).
                ButtonStyle parsedStyle = ButtonStyle.Ghost;
                bool hasStyle = segments.Length > 2 &&
                    Enum.TryParse<ButtonStyle>(segments[segments.Length - 1], ignoreCase: true, out parsedStyle);
                var value = (hasStyle
                    ? string.Join(":", segments, 1, segments.Length - 2)
                    : segments.Length > 1 ? string.Join(":", segments, 1, segments.Length - 1) : "").Trim();
                var style = hasStyle ? parsedStyle : ButtonStyle.Ghost;
                if (string.IsNullOrWhiteSpace(label))
                    throw new ArgumentException("Each button must have a non-empty label.");
                if (string.IsNullOrWhiteSpace(value))
                    throw new ArgumentException("Each button must have a non-empty value.");
                buttons.Add(new ButtonDefinition { Label = label, Value = value, Style = style });
            }
        }

        if (type is null)
            throw new ArgumentException("--type is required.");
        if (title is null)
            throw new ArgumentException("--title is required.");
        if (message is null)
            throw new ArgumentException("--message is required.");

        // Default OK button for Question type when no buttons specified
        if (type == NotificationType.Question && buttons.Count == 0)
            buttons.Add(new ButtonDefinition { Label = "OK", Value = "ok", Style = ButtonStyle.Primary });

        return new BillboardConfig
        {
            Type = type.Value,
            Title = title,
            Message = message,
            Timeout = timeout,
            Modal = modal,
            Theme = theme,
            PipeName = pipeName,
            Buttons = buttons,
            Illustration = illustration?.Equals("none", StringComparison.OrdinalIgnoreCase) == true ? null : illustration,
            MspName = mspName,
            MspLogo = mspLogo,
        };
    }
}
