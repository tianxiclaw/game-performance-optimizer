namespace GamePerfCenter.Services;

public sealed class AppServices
{
    public SettingsService Settings { get; } = new();
    public EngineBridge Engine { get; } = new();
    public AppState State { get; }
    public DriverService Drivers { get; } = new();

    public AppServices()
    {
        State = new AppState(Engine, Settings);
    }
}
