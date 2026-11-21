namespace GamePerfCenter;

public interface IThemeAware
{
    void OnThemeChanged();
}

/// <summary>页面在语言切换后重刷自己用代码拼出来的文案与计数。</summary>
public interface ILanguageAware
{
    void OnLanguageChanged();
}
