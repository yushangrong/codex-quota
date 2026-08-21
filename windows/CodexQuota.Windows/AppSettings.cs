using System.Text.Json;

namespace CodexQuota.Windows;

public enum AppAppearance
{
    System,
    Dark,
    Light,
}

public sealed class AppSettings
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };

    public double HorizontalOffset { get; set; }
    public double VerticalOffset { get; set; }
    public bool OverlayEnabled { get; set; } = true;
    public AppAppearance Appearance { get; set; } = AppAppearance.System;

    public static AppSettings Load(string filePath)
    {
        try
        {
            return File.Exists(filePath)
                ? JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(filePath), Options) ?? new AppSettings()
                : new AppSettings();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException)
        {
            return new AppSettings();
        }
    }

    public void Save(string filePath)
    {
        var directory = Path.GetDirectoryName(filePath) ?? throw new InvalidOperationException("Missing settings directory.");
        Directory.CreateDirectory(directory);
        var temporaryPath = filePath + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(this, Options));
        File.Move(temporaryPath, filePath, true);
    }

    public void ResetPosition()
    {
        HorizontalOffset = 0;
        VerticalOffset = 0;
    }
}
