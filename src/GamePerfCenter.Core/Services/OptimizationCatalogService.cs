using System.Text;
using System.Text.Json;
using GamePerfCenter.Core.Infrastructure;
using GamePerfCenter.Core.Models;

namespace GamePerfCenter.Core.Services;

/// <summary>
/// 从 PowerShell 引擎读取优化项目录。硬件检测与项目录仍由引擎维护，
/// Core 只负责解析与缓存，避免 CLI / GUI 各写一套检测逻辑。
/// </summary>
public sealed class OptimizationCatalogService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        NumberHandling = System.Text.Json.Serialization.JsonNumberHandling.AllowReadingFromString
    };

    private readonly string _enginePath;
    private readonly object _lock = new();
    private OptimizationCatalog? _cache;
    private DateTime _cacheAt = DateTime.MinValue;
    private DateTime _engineWriteAt = DateTime.MinValue;

    public OptimizationCatalogService(string? baseDirectory = null, string? enginePath = null)
    {
        var dir = baseDirectory ?? AppContext.BaseDirectory;
        _enginePath = enginePath ?? LocateEngine(dir);
    }

    private static string LocateEngine(string startDirectory)
    {
        var candidates = new List<string> { Path.Combine(startDirectory, "游戏性能优化.ps1") };
        var current = new DirectoryInfo(startDirectory);
        for (var i = 0; i < 6 && current.Parent is not null; i++)
        {
            current = current.Parent;
            candidates.Add(Path.Combine(current.FullName, "游戏性能优化.ps1"));
        }
        candidates.Add(Path.Combine(Environment.CurrentDirectory, "游戏性能优化.ps1"));

        foreach (var candidate in candidates)
            if (File.Exists(candidate)) return candidate;
        return candidates[0];
    }

    public string EnginePath => _enginePath;

    public OptimizationCatalog Load(bool force = false)
    {
        if (!File.Exists(_enginePath))
            throw new FileNotFoundException("优化引擎脚本缺失", _enginePath);

        lock (_lock)
        {
            var writeAt = File.GetLastWriteTimeUtc(_enginePath);
            if (!force && _cache is not null && writeAt == _engineWriteAt &&
                DateTime.UtcNow - _cacheAt < TimeSpan.FromMinutes(5))
                return _cache;

            var temp = Path.Combine(Path.GetTempPath(), $"gpc_catalog_{Guid.NewGuid():N}.json");
            try
            {
                PowerShellRunner.RunFile(_enginePath, new[]
                {
                    "-EngineOnly", "-NoElevate", "-Catalog", "-CatalogOut", temp
                }, TimeSpan.FromMinutes(5));

                if (!File.Exists(temp))
                    throw new InvalidOperationException("引擎未生成优化项目录");

                var json = File.ReadAllText(temp, Encoding.UTF8);
                var catalog = JsonSerializer.Deserialize<OptimizationCatalog>(json, JsonOptions)
                              ?? throw new InvalidOperationException("优化项目录为空");
                _cache = catalog;
                _cacheAt = DateTime.UtcNow;
                _engineWriteAt = writeAt;
                return catalog;
            }
            finally
            {
                try { if (File.Exists(temp)) File.Delete(temp); } catch { }
            }
        }
    }

    public static OptimizationCatalog Parse(string json)
    {
        return JsonSerializer.Deserialize<OptimizationCatalog>(json, JsonOptions)
               ?? throw new InvalidOperationException("优化项目录为空");
    }
}
