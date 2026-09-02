using System.Globalization;

namespace CodexQuota.Windows;

public static class QuotaFormatter
{
    public static QuotaDisplayState Display(QuotaSnapshot snapshot, DateTimeOffset? currentTime = null)
    {
        var now = currentTime ?? DateTimeOffset.Now;
        if (snapshot.ResetsAt <= now)
        {
            return new QuotaDisplayState(
                null,
                QuotaLevel.Unavailable,
                "Codex -- · 等待刷新",
                "--",
                "窗口已到重置时间，等待新数据",
                true);
        }

        var remaining = Math.Clamp(
            (int)Math.Round(100 - snapshot.UsedPercent, MidpointRounding.AwayFromZero),
            0,
            100);
        var reset = Countdown(snapshot.ResetsAt, now);
        var detailedReset = reset.Replace("后重置", string.Empty, StringComparison.Ordinal);
        var compactReset = CompactCountdown(snapshot.ResetsAt, now);
        var stale = now - snapshot.ObservedAt > TimeSpan.FromMinutes(30);
        var used = (int)Math.Round(snapshot.UsedPercent, MidpointRounding.AwayFromZero);
        var tooltip = $"已用 {used}% · {snapshot.ResetsAt.LocalDateTime.ToString("g", CultureInfo.CurrentCulture)} 重置" +
            (stale ? " · 数据可能已过期" : string.Empty);

        return new QuotaDisplayState(
            remaining,
            Level(remaining),
            $"Codex {remaining}% · {detailedReset}",
            $"{remaining}% · {compactReset}",
            tooltip,
            stale);
    }

    public static QuotaLevel Level(int remainingPercent) => remainingPercent > 30
        ? QuotaLevel.Normal
        : remainingPercent >= 10 ? QuotaLevel.Warning : QuotaLevel.Critical;

    public static string Countdown(DateTimeOffset reset, DateTimeOffset now)
    {
        var seconds = Math.Max(0, (reset - now).TotalSeconds);
        if (seconds >= 86_400)
        {
            var wholeHours = (int)(seconds / 3_600);
            var days = wholeHours / 24;
            var hours = wholeHours % 24;
            return hours == 0 ? $"{days}天后重置" : $"{days}天{hours}小时后重置";
        }
        if (seconds >= 3_600) return $"{(int)(seconds / 3_600)}小时后重置";
        return $"{Math.Max(1, (int)(seconds / 60))}分钟后重置";
    }

    public static string CompactCountdown(DateTimeOffset reset, DateTimeOffset now)
    {
        var seconds = Math.Max(0, (reset - now).TotalSeconds);
        if (seconds >= 86_400)
        {
            var days = Math.Max(1, (int)Math.Round(seconds / 86_400, MidpointRounding.AwayFromZero));
            return $"约{days}天";
        }
        return Countdown(reset, now).Replace("后重置", string.Empty, StringComparison.Ordinal);
    }
}
