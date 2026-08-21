using Microsoft.Win32;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Orientation = System.Windows.Controls.Orientation;
using Size = System.Windows.Size;
using Window = System.Windows.Window;

namespace CodexQuota.Windows;

public sealed class OverlayWindow : Window
{
    private const double HeightInDips = 30;
    private const double MinimumWidthInDips = 74;
    private const double MaximumWidthInDips = 180;
    private const double FallbackSidebarWidthInDips = 244;

    private readonly Border border;
    private readonly Ellipse dot;
    private readonly TextBlock label;
    private IntPtr handle;

    public OverlayWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        Focusable = false;
        IsHitTestVisible = false;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = -10_000;
        Top = -10_000;

        dot = new Ellipse
        {
            Width = 6,
            Height = 6,
            Margin = new Thickness(0, 0, 6, 0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        label = new TextBlock
        {
            FontSize = 11.5,
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
        var content = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            VerticalAlignment = VerticalAlignment.Center,
        };
        content.Children.Add(dot);
        content.Children.Add(label);

        border = new Border
        {
            Height = HeightInDips,
            CornerRadius = new CornerRadius(HeightInDips / 2),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(11, 0, 11, 0),
            Child = content,
        };
        Content = border;
        Height = HeightInDips;
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        handle = new WindowInteropHelper(this).Handle;
        var styles = NativeMethods.GetWindowLongPtr(handle, NativeMethods.GwlExStyle).ToInt64();
        styles |= NativeMethods.WsExNoActivate | NativeMethods.WsExToolWindow | NativeMethods.WsExTransparent;
        NativeMethods.SetWindowLongPtr(handle, NativeMethods.GwlExStyle, new IntPtr(styles));
    }

    public void Render(QuotaDisplayState state, CodexWindowSnapshot? target, AppSettings settings)
    {
        if (!settings.OverlayEnabled || target is null)
        {
            Hide();
            return;
        }

        var scale = target.DpiScale;
        var frame = target.Frame;
        var sidebarWidth = Math.Min(FallbackSidebarWidthInDips * scale, frame.Width);
        var x = frame.Left + (16 + 30 + 8 + settings.HorizontalOffset) * scale;
        var y = frame.Bottom - (14 + HeightInDips + settings.VerticalOffset) * scale;
        var availableWidthPixels = frame.Left + sidebarWidth - 10 * scale - x;
        if (availableWidthPixels < MinimumWidthInDips * scale)
        {
            Hide();
            return;
        }

        ApplyPalette(state.Level, settings.Appearance);
        var maximumWidth = Math.Min(MaximumWidthInDips, availableWidthPixels / scale);
        var text = FittingText(state, maximumWidth);
        label.Text = text;
        label.ToolTip = state.TooltipText;
        var desiredWidth = Math.Clamp(MeasureWidth(text), MinimumWidthInDips, maximumWidth);
        Width = desiredWidth;

        if (!IsVisible)
        {
            Show();
        }
        NativeMethods.SetWindowPos(
            handle,
            new IntPtr(-1),
            (int)Math.Round(x),
            (int)Math.Round(y),
            (int)Math.Ceiling(desiredWidth * scale),
            (int)Math.Ceiling(HeightInDips * scale),
            NativeMethods.SwpNoActivate | NativeMethods.SwpShowWindow);
    }

    private string FittingText(QuotaDisplayState state, double maximumWidth)
    {
        if (MeasureWidth(state.PillText) <= maximumWidth) return state.PillText;
        if (MeasureWidth(state.CompactText) <= maximumWidth) return state.CompactText;
        return state.RemainingPercent is int remaining ? $"{remaining}%" : "--";
    }

    private double MeasureWidth(string text)
    {
        label.Text = text;
        label.Measure(new Size(double.PositiveInfinity, HeightInDips));
        return 34 + label.DesiredSize.Width;
    }

    private void ApplyPalette(QuotaLevel level, AppAppearance appearance)
    {
        var dark = appearance == AppAppearance.Dark ||
            (appearance == AppAppearance.System && SystemThemeIsDark());
        var palette = Palette.For(level, dark);
        dot.Fill = palette.Foreground;
        label.Foreground = palette.Foreground;
        border.Background = palette.Background;
        border.BorderBrush = palette.Border;
    }

    private static bool SystemThemeIsDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int value && value == 0;
        }
        catch
        {
            return false;
        }
    }

    private sealed record Palette(Brush Foreground, Brush Background, Brush Border)
    {
        public static Palette For(QuotaLevel level, bool dark) => (level, dark) switch
        {
            (QuotaLevel.Normal, false) => Make(8, 122, 85, 226, 247, 238, 140, 211, 181),
            (QuotaLevel.Normal, true) => Make(94, 233, 181, 18, 59, 47, 71, 151, 120),
            (QuotaLevel.Warning, false) => Make(147, 96, 0, 255, 245, 214, 224, 190, 103),
            (QuotaLevel.Warning, true) => Make(246, 200, 95, 65, 49, 19, 159, 126, 50),
            (QuotaLevel.Critical, false) => Make(179, 38, 30, 255, 234, 232, 226, 150, 145),
            (QuotaLevel.Critical, true) => Make(255, 123, 114, 67, 30, 29, 164, 76, 71),
            (QuotaLevel.Unavailable, false) => Make(87, 96, 106, 239, 241, 243, 188, 194, 200),
            _ => Make(174, 184, 194, 45, 49, 54, 99, 107, 116),
        };

        private static Palette Make(
            byte foregroundRed,
            byte foregroundGreen,
            byte foregroundBlue,
            byte backgroundRed,
            byte backgroundGreen,
            byte backgroundBlue,
            byte borderRed,
            byte borderGreen,
            byte borderBlue) => new(
                FrozenBrush(Color.FromRgb(foregroundRed, foregroundGreen, foregroundBlue)),
                FrozenBrush(Color.FromRgb(backgroundRed, backgroundGreen, backgroundBlue)),
                FrozenBrush(Color.FromArgb(158, borderRed, borderGreen, borderBlue)));

        private static SolidColorBrush FrozenBrush(Color color)
        {
            var brush = new SolidColorBrush(color);
            brush.Freeze();
            return brush;
        }
    }
}
