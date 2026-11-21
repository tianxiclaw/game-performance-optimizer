using GamePerfCenter.Core.Services;

namespace GamePerfCenter.Services;

public sealed class AppServices
{
    public SettingsService Settings { get; } = new();
    public EngineBridge Engine { get; } = new();
    public AppState State { get; }
    public DriverService Drivers { get; } = new();
    public DriverInventoryService DriverInventory { get; } = new();
    public DriverOperationService DriverOperations { get; } = new();
    public OptimizationCatalogService OptimizationCatalog { get; }
    public OptimizationExecutionService OptimizationExecution { get; }
    public LiveMetricsService Metrics { get; } = new();

    public AppServices()
    {
        // Core 的静默失败统一落到 data\winui.log，便于从用户日志定位真实原因。
        CoreDiagnostics.SetSink(AppLog.Write);
        OptimizationCatalog = new OptimizationCatalogService(AppPaths.BaseDir, AppPaths.EnginePath);
        OptimizationExecution = new OptimizationExecutionService(AppPaths.BaseDir, AppPaths.BackupDir,
            AppPaths.UserSid);
        State = new AppState(Engine, Settings, OptimizationCatalog, OptimizationExecution);
    }
}
