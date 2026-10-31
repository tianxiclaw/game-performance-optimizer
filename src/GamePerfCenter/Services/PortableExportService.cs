using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;

namespace GamePerfCenter.Services;

/// <summary>
/// 把当前程序目录打包成可分发的便携 ZIP，自动排除本机设置、备份、诊断与日志。
/// </summary>
public static class PortableExportService
{
    private static readonly HashSet<string> ExcludedDirs = new(StringComparer.OrdinalIgnoreCase)
    {
        "data", "backups", "diagnostics", ".tmp"
    };

    private static readonly HashSet<string> ExcludedFiles = new(StringComparer.OrdinalIgnoreCase)
    {
        "gui-settings.json", "profiles.json", "state_last_apply.json", "SHA256.txt"
    };

    public static Task<(int Files, long Bytes)> ExportAsync(string targetPath, CancellationToken token = default)
        => Task.Run(() => Export(targetPath, token), token);

    private static (int Files, long Bytes) Export(string targetPath, CancellationToken token)
    {
        var baseDir = new DirectoryInfo(AppPaths.BaseDir).FullName;
        var targetFull = Path.GetFullPath(targetPath);
        var tempPath = targetFull + ".part";

        var files = Directory.EnumerateFiles(baseDir, "*", SearchOption.AllDirectories)
            .Where(path => !IsInExcludedDir(path, baseDir))
            .Where(path => !ExcludedFiles.Contains(Path.GetFileName(path)))
            .Where(path => !IsExcludedExtension(path))
            .Where(path => !string.Equals(Path.GetFullPath(path), targetFull, StringComparison.OrdinalIgnoreCase))
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .ToList();

        try
        {
            int count;
            long total;
            using (var stream = new FileStream(tempPath, FileMode.Create, FileAccess.Write, FileShare.None))
            using (var archive = new ZipArchive(stream, ZipArchiveMode.Create))
            {
                var hashes = new List<string>(files.Count);
                total = 0;

                foreach (var path in files)
                {
                    token.ThrowIfCancellationRequested();
                    var relative = Path.GetRelativePath(baseDir, path).Replace('\\', '/');
                    var bytes = File.ReadAllBytes(path);
                    total += bytes.Length;

                    using (var sha = SHA256.Create())
                        hashes.Add($"{Convert.ToHexString(sha.ComputeHash(bytes)).ToLowerInvariant()}  {relative}");

                    var entry = archive.CreateEntry(relative, CompressionLevel.Optimal);
                    entry.LastWriteTime = File.GetLastWriteTime(path);
                    using var entryStream = entry.Open();
                    entryStream.Write(bytes, 0, bytes.Length);
                }

                var checksumEntry = archive.CreateEntry("SHA256.txt", CompressionLevel.Optimal);
                using var writer = new StreamWriter(checksumEntry.Open(), new UTF8Encoding(false));
                writer.Write(string.Join("\r\n", hashes));
                writer.Write("\r\n");
                count = files.Count;
            }

            File.Move(tempPath, targetFull, true);
            return (count, total);
        }
        finally
        {
            if (File.Exists(tempPath)) File.Delete(tempPath);
        }
    }

    private static bool IsInExcludedDir(string path, string baseDir)
    {
        var relative = Path.GetRelativePath(baseDir, path);
        var separator = relative.IndexOfAny(new[] { '\\', '/' });
        return separator > 0 && ExcludedDirs.Contains(relative[..separator]);
    }

    private static bool IsExcludedExtension(string path)
    {
        var extension = Path.GetExtension(path);
        return extension.Equals(".log", StringComparison.OrdinalIgnoreCase)
            || extension.Equals(".zip", StringComparison.OrdinalIgnoreCase)
            || extension.Equals(".pdb", StringComparison.OrdinalIgnoreCase)
            || extension.Equals(".tmp", StringComparison.OrdinalIgnoreCase);
    }
}
