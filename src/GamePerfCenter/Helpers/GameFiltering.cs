using GamePerfCenter.Core.Infrastructure;
using GamePerfCenter.Models;

namespace GamePerfCenter.Helpers;

/// <summary>游戏库的筛选规则；页面只负责把筛选控件读数传进来。</summary>
public static class GameFiltering
{
    public static bool Matches(GameInfo game, string? keyword, string? source, string? profileFilter)
    {
        if (!TextMatch.FieldsContain(keyword, game.Name, game.Exe)) return false;
        if (!TextMatch.TagMatches(source, game.SourceText)) return false;

        var saved = game.Profile?.HasSaved == true;
        return profileFilter switch
        {
            "saved" => saved,
            "none" => !saved,
            _ => true
        };
    }
}