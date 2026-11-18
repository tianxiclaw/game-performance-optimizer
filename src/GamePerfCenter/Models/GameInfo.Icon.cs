using System.ComponentModel;
using System.Text.Json.Serialization;
using Microsoft.UI.Xaml.Media;

namespace GamePerfCenter.Models;

/// <summary>
/// 游戏图标由 shell 按每台机器上的实际 exe 路径提取，不预置任何游戏清单。
/// 提取失败时保持为空，界面回退到首字母。
/// </summary>
public sealed partial class GameInfo : INotifyPropertyChanged
{
    private ImageSource? _icon;
    private bool _iconLoaded;

    [JsonIgnore]
    public ImageSource? Icon
    {
        get => _icon;
        private set
        {
            if (ReferenceEquals(_icon, value)) return;
            _icon = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Icon)));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(HasIcon)));
        }
    }

    [JsonIgnore]
    public bool HasIcon => _icon is not null;

    [JsonIgnore]
    public bool IconLoaded => _iconLoaded;

    /// <summary>图标提取最多尝试一次；失败后不再反复访问不存在的路径。</summary>
    internal void ApplyIcon(ImageSource? icon)
    {
        _iconLoaded = true;
        Icon = icon;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}