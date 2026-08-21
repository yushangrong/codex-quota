using System.Globalization;
using System.Text.Json;

namespace CodexQuota.Windows;

public static class QuotaEventDecoder
{
    public static DecodedRateLimitEvent? Decode(string line)
    {
        try
        {
            using var document = JsonDocument.Parse(line, new JsonDocumentOptions { MaxDepth = 32 });
            var root = document.RootElement;
            if (!TryGetString(root, "type", out var type) || type != "event_msg" ||
                !TryGetString(root, "timestamp", out var timestamp) ||
                !DateTimeOffset.TryParse(
                    timestamp,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AllowWhiteSpaces,
                    out var observedAt) ||
                !root.TryGetProperty("payload", out var payload) ||
                payload.ValueKind != JsonValueKind.Object ||
                !payload.TryGetProperty("rate_limits", out var rateLimits) ||
                rateLimits.ValueKind != JsonValueKind.Object ||
                !TryGetString(rateLimits, "limit_id", out var limitId) ||
                !TryDecodeWindow(rateLimits, "primary", out var primary) ||
                !TryDecodeWindow(rateLimits, "secondary", out var secondary))
            {
                return null;
            }

            return new DecodedRateLimitEvent(
                observedAt,
                limitId,
                primary,
                secondary);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static bool TryDecodeWindow(JsonElement rateLimits, string name, out QuotaWindow? window)
    {
        window = null;
        if (!rateLimits.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (value.ValueKind != JsonValueKind.Object ||
            !value.TryGetProperty("used_percent", out var usedPercent) || !usedPercent.TryGetDouble(out var used) ||
            !value.TryGetProperty("window_minutes", out var windowMinutes) || !windowMinutes.TryGetInt32(out var minutes) ||
            !value.TryGetProperty("resets_at", out var resetsAt) || !resetsAt.TryGetInt64(out var reset))
        {
            return false;
        }

        window = new QuotaWindow(used, minutes, reset);
        return true;
    }

    private static bool TryGetString(JsonElement value, string name, out string result)
    {
        result = string.Empty;
        if (!value.TryGetProperty(name, out var property) || property.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        result = property.GetString() ?? string.Empty;
        return true;
    }
}
