using System.Diagnostics;
using System.Runtime.InteropServices;

namespace CodexQuota.Windows;

public sealed record CodexWindowSnapshot(IntPtr Handle, NativeRect Frame, double DpiScale);

public sealed class CodexWindowTracker
{
    private static readonly HashSet<string> OfficialProcessNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "ChatGPT",
        "Codex",
    };

    public CodexWindowSnapshot? Current()
    {
        var window = NativeMethods.GetForegroundWindow();
        if (window == IntPtr.Zero || !NativeMethods.IsWindowVisible(window) || NativeMethods.IsIconic(window))
        {
            return null;
        }

        NativeMethods.GetWindowThreadProcessId(window, out var processId);
        if (processId == 0)
        {
            return null;
        }

        try
        {
            using var process = Process.GetProcessById((int)processId);
            if (!OfficialProcessNames.Contains(process.ProcessName))
            {
                return null;
            }
        }
        catch
        {
            return null;
        }

        if (NativeMethods.DwmGetWindowAttribute(
                window,
                NativeMethods.DwmwaExtendedFrameBounds,
                out var frame,
                Marshal.SizeOf<NativeRect>()) != 0 &&
            !NativeMethods.GetWindowRect(window, out frame))
        {
            return null;
        }

        var dpi = NativeMethods.GetDpiForWindow(window);
        var scale = dpi > 0 ? dpi / 96.0 : 1;
        if (frame.Width < 210 * scale || frame.Height < 120 * scale)
        {
            return null;
        }

        return new CodexWindowSnapshot(window, frame, scale);
    }
}
