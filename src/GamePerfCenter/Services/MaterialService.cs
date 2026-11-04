using Microsoft.UI.Composition.SystemBackdrops;

namespace GamePerfCenter.Services;

/// <summary>
/// 窗口材质。云母与液态玻璃走 Windows 11 的系统合成层，
/// Windows 10 或不支持透明合成的环境自动回退到默认深空渐变。
/// </summary>
public static class MaterialService
{
    public static bool IsSupported(string material) => material switch
    {
        "mica" => MicaController.IsSupported(),
        "glass" => DesktopAcrylicController.IsSupported(),
        _ => true
    };

    public static string Normalize(string material)
        => material is "mica" or "glass" ? material : "deep";

    public static string DisplayName(string material) => material switch
    {
        "mica" => "云母",
        "glass" => "液态玻璃",
        _ => "深空"
    };
}
