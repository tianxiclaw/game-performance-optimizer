using GamePerfCenter.Core.Infrastructure;
using GamePerfCenter.Models;

namespace GamePerfCenter.Helpers;

/// <summary>优化项列表的筛选规则；只做数据判断，不碰控件状态。</summary>
public static class ItemFiltering
{
    public static List<ItemInfo> Filter(
        IEnumerable<ItemInfo> items, string? category, string? risk, string? search) =>
        items.Where(item =>
                TextMatch.TagMatches(category, item.Cat) &&
                TextMatch.TagMatches(risk, item.Risk) &&
                TextMatch.FieldsContain(search, item.Name, item.Cat, item.Desc, item.StatusText))
            .ToList();
}