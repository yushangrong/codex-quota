using System.Text.Json;

namespace CodexQuota.Windows;

public sealed class QuotaCache
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
    };

    private readonly string filePath;

    public QuotaCache(string filePath)
    {
        this.filePath = filePath;
    }

    public QuotaSnapshot? Load()
    {
        return File.Exists(filePath)
            ? JsonSerializer.Deserialize<QuotaSnapshot>(File.ReadAllText(filePath), Options)
            : null;
    }

    public void Save(QuotaSnapshot value)
    {
        var directory = Path.GetDirectoryName(filePath) ?? throw new InvalidOperationException("Missing cache directory.");
        Directory.CreateDirectory(directory);
        var temporaryPath = filePath + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(value, Options));
        File.Move(temporaryPath, filePath, true);
    }
}
