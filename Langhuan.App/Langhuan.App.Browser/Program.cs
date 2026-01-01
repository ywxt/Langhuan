namespace Langhuan.App.Browser;

using System.Threading.Tasks;
using Avalonia;
using Avalonia.Browser;

internal static class Program
{
    private static Task Main() => BuildAvaloniaApp()
        .WithInterFont()
        .StartBrowserAppAsync("out");

    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>();
}
