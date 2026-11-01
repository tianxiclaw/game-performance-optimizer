using System.Text;

namespace GamePerfCenter.Core.Infrastructure;

/// <summary>
/// INF 文件在不同厂商手里可能是 UTF-8、UTF-16 或本地 ANSI。
/// 这里按 BOM 优先，其次严格 UTF-8，最后回退到系统 ANSI 代码页。
/// </summary>
public static class TextFileReader
{
    private static readonly Encoding StrictUtf8 = new UTF8Encoding(false, true);
    private static readonly Encoding Ansi;

    static TextFileReader()
    {
        try { Encoding.RegisterProvider(CodePagesEncodingProvider.Instance); } catch { }
        try { Ansi = Encoding.GetEncoding(0); }
        catch { Ansi = Encoding.Default; }
    }

    public static string ReadAllText(string path)
    {
        var bytes = File.ReadAllBytes(path);
        if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
            return Encoding.UTF8.GetString(bytes, 3, bytes.Length - 3);
        if (bytes.Length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
            return Encoding.Unicode.GetString(bytes, 2, bytes.Length - 2);
        if (bytes.Length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF)
            return Encoding.BigEndianUnicode.GetString(bytes, 2, bytes.Length - 2);

        try { return StrictUtf8.GetString(bytes); }
        catch (DecoderFallbackException) { return Ansi.GetString(bytes); }
    }
}
