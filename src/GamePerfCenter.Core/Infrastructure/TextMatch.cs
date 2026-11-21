namespace GamePerfCenter.Core.Infrastructure;

/// <summary>
/// 界面筛选共用的纯文本匹配规则。不依赖 UI 模型，便于单独测试，
/// 也避免各页面各写一套大小写与空值处理。
/// </summary>
public static class TextMatch
{
    /// <summary>筛选值为空时表示“全部”，否则按不区分大小写精确比较。</summary>
    public static bool TagMatches(string? filter, string? value) =>
        string.IsNullOrWhiteSpace(filter) ||
        string.Equals(filter, value, StringComparison.OrdinalIgnoreCase);

    /// <summary>关键词为空时表示“全部”，否则任一字段包含关键词即命中。</summary>
    public static bool FieldsContain(string? query, params string?[] fields)
    {
        if (string.IsNullOrWhiteSpace(query)) return true;
        var needle = query.Trim();
        foreach (var field in fields)
        {
            if (!string.IsNullOrEmpty(field) &&
                field.Contains(needle, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }
}