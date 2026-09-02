using CodexQuota.Windows;

var fixtureRoot = args.Length == 1 ? Path.GetFullPath(args[0]) : FindFixtureRoot();
TestDecoderAndSelector(fixtureRoot);
TestFormatter();
TestIncrementalReader(fixtureRoot);
Console.WriteLine("PASS: Windows quota core tests");
return;

static void TestDecoderAndSelector(string fixtureRoot)
{
    var primary = DecodeFixture(fixtureRoot, "weekly-primary");
    var secondary = DecodeFixture(fixtureRoot, "weekly-secondary");
    var shortWindow = DecodeFixture(fixtureRoot, "non-weekly");

    Equal<double?>(37d, QuotaSelector.Snapshot(primary, "p")?.UsedPercent, "primary weekly percentage");
    Equal<int?>(10_080, QuotaSelector.Snapshot(secondary, "s")?.WindowMinutes, "secondary weekly window");
    Equal<QuotaSnapshot?>(null, QuotaSelector.Snapshot(shortWindow, "x"), "short window rejection");
    True(!primary.ToString().Contains("PRIVATE_TEXT_MUST_NOT_SURVIVE", StringComparison.Ordinal), "private payload is not retained");

    var invalid = primary with { Primary = primary.Primary! with { UsedPercent = 101 } };
    Equal<QuotaSnapshot?>(null, QuotaSelector.Snapshot(invalid, "x"), "invalid percentage rejection");

    var malformedPrimary = File.ReadAllText(Path.Combine(fixtureRoot, "weekly-secondary.jsonl"))
        .Replace("\"primary\":null", "\"primary\":{}", StringComparison.Ordinal);
    Equal<DecodedRateLimitEvent?>(null, QuotaEventDecoder.Decode(malformedPrimary), "malformed optional window rejects the event");
}

static void TestFormatter()
{
    var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
    var snapshot = new QuotaSnapshot(37, 10_080, now.AddDays(3), now, "fixture");
    var display = QuotaFormatter.Display(snapshot, now);
    Equal<int?>(63, display.RemainingPercent, "remaining percentage");
    Equal(QuotaLevel.Normal, display.Level, "normal threshold");
    Equal("Codex 63% · 3天", display.PillText, "pill copy");
    Equal("63% · 约3天", display.CompactText, "compact copy");
    Equal(QuotaLevel.Warning, QuotaFormatter.Level(30), "warning threshold");
    Equal(QuotaLevel.Warning, QuotaFormatter.Level(10), "warning lower boundary");
    Equal(QuotaLevel.Critical, QuotaFormatter.Level(9), "critical threshold");
    Equal("6小时后重置", QuotaFormatter.Countdown(now.AddHours(6), now), "hour countdown");

    var detailed = snapshot with { UsedPercent = 47, ResetsAt = now.AddDays(4).AddHours(19) };
    var detailedDisplay = QuotaFormatter.Display(detailed, now);
    Equal("Codex 53% · 4天19小时", detailedDisplay.PillText, "detailed multi-day copy");
    Equal("53% · 约5天", detailedDisplay.CompactText, "rounded compact day copy");
    Equal("约4天", QuotaFormatter.CompactCountdown(now.AddDays(4).AddHours(11), now), "compact day rounds down");
    Equal("约5天", QuotaFormatter.CompactCountdown(now.AddDays(4).AddHours(12), now), "compact day rounds up");

    var expired = snapshot with { ResetsAt = now };
    Equal("Codex -- · 等待刷新", QuotaFormatter.Display(expired, now).PillText, "expired window");
}

static void TestIncrementalReader(string fixtureRoot)
{
    var temporaryRoot = Path.Combine(Path.GetTempPath(), $"CodexQuotaWindowsTests-{Guid.NewGuid():N}");
    Directory.CreateDirectory(temporaryRoot);
    try
    {
        var file = Path.Combine(temporaryRoot, "rollout.jsonl");
        var line = File.ReadAllText(Path.Combine(fixtureRoot, "weekly-primary.jsonl")).TrimEnd('\r', '\n');
        File.WriteAllText(file, line);
        var reader = new QuotaEventReader([temporaryRoot]);
        Equal<QuotaSnapshot?>(null, reader.Scan(), "partial line is deferred");

        File.AppendAllText(file, Environment.NewLine);
        Equal<double?>(37d, reader.Scan()?.UsedPercent, "completed line is decoded incrementally");

        var newer = line
            .Replace("2026-07-21T07:30:27.974Z", "2026-07-21T08:30:27.974Z", StringComparison.Ordinal)
            .Replace("\"used_percent\":37", "\"used_percent\":40", StringComparison.Ordinal);
        File.AppendAllText(file, newer + Environment.NewLine);
        Equal<double?>(40d, reader.Scan()?.UsedPercent, "newest event wins");
    }
    finally
    {
        Directory.Delete(temporaryRoot, true);
    }
}

static DecodedRateLimitEvent DecodeFixture(string fixtureRoot, string name)
{
    var line = File.ReadAllText(Path.Combine(fixtureRoot, name + ".jsonl"));
    return QuotaEventDecoder.Decode(line) ?? throw new InvalidOperationException($"Could not decode {name}.");
}

static string FindFixtureRoot()
{
    var current = new DirectoryInfo(AppContext.BaseDirectory);
    while (current is not null)
    {
        var candidate = Path.Combine(current.FullName, "Tests", "Fixtures");
        if (Directory.Exists(candidate)) return candidate;
        current = current.Parent;
    }
    throw new DirectoryNotFoundException("Tests/Fixtures was not found.");
}

static void Equal<T>(T expected, T actual, string context)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"{context}: expected {expected}, got {actual}");
    }
}

static void True(bool condition, string context)
{
    if (!condition) throw new InvalidOperationException(context);
}
