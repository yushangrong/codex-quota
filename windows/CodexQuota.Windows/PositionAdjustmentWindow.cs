using System.ComponentModel;
using System.Globalization;
using System.Windows.Automation;
using System.Windows.Interop;
using WpfBorder = System.Windows.Controls.Border;
using WpfButton = System.Windows.Controls.Button;
using WpfGrid = System.Windows.Controls.Grid;
using WpfRepeatButton = System.Windows.Controls.Primitives.RepeatButton;
using WpfStackPanel = System.Windows.Controls.StackPanel;
using WpfTextBlock = System.Windows.Controls.TextBlock;
using WpfWindow = System.Windows.Window;
using WpfBrushes = System.Windows.SystemColors;
using WpfFontWeights = System.Windows.FontWeights;
using WpfGridLength = System.Windows.GridLength;
using WpfGridUnitType = System.Windows.GridUnitType;
using WpfHorizontalAlignment = System.Windows.HorizontalAlignment;
using WpfOrientation = System.Windows.Controls.Orientation;
using WpfResizeMode = System.Windows.ResizeMode;
using WpfThickness = System.Windows.Thickness;
using WpfVerticalAlignment = System.Windows.VerticalAlignment;
using WpfWindowStartupLocation = System.Windows.WindowStartupLocation;
using WpfWindowStyle = System.Windows.WindowStyle;

namespace CodexQuota.Windows;

public sealed class PositionAdjustmentWindow : WpfWindow
{
    private readonly Action<double, double> adjust;
    private readonly Action reset;
    private readonly Func<(double Horizontal, double Vertical)> offsets;
    private readonly WpfTextBlock offsetLabel;
    private bool allowClose;

    public PositionAdjustmentWindow(
        Action<double, double> adjust,
        Action reset,
        Func<(double Horizontal, double Vertical)> offsets)
    {
        this.adjust = adjust;
        this.reset = reset;
        this.offsets = offsets;

        Title = "调整悬浮层位置";
        Width = 310;
        SizeToContent = System.Windows.SizeToContent.Height;
        ResizeMode = WpfResizeMode.NoResize;
        WindowStyle = WpfWindowStyle.ToolWindow;
        WindowStartupLocation = WpfWindowStartupLocation.CenterScreen;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        Background = WpfBrushes.WindowBrush;

        var title = new WpfTextBlock
        {
            Text = "连续点击方向按钮来微调",
            FontSize = 14,
            FontWeight = WpfFontWeights.SemiBold,
            HorizontalAlignment = WpfHorizontalAlignment.Center,
            Margin = new WpfThickness(0, 0, 0, 5),
        };
        var hint = new WpfTextBlock
        {
            Text = "可连续点击或按住，每次移动 2 px",
            Foreground = WpfBrushes.GrayTextBrush,
            FontSize = 12,
            HorizontalAlignment = WpfHorizontalAlignment.Center,
            Margin = new WpfThickness(0, 0, 0, 5),
        };
        offsetLabel = new WpfTextBlock
        {
            Foreground = WpfBrushes.GrayTextBrush,
            FontFamily = new System.Windows.Media.FontFamily("Consolas"),
            FontSize = 12,
            HorizontalAlignment = WpfHorizontalAlignment.Center,
            Margin = new WpfThickness(0, 0, 0, 14),
        };

        var directionGrid = new WpfGrid
        {
            Width = 188,
            HorizontalAlignment = WpfHorizontalAlignment.Center,
            Margin = new WpfThickness(0, 0, 0, 16),
        };
        for (var index = 0; index < 3; index += 1)
        {
            directionGrid.RowDefinitions.Add(new System.Windows.Controls.RowDefinition
            {
                Height = WpfGridLength.Auto,
            });
            directionGrid.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition
            {
                Width = new WpfGridLength(1, WpfGridUnitType.Star),
            });
        }

        AddToGrid(directionGrid, DirectionButton("↑", "上移 2 px", 0, 2), row: 0, column: 1);
        AddToGrid(directionGrid, DirectionButton("←", "左移 2 px", -2, 0), row: 1, column: 0);
        AddToGrid(directionGrid, new WpfTextBlock
        {
            Text = "▰",
            Foreground = WpfBrushes.GrayTextBrush,
            FontSize = 18,
            HorizontalAlignment = WpfHorizontalAlignment.Center,
            VerticalAlignment = WpfVerticalAlignment.Center,
        }, row: 1, column: 1);
        AddToGrid(directionGrid, DirectionButton("→", "右移 2 px", 2, 0), row: 1, column: 2);
        AddToGrid(directionGrid, DirectionButton("↓", "下移 2 px", 0, -2), row: 2, column: 1);

        var resetButton = ActionButton("恢复默认", () =>
        {
            reset();
            RefreshOffsets();
        });
        resetButton.Margin = new WpfThickness(0, 0, 5, 0);
        var doneButton = ActionButton("完成", Hide);
        doneButton.Margin = new WpfThickness(5, 0, 0, 0);

        var footer = new WpfGrid { Width = 230 };
        footer.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition
        {
            Width = new WpfGridLength(1, WpfGridUnitType.Star),
        });
        footer.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition
        {
            Width = new WpfGridLength(1, WpfGridUnitType.Star),
        });
        AddToGrid(footer, resetButton, row: 0, column: 0);
        AddToGrid(footer, doneButton, row: 0, column: 1);

        var stack = new WpfStackPanel { Orientation = WpfOrientation.Vertical };
        stack.Children.Add(title);
        stack.Children.Add(hint);
        stack.Children.Add(offsetLabel);
        stack.Children.Add(directionGrid);
        stack.Children.Add(footer);

        Content = new WpfBorder
        {
            Padding = new WpfThickness(24, 18, 24, 20),
            Background = WpfBrushes.WindowBrush,
            Child = stack,
        };
        RefreshOffsets();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var handle = new WindowInteropHelper(this).Handle;
        var styles = NativeMethods.GetWindowLongPtr(handle, NativeMethods.GwlExStyle).ToInt64();
        styles |= NativeMethods.WsExNoActivate | NativeMethods.WsExToolWindow;
        NativeMethods.SetWindowLongPtr(handle, NativeMethods.GwlExStyle, new IntPtr(styles));
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!allowClose)
        {
            e.Cancel = true;
            Hide();
        }
        base.OnClosing(e);
    }

    public void Present()
    {
        RefreshOffsets();
        if (!IsVisible)
        {
            Show();
        }
    }

    public void ClosePermanently()
    {
        allowClose = true;
        Close();
    }

    private WpfRepeatButton DirectionButton(string title, string accessibilityLabel, double horizontal, double vertical)
    {
        var button = new WpfRepeatButton
        {
            Content = title,
            Delay = 350,
            Interval = 150,
            MinHeight = 30,
            Padding = new WpfThickness(10, 3, 10, 3),
        };
        button.Click += (_, _) =>
        {
            adjust(horizontal, vertical);
            RefreshOffsets();
        };
        button.Width = 54;
        button.Height = 32;
        button.FontSize = 17;
        button.FontWeight = WpfFontWeights.SemiBold;
        button.Margin = new WpfThickness(4);
        AutomationProperties.SetName(button, accessibilityLabel);
        return button;
    }

    private static WpfButton ActionButton(string title, Action action)
    {
        var button = new WpfButton
        {
            Content = title,
            MinHeight = 30,
            Padding = new WpfThickness(10, 3, 10, 3),
        };
        button.Click += (_, _) => action();
        return button;
    }

    private void RefreshOffsets()
    {
        var current = offsets();
        offsetLabel.Text = $"水平 {Format(current.Horizontal)} px  ·  垂直 {Format(current.Vertical)} px";
    }

    private static string Format(double value) =>
        value.ToString("0.#", CultureInfo.CurrentCulture);

    private static void AddToGrid(WpfGrid grid, System.Windows.UIElement child, int row, int column)
    {
        WpfGrid.SetRow(child, row);
        WpfGrid.SetColumn(child, column);
        grid.Children.Add(child);
    }
}
