using System.Reflection;
using System.Windows;
using System.Windows.Threading;
using Application = System.Windows.Application;
using MessageBox = System.Windows.MessageBox;

namespace CodexQuota.Windows;

public sealed class MainController : IDisposable
{
    private readonly string settingsPath;
    private readonly AppSettings settings;
    private readonly QuotaEventReader reader;
    private readonly QuotaCache cache;
    private readonly DiagnosticLogger logger;
    private readonly StartupController startup = new();
    private readonly CodexWindowTracker windowTracker = new();
    private readonly OverlayWindow overlay = new();
    private readonly PositionAdjustmentWindow positionAdjustment;
    private readonly TrayController tray;
    private readonly DispatcherTimer windowTimer = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private readonly DispatcherTimer quotaTimer = new() { Interval = TimeSpan.FromSeconds(5) };

    private QuotaSnapshot? snapshot;
    private string? diagnosticCode;
    private bool isScanning;
    private bool disposed;
    private bool startupEnabled;
    private int consecutiveScanFailures;

    public MainController()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var localRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CodexQuota");
        var settingsRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "CodexQuota");
        settingsPath = Path.Combine(settingsRoot, "settings.json");
        settings = AppSettings.Load(settingsPath);
        reader = new QuotaEventReader([
            Path.Combine(home, ".codex", "sessions"),
            Path.Combine(home, ".codex", "archived_sessions"),
        ]);
        cache = new QuotaCache(Path.Combine(localRoot, "snapshot.json"));
        logger = new DiagnosticLogger(Path.Combine(localRoot, "app.log"));
        positionAdjustment = new PositionAdjustmentWindow(
            AdjustPosition,
            ResetPosition,
            () => (settings.HorizontalOffset, settings.VerticalOffset));
        tray = new TrayController(new TrayActions(
            Render,
            ToggleOverlay,
            ToggleStartup,
            positionAdjustment.Present,
            SelectAppearance,
            ShowAbout,
            () => Application.Current.Shutdown()));

        windowTimer.Tick += (_, _) => RenderOverlay();
        quotaTimer.Tick += async (_, _) => await RefreshQuotaAsync();
    }

    public void Start()
    {
        startupEnabled = ReadStartupEnabled();
        try
        {
            snapshot = cache.Load();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Text.Json.JsonException)
        {
            diagnosticCode = "CACHE_LOAD_FAILED";
            logger.Log("cache", diagnosticCode);
        }

        Render();
        windowTimer.Start();
        quotaTimer.Start();
        _ = RefreshQuotaAsync();
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        windowTimer.Stop();
        quotaTimer.Stop();
        tray.Dispose();
        positionAdjustment.ClosePermanently();
        overlay.Close();
    }

    private async Task RefreshQuotaAsync()
    {
        if (disposed || isScanning) return;
        isScanning = true;
        try
        {
            var scanned = await Task.Run(reader.Scan);
            if (disposed) return;
            if (scanned is not null)
            {
                try
                {
                    cache.Save(scanned);
                    snapshot = scanned;
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                {
                    RecordPollingFailure("cache", "CACHE_SAVE_FAILED");
                    return;
                }
            }
            RecordPollingSuccess();
        }
        catch (QuotaScanException)
        {
            RecordPollingFailure("reader", "SCAN_FAILED");
        }
        catch (Exception)
        {
            RecordPollingFailure("reader", "SCAN_FAILED");
        }
        finally
        {
            isScanning = false;
            if (!disposed) Render();
        }
    }

    private void Render()
    {
        if (disposed) return;
        var display = CurrentDisplay();
        overlay.Render(display, windowTracker.Current(), settings);
        tray.Update(display, diagnosticCode, settings, startupEnabled);
    }

    private void RenderOverlay()
    {
        if (disposed) return;
        overlay.Render(CurrentDisplay(), windowTracker.Current(), settings);
    }

    private void RecordPollingSuccess()
    {
        consecutiveScanFailures = 0;
        quotaTimer.Interval = TimeSpan.FromSeconds(5);
        diagnosticCode = null;
    }

    private void RecordPollingFailure(string subsystem, string code)
    {
        var delay = Math.Min(60, 5 * (1 << Math.Min(consecutiveScanFailures, 4)));
        consecutiveScanFailures += 1;
        quotaTimer.Interval = TimeSpan.FromSeconds(delay);
        diagnosticCode = code;
        logger.Log(subsystem, code);
    }

    private void ToggleOverlay()
    {
        settings.OverlayEnabled = !settings.OverlayEnabled;
        SaveSettings();
        Render();
    }

    private void ToggleStartup()
    {
        try
        {
            startup.SetEnabled(!startupEnabled);
            startupEnabled = startup.IsEnabled;
            diagnosticCode = null;
        }
        catch
        {
            diagnosticCode = "STARTUP_UPDATE_FAILED";
            logger.Log("startup", diagnosticCode);
        }
        Render();
    }

    private void AdjustPosition(double horizontal, double vertical)
    {
        settings.HorizontalOffset += horizontal;
        settings.VerticalOffset += vertical;
        SaveSettings();
        Render();
    }

    private void ResetPosition()
    {
        settings.ResetPosition();
        SaveSettings();
        Render();
    }

    private void SelectAppearance(AppAppearance appearance)
    {
        settings.Appearance = appearance;
        SaveSettings();
        Render();
    }

    private void SaveSettings()
    {
        try
        {
            settings.Save(settingsPath);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            diagnosticCode = "SETTINGS_SAVE_FAILED";
            logger.Log("settings", diagnosticCode);
        }
    }

    private QuotaDisplayState CurrentDisplay() =>
        snapshot is null ? QuotaDisplayState.Waiting : QuotaFormatter.Display(snapshot);

    private bool ReadStartupEnabled()
    {
        try
        {
            return startup.IsEnabled;
        }
        catch
        {
            return false;
        }
    }

    private static void ShowAbout()
    {
        var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.1.0";
        MessageBox.Show(
            $"Codex Quota {version}\n\nWindows 原生版本\nGitHub: github.com/yushangrong/codex-quota\n非 OpenAI 官方项目",
            "关于 Codex Quota",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }
}
