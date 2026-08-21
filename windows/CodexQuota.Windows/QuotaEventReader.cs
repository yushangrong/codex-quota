using System.Text;

namespace CodexQuota.Windows;

public sealed class QuotaEventReader
{
    private sealed class Cursor
    {
        public long Offset { get; set; }
        public byte[] Pending { get; set; } = [];
        public DateTime CreationTimeUtc { get; set; }
    }

    private sealed record Inventory(
        IReadOnlyList<string> Files,
        IReadOnlySet<string> CompletelyInventoriedRoots,
        bool HadFailure);

    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private static readonly StringComparer PathComparer = StringComparer.OrdinalIgnoreCase;

    private readonly string[] roots;
    private readonly Dictionary<string, Cursor> cursors = new(PathComparer);
    private readonly Dictionary<string, QuotaSnapshot> latestSnapshots = new(PathComparer);

    public QuotaEventReader(IEnumerable<string> roots)
    {
        this.roots = roots.Select(Path.GetFullPath).ToArray();
    }

    public QuotaSnapshot? Scan()
    {
        var inventory = JsonlFiles();
        var discovered = new HashSet<string>(inventory.Files, PathComparer);
        var retained = new HashSet<string>(cursors.Keys, PathComparer);
        retained.UnionWith(latestSnapshots.Keys);
        foreach (var file in retained.Where(file =>
                     !discovered.Contains(file) &&
                     inventory.CompletelyInventoriedRoots.Any(root => IsWithin(root, file))))
        {
            cursors.Remove(file);
            latestSnapshots.Remove(file);
        }

        var hadFailure = inventory.HadFailure;
        var decodedValidSnapshot = false;
        foreach (var file in inventory.Files)
        {
            try
            {
                var metadata = new FileInfo(file);
                metadata.Refresh();
                if (!metadata.Exists)
                {
                    throw new IOException("File disappeared during quota scan.");
                }

                if (!cursors.TryGetValue(file, out var cursor))
                {
                    cursor = new Cursor { CreationTimeUtc = metadata.CreationTimeUtc };
                }
                else if (metadata.CreationTimeUtc != cursor.CreationTimeUtc || metadata.Length < cursor.Offset)
                {
                    cursor = new Cursor { CreationTimeUtc = metadata.CreationTimeUtc };
                    latestSnapshots.Remove(file);
                }

                var appended = ReadFrom(file, cursor.Offset);
                cursor.Offset = appended.Offset;
                cursor.CreationTimeUtc = metadata.CreationTimeUtc;
                foreach (var bytes in CompleteLines(appended.Data, cursor))
                {
                    string line;
                    try
                    {
                        line = StrictUtf8.GetString(bytes);
                    }
                    catch (DecoderFallbackException)
                    {
                        continue;
                    }

                    var decoded = QuotaEventDecoder.Decode(line);
                    var snapshot = decoded is null
                        ? null
                        : QuotaSelector.Snapshot(decoded, SourceFingerprint(Path.GetFileName(file)));
                    if (snapshot is null)
                    {
                        continue;
                    }

                    decodedValidSnapshot = true;
                    if (!latestSnapshots.TryGetValue(file, out var previous) ||
                        snapshot.ObservedAt > previous.ObservedAt)
                    {
                        latestSnapshots[file] = snapshot;
                    }
                }

                cursors[file] = cursor;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                hadFailure = true;
            }
        }

        if (hadFailure && !decodedValidSnapshot)
        {
            throw new QuotaScanException();
        }

        return latestSnapshots.Values.MaxBy(snapshot => snapshot.ObservedAt);
    }

    private Inventory JsonlFiles()
    {
        var files = new HashSet<string>(PathComparer);
        var completeRoots = new HashSet<string>(PathComparer);
        var hadFailure = false;
        var usableRoots = 0;

        foreach (var root in roots)
        {
            try
            {
                if (File.Exists(root))
                {
                    if (Path.GetExtension(root).Equals(".jsonl", StringComparison.OrdinalIgnoreCase))
                    {
                        usableRoots += 1;
                        files.Add(Path.GetFullPath(root));
                        completeRoots.Add(root);
                    }
                    else
                    {
                        hadFailure = true;
                    }
                    continue;
                }

                if (!Directory.Exists(root))
                {
                    completeRoots.Add(root);
                    continue;
                }

                usableRoots += 1;
                var options = new EnumerationOptions
                {
                    RecurseSubdirectories = true,
                    IgnoreInaccessible = false,
                    AttributesToSkip = FileAttributes.Hidden | FileAttributes.ReparsePoint,
                };
                foreach (var file in Directory.EnumerateFiles(root, "*.jsonl", options))
                {
                    files.Add(Path.GetFullPath(file));
                }
                completeRoots.Add(root);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                hadFailure = true;
            }
        }

        if (usableRoots == 0)
        {
            hadFailure = true;
        }

        return new Inventory(files.OrderBy(file => file, PathComparer).ToArray(), completeRoots, hadFailure);
    }

    private static (byte[] Data, long Offset) ReadFrom(string file, long offset)
    {
        using var stream = new FileStream(
            file,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete,
            64 * 1024,
            FileOptions.SequentialScan);
        stream.Seek(offset, SeekOrigin.Begin);
        using var buffer = new MemoryStream();
        stream.CopyTo(buffer);
        return (buffer.ToArray(), stream.Position);
    }

    private static IEnumerable<byte[]> CompleteLines(byte[] appended, Cursor cursor)
    {
        var combined = new byte[cursor.Pending.Length + appended.Length];
        Buffer.BlockCopy(cursor.Pending, 0, combined, 0, cursor.Pending.Length);
        Buffer.BlockCopy(appended, 0, combined, cursor.Pending.Length, appended.Length);

        var lines = new List<byte[]>();
        var start = 0;
        for (var index = 0; index < combined.Length; index += 1)
        {
            if (combined[index] != (byte)'\n')
            {
                continue;
            }

            var line = new byte[index - start];
            Buffer.BlockCopy(combined, start, line, 0, line.Length);
            lines.Add(line);
            start = index + 1;
        }

        cursor.Pending = combined[start..];
        return lines;
    }

    private static bool IsWithin(string root, string file)
    {
        var relative = Path.GetRelativePath(root, file);
        return relative == "." ||
            (!Path.IsPathRooted(relative) && relative != ".." &&
             !relative.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal));
    }

    private static string SourceFingerprint(string filename)
    {
        const ulong offsetBasis = 14_695_981_039_346_656_037;
        const ulong prime = 1_099_511_628_211;
        var hash = offsetBasis;
        foreach (var value in Encoding.UTF8.GetBytes(filename))
        {
            hash ^= value;
            hash *= prime;
        }
        return hash.ToString("x");
    }
}
