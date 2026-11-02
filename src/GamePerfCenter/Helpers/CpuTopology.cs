using System.Runtime.InteropServices;

namespace GamePerfCenter.Helpers;

/// <summary>
/// 本机 CPU 拓扑：物理核心数、逻辑处理器数，以及“每核保留一个线程”的亲和性掩码。
/// </summary>
public static class CpuTopology
{
    private const int RelationProcessorCore = 0;

    private static readonly Lazy<Info> Cached = new(Query);

    public static int PhysicalCores => Cached.Value.Cores;
    public static int LogicalProcessors => Cached.Value.Logical;
    public static bool HasSmt => LogicalProcessors > PhysicalCores;

    private readonly record struct Info(int Cores, int Logical);

    [StructLayout(LayoutKind.Sequential)]
    private struct Slpi64
    {
        public UIntPtr ProcessorMask;
        public int Relationship;
        public int Padding;
        public long Data0;
        public long Data1;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetLogicalProcessorInformation(IntPtr buffer, ref uint length);

    private static Info Query()
    {
        var fallback = new Info(Environment.ProcessorCount, Environment.ProcessorCount);
        if (IntPtr.Size != 8) return fallback;

        uint length = 0;
        GetLogicalProcessorInformation(IntPtr.Zero, ref length);
        if (length == 0) return fallback;

        var buffer = Marshal.AllocHGlobal((int)length);
        try
        {
            if (!GetLogicalProcessorInformation(buffer, ref length)) return fallback;

            var size = Marshal.SizeOf<Slpi64>();
            var count = (int)length / size;
            var cores = 0;
            var logical = 0;
            for (var i = 0; i < count; i++)
            {
                var item = Marshal.PtrToStructure<Slpi64>(IntPtr.Add(buffer, i * size));
                if (item.Relationship != RelationProcessorCore) continue;
                var mask = item.ProcessorMask.ToUInt64();
                if (mask == 0) continue;
                cores++;
                logical += PopCount(mask);
            }
            return cores > 0 ? new Info(cores, logical) : fallback;
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static int PopCount(ulong value)
    {
        var count = 0;
        while (value != 0)
        {
            value &= value - 1;
            count++;
        }
        return count;
    }
}
