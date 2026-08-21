using System.Globalization;
using System.Text;

namespace CodexQuota.Windows;

public sealed class DiagnosticLogger
{
    private const long MaximumBytes = 256 * 1024;
    private readonly object gate = new();
    private readonly string filePath;

    public DiagnosticLogger(string filePath)
    {
        this.filePath = filePath;
    }

    public void Log(string subsystem, string code)
    {
        lock (gate)
        {
            try
            {
                var directory = Path.GetDirectoryName(filePath) ?? throw new InvalidOperationException();
                Directory.CreateDirectory(directory);
                var line = $"{DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture)} subsystem={subsystem} code={code}{Environment.NewLine}";
                var currentSize = File.Exists(filePath) ? new FileInfo(filePath).Length : 0;
                if (currentSize > 0 && currentSize + Encoding.UTF8.GetByteCount(line) > MaximumBytes)
                {
                    File.Move(filePath, filePath + ".1", true);
                }
                File.AppendAllText(filePath, line);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                return;
            }
        }
    }
}
