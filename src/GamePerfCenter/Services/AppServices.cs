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

    public AppServices()
    {
        OptimizationCatalog = new OptimizationCatalogService(AppPaths.BaseDir, AppPaths.EnginePath);
        OptimizationExecution = new OptimizationExecutionService(AppPaths.BaseDir, AppPaths.BackupDir,
            AppPaths.UserSid);
        State = new AppState(Engine, Settings, OptimizationCatalog, OptimizationExecution);
    }
}
