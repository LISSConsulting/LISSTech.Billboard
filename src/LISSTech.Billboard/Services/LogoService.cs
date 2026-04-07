using System;
using System.Net.Http;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media.Imaging;

namespace LISSTech.Billboard.Services;

/// <summary>
/// Handles MSP logo loading, caching, and cache eviction.
/// </summary>
public static class LogoService
{
    private static readonly HttpClient _httpClient = new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(30)
    };
    private static string GetCacheDir()
    {
        return System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "LISSTech", "Billboard", "LogoCache");
    }

    internal static string GetCacheFile(string logoPath)
    {
        byte[] hashBytes;
        using (var sha = System.Security.Cryptography.SHA256.Create())
            hashBytes = sha.ComputeHash(System.Text.Encoding.UTF8.GetBytes(logoPath));
        return System.IO.Path.Combine(GetCacheDir(),
            BitConverter.ToString(hashBytes).Replace("-", "") + ".png");
    }

    /// <summary>
    /// Evicts cache files older than 7 days. Best-effort; failures are silently ignored.
    /// </summary>
    public static void EvictStaleCache()
    {
        try
        {
            var cacheDir = GetCacheDir();
            if (!System.IO.Directory.Exists(cacheDir))
                return;

            var cutoff = DateTime.UtcNow.AddDays(-7);
            foreach (var file in System.IO.Directory.GetFiles(cacheDir, "*.png"))
            {
                if (System.IO.File.GetLastWriteTimeUtc(file) < cutoff)
                {
                    try { System.IO.File.Delete(file); }
                    catch { /* best-effort cleanup */ }
                }
            }
        }
        catch { /* best-effort cleanup */ }
    }

    /// <summary>
    /// Loads an MSP logo synchronously. Returns null for remote URLs without a cache hit
    /// (those should be handled asynchronously by the caller).
    /// </summary>
    public static BitmapImage? LoadMspLogo(string? logoPath)
    {
        if (string.IsNullOrWhiteSpace(logoPath))
            return null;

        try
        {
            if (Uri.TryCreate(logoPath, UriKind.Absolute, out var uri) &&
                (uri.Scheme == "http" || uri.Scheme == "https"))
            {
                // Remote URL -- only return from cache; async download handled separately
                var cacheFile = GetCacheFile(logoPath!);

                if (System.IO.File.Exists(cacheFile))
                {
                    var cached = new BitmapImage();
                    cached.BeginInit();
                    cached.UriSource = new Uri(cacheFile, UriKind.Absolute);
                    cached.CacheOption = BitmapCacheOption.OnLoad;
                    cached.DecodePixelWidth = 48;
                    cached.EndInit();
                    cached.Freeze();
                    return cached;
                }

                // No cache hit -- return null so caller can handle async download
                return null;
            }
            else
            {
                // Local file path
                var fullPath = System.IO.Path.GetFullPath(logoPath);
                if (!System.IO.File.Exists(fullPath))
                    return null;

                var img = new BitmapImage();
                img.BeginInit();
                img.UriSource = new Uri(fullPath, UriKind.Absolute);
                img.CacheOption = BitmapCacheOption.OnLoad;
                img.DecodePixelWidth = 48;
                img.EndInit();
                img.Freeze();
                return img;
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Billboard: failed to load MSP logo: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Downloads a remote logo, saves to cache with atomic rename, and invokes
    /// <paramref name="onLoaded"/> on completion with the cached BitmapImage.
    /// Download runs on a background thread; the BitmapImage is created on the
    /// WPF dispatcher thread so WPF can safely freeze and hand it to the caller.
    /// </summary>
    public static void DownloadAndCacheAsync(Uri uri, string logoPath, Action<BitmapImage> onLoaded)
    {
        var cacheDir = GetCacheDir();
        System.IO.Directory.CreateDirectory(cacheDir);
        EvictStaleCache();

        var cacheFile = GetCacheFile(logoPath);

        Task.Run(async () =>
        {
            try
            {
                var bytes = await _httpClient.GetByteArrayAsync(uri);

                // Write to temp file then atomically rename to avoid race conditions
                var tempFile = cacheFile + ".tmp";
                System.IO.File.WriteAllBytes(tempFile, bytes);
                try
                {
                    System.IO.File.Move(tempFile, cacheFile);
                }
                catch (System.IO.IOException)
                {
                    // Another instance already wrote the cache file -- that's fine
                    try { System.IO.File.Delete(tempFile); } catch { }
                }

                // BitmapImage with UriSource requires the WPF dispatcher (STA).
                // Post the image creation back to the UI thread via the application dispatcher.
                Application.Current?.Dispatcher?.BeginInvoke(new Action(() =>
                {
                    try
                    {
                        var img = new BitmapImage();
                        img.BeginInit();
                        img.UriSource = new Uri(cacheFile, UriKind.Absolute);
                        img.CacheOption = BitmapCacheOption.OnLoad;
                        img.DecodePixelWidth = 48;
                        img.EndInit();
                        img.Freeze();
                        onLoaded(img);
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"Billboard: failed to create logo BitmapImage: {ex.Message}");
                    }
                }));
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Billboard: failed to download logo: {ex.Message}");
            }
        });
    }
}
