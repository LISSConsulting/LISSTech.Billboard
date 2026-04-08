using System;
using System.IO;
using System.Reflection;
using LISSTech.Billboard;
using LISSTech.Billboard.Models;
using LISSTech.Billboard.Services;

namespace LISSTech.Billboard.Host;

static class Program
{
    // Resolve DLL dependencies from ../Assembly/ relative to the exe.
    // Uses Assembly.Load(byte[]) to stay in the default load context so
    // WPF pack:// URIs can find embedded resources.
    static Program()
    {
        var exeDir = AppDomain.CurrentDomain.BaseDirectory;
        var assemblyDir = Path.GetFullPath(Path.Combine(exeDir, "..", "Assembly"));
        if (!Directory.Exists(assemblyDir)) return;

        AppDomain.CurrentDomain.AssemblyResolve += (_, e) =>
        {
            var name = new AssemblyName(e.Name).Name;
            var path = Path.Combine(assemblyDir, name + ".dll");
            if (!File.Exists(path)) return null;
            return Assembly.Load(File.ReadAllBytes(path));
        };
    }

    [STAThread]
    static int Main(string[] args)
    {
        if (CliParser.IsHelpRequested(args))
        {
            Console.WriteLine(CliParser.GetUsage());
            return 0;
        }

        BillboardConfig config;
        try
        {
            config = CliParser.Parse(args);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Billboard: {ex.Message}");
            Console.Error.WriteLine("Run 'Billboard.exe --help' for usage.");
            return 100;
        }

        BillboardResult result;
        try
        {
            result = BillboardService.Show(config);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Billboard window error: {ex}");
            return 100;
        }

        int exitCode = result.Timeout ? 2 : result.Dismissed ? 1 : 0;

        if (config.PipeName != null)
        {
            try
            {
                using var pipe = new PipeServer(config.PipeName);
                pipe.WaitForConnectionAndWriteAsync(result).GetAwaiter().GetResult();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Billboard pipe error: {ex.Message}");
                exitCode = 100;
            }
        }

        return exitCode;
    }
}
