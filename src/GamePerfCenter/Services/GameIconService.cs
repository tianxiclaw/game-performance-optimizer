using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage;
using Windows.Storage.FileProperties;

namespace GamePerfCenter.Services;

/// <summary>
/// 按 exe 路径读取系统为它提供的缩略图（即资源管理器里看到的程序图标）。
/// 结果按路径缓存在内存中，任何机器、任何游戏都走同一条路径；
/// 找不到文件或系统没有缩略图时返回 null，由界面回退到首字母。
/// </summary>
public static class GameIconService
{
    private const uint IconSize = 64;
    private static readonly Dictionary<string, Task<ImageSource?>> Cache =
        new(StringComparer.OrdinalIgnoreCase);

    public static Task<ImageSource?> GetAsync(string? exe)
    {
        if (string.IsNullOrWhiteSpace(exe)) return Task.FromResult<ImageSource?>(null);
        var path = exe.Trim().Trim('"');
        if (path.Length == 0) return Task.FromResult<ImageSource?>(null);

        lock (Cache)
        {
            if (Cache.TryGetValue(path, out var cached)) return cached;
            var task = LoadAsync(path);
            Cache[path] = task;
            return task;
        }
    }

    private static async Task<ImageSource?> LoadAsync(string path)
    {
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(path);
            using var thumb = await file.GetThumbnailAsync(
                ThumbnailMode.SingleItem, IconSize, ThumbnailOptions.ResizeThumbnail);
            if (thumb is null || thumb.Size == 0) return null;

            var image = new BitmapImage();
            await image.SetSourceAsync(thumb);
            return image;
        }
        catch
        {
            return null;
        }
    }
}