using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace CodexQuota.Windows;

public sealed record TrayActions(
    Action Refresh,
    Action ToggleOverlay,
    Action ToggleStartup,
    Action ShowPositionAdjustment,
    Action<AppAppearance> SelectAppearance,
    Action ShowAbout,
    Action Quit);

public sealed class TrayController : IDisposable
{
    private readonly Forms.NotifyIcon notifyIcon;
    private readonly Forms.ContextMenuStrip menu = new();
    private readonly Forms.ToolStripMenuItem currentQuota = new("当前额度：等待数据") { Enabled = false };
    private readonly Forms.ToolStripMenuItem diagnostic = new("诊断：正常") { Enabled = false };
    private readonly Forms.ToolStripMenuItem overlay = new("显示悬浮层");
    private readonly Forms.ToolStripMenuItem startup = new("开机启动");
    private readonly Dictionary<AppAppearance, Forms.ToolStripMenuItem> appearanceItems = [];
    private readonly TrayActions actions;

    public TrayController(TrayActions actions)
    {
        this.actions = actions;
        menu.Opening += (_, _) => actions.Refresh();
        overlay.Click += (_, _) => actions.ToggleOverlay();
        startup.Click += (_, _) => actions.ToggleStartup();

        var appearance = new Forms.ToolStripMenuItem("外观");
        foreach (var (value, title) in new[]
                 {
                     (AppAppearance.System, "跟随系统"),
                     (AppAppearance.Dark, "深色"),
                     (AppAppearance.Light, "浅色"),
                 })
        {
            var item = Item(title, () => actions.SelectAppearance(value));
            appearanceItems[value] = item;
            appearance.DropDownItems.Add(item);
        }

        menu.Items.Add(currentQuota);
        menu.Items.Add(diagnostic);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(overlay);
        menu.Items.Add(startup);
        menu.Items.Add(Item("调整位置…", actions.ShowPositionAdjustment));
        menu.Items.Add(appearance);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(Item("关于 Codex Quota", actions.ShowAbout));
        menu.Items.Add(Item("退出", actions.Quit));

        notifyIcon = new Forms.NotifyIcon
        {
            Icon = Drawing.SystemIcons.Application,
            Text = "Codex 周额度",
            ContextMenuStrip = menu,
            Visible = true,
        };
    }

    public void Update(
        QuotaDisplayState display,
        string? diagnosticCode,
        AppSettings settings,
        bool startupEnabled)
    {
        var tooltip = $"Codex {display.CompactText}";
        notifyIcon.Text = tooltip[..Math.Min(tooltip.Length, 63)];
        currentQuota.Text = $"当前额度：{display.PillText}";
        currentQuota.ToolTipText = display.TooltipText;
        diagnostic.Text = diagnosticCode is null ? "诊断：正常" : $"诊断：{diagnosticCode}";
        overlay.Checked = settings.OverlayEnabled;
        startup.Checked = startupEnabled;
        foreach (var (appearance, item) in appearanceItems)
        {
            item.Checked = settings.Appearance == appearance;
        }
    }

    public void Dispose()
    {
        notifyIcon.Visible = false;
        notifyIcon.Dispose();
        menu.Dispose();
    }

    private static Forms.ToolStripMenuItem Item(string title, Action action)
    {
        var item = new Forms.ToolStripMenuItem(title);
        item.Click += (_, _) => action();
        return item;
    }
}
