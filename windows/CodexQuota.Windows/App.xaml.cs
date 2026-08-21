using System.Windows;
using Application = System.Windows.Application;

namespace CodexQuota.Windows;

public partial class App : Application
{
    private MainController? controller;
    private Mutex? instanceMutex;
    private bool ownsInstanceMutex;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        instanceMutex = new Mutex(true, @"Local\CodexQuota", out ownsInstanceMutex);
        if (!ownsInstanceMutex)
        {
            Shutdown();
            return;
        }

        controller = new MainController();
        controller.Start();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        controller?.Dispose();
        controller = null;
        if (ownsInstanceMutex)
        {
            instanceMutex?.ReleaseMutex();
        }
        instanceMutex?.Dispose();
        instanceMutex = null;
        base.OnExit(e);
    }
}
