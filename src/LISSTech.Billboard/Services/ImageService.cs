using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media.Imaging;

namespace LISSTech.Billboard.Services;

/// <summary>
/// Loads bounded PNG, JPEG, and GIF artwork from local paths or public HTTPS URLs.
/// Remote images are validated before entering the per-user cache.
/// </summary>
public static class ImageService
{
    internal const int MaxDownloadBytes = 8 * 1024 * 1024;
    internal const int MaxDimension = 8192;
    internal const long MaxPixels = 16_000_000;
    internal const int MaxGifFrames = 60;

    private static readonly HttpClient HttpClient = new HttpClient(
        new HttpClientHandler { AllowAutoRedirect = false })
    {
        Timeout = TimeSpan.FromSeconds(15)
    };

    static ImageService()
    {
        HttpClient.DefaultRequestHeaders.UserAgent.ParseAdd("LISSTech.Billboard/1.0");
    }

    private static string GetCacheDir()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "LISSTech", "Billboard", "ImageCache");
    }

    internal static string GetCacheFile(string source)
    {
        byte[] hashBytes;
        using (var sha = System.Security.Cryptography.SHA256.Create())
            hashBytes = sha.ComputeHash(System.Text.Encoding.UTF8.GetBytes(source));
        return Path.Combine(
            GetCacheDir(),
            BitConverter.ToString(hashBytes).Replace("-", "") + ".img");
    }

    public static void EvictStaleCache()
    {
        try
        {
            var cacheDir = GetCacheDir();
            if (!Directory.Exists(cacheDir))
                return;

            var cutoff = DateTime.UtcNow.AddDays(-7);
            foreach (var file in Directory.GetFiles(cacheDir, "*.img"))
            {
                if (File.GetLastWriteTimeUtc(file) >= cutoff)
                    continue;
                try { File.Delete(file); }
                catch { }
            }
        }
        catch { }
    }

    public static BitmapImage? LoadImage(string? source, int decodePixelWidth)
    {
        if (string.IsNullOrWhiteSpace(source))
            return null;

        try
        {
            string path;
            if (TryCreateRemoteUri(source!, out _))
            {
                path = GetCacheFile(source!);
            }
            else
            {
                path = Path.GetFullPath(source!);
            }

            if (!File.Exists(path))
                return null;
            var file = new FileInfo(path);
            if (file.Length <= 0 || file.Length > MaxDownloadBytes)
                return null;

            return CreateBitmap(File.ReadAllBytes(path), decodePixelWidth);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Billboard: failed to load image: {ex.Message}");
            return null;
        }
    }

    public static void DownloadAndCacheAsync(
        string source,
        int decodePixelWidth,
        Action<BitmapImage> onLoaded)
    {
        if (!TryCreateRemoteUri(source, out var uri))
            return;

        var cacheDir = GetCacheDir();
        Directory.CreateDirectory(cacheDir);
        EvictStaleCache();
        var cacheFile = GetCacheFile(source);

        Task.Run(async () =>
        {
            string? tempFile = null;
            try
            {
                var bytes = await DownloadBytesAsync(uri!);
                ValidateImage(bytes);

                tempFile = cacheFile + "." + Guid.NewGuid().ToString("N") + ".tmp";
                File.WriteAllBytes(tempFile, bytes);
                try
                {
                    File.Move(tempFile, cacheFile);
                    tempFile = null;
                }
                catch (IOException) when (File.Exists(cacheFile))
                {
                    File.Delete(tempFile);
                    tempFile = null;
                }

                Application.Current?.Dispatcher?.BeginInvoke(new Action(() =>
                {
                    try
                    {
                        var image = CreateBitmap(bytes, decodePixelWidth);
                        onLoaded(image);
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine(
                            $"Billboard: failed to decode image: {ex.Message}");
                    }
                }));
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Billboard: rejected remote image: {ex.Message}");
            }
            finally
            {
                if (tempFile != null)
                {
                    try { File.Delete(tempFile); }
                    catch { }
                }
            }
        });
    }

    internal static bool TryCreateRemoteUri(string source, out Uri? uri)
    {
        if (!Uri.TryCreate(source, UriKind.Absolute, out uri) ||
            uri.Scheme != Uri.UriSchemeHttps ||
            !string.IsNullOrEmpty(uri.UserInfo) ||
            uri.Port != 443 ||
            string.IsNullOrWhiteSpace(uri.DnsSafeHost) ||
            uri.DnsSafeHost.IndexOf('.') < 0 ||
            uri.DnsSafeHost.EndsWith(".local", StringComparison.OrdinalIgnoreCase) ||
            uri.DnsSafeHost.EndsWith(".internal", StringComparison.OrdinalIgnoreCase))
        {
            uri = null;
            return false;
        }

        return true;
    }

    internal static bool IsPublicAddress(IPAddress address)
    {
        if (address.IsIPv4MappedToIPv6)
            address = address.MapToIPv4();

        if (address.AddressFamily == AddressFamily.InterNetworkV6)
        {
            return !IPAddress.IsLoopback(address) &&
                   !address.IsIPv6LinkLocal &&
                   !address.IsIPv6SiteLocal &&
                   !address.IsIPv6Multicast &&
                   !address.Equals(IPAddress.IPv6Any) &&
                   !address.Equals(IPAddress.IPv6None);
        }

        var bytes = address.GetAddressBytes();
        if (bytes.Length != 4)
            return false;

        return bytes[0] != 0 &&
               bytes[0] != 10 &&
               bytes[0] != 127 &&
               !(bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) &&
               !(bytes[0] == 169 && bytes[1] == 254) &&
               !(bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) &&
               !(bytes[0] == 192 && bytes[1] == 168) &&
               !(bytes[0] == 198 && (bytes[1] == 18 || bytes[1] == 19)) &&
               bytes[0] < 224;
    }

    internal static string ValidateImage(byte[] bytes)
    {
        if (bytes.Length == 0 || bytes.Length > MaxDownloadBytes)
            throw new InvalidDataException("Image size is outside the supported range.");

        var format = DetectFormat(bytes);
        var dimensions = ReadDimensions(bytes, format);
        ValidateDimensions(dimensions.width, dimensions.height);

        using var stream = new MemoryStream(bytes, writable: false);
        var decoder = BitmapDecoder.Create(
            stream,
            BitmapCreateOptions.DelayCreation,
            BitmapCacheOption.None);
        if (decoder.Frames.Count == 0)
            throw new InvalidDataException("Image contains no frames.");
        if (format == "gif" && decoder.Frames.Count > MaxGifFrames)
            throw new InvalidDataException("GIF contains too many frames.");

        long totalPixels = 0;
        foreach (var frame in decoder.Frames)
        {
            ValidateDimensions(frame.PixelWidth, frame.PixelHeight);
            totalPixels += (long)frame.PixelWidth * frame.PixelHeight;
            if (totalPixels > MaxPixels)
                throw new InvalidDataException("Image frames exceed the safety limit.");
        }

        return format;
    }

    private static string DetectFormat(byte[] bytes)
    {
        if (bytes.Length >= 8 &&
            bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E &&
            bytes[3] == 0x47 && bytes[4] == 0x0D && bytes[5] == 0x0A &&
            bytes[6] == 0x1A && bytes[7] == 0x0A)
            return "png";
        if (bytes.Length >= 3 &&
            bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF)
            return "jpeg";
        if (bytes.Length >= 6 &&
            bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 &&
            bytes[3] == 0x38 && (bytes[4] == 0x37 || bytes[4] == 0x39) &&
            bytes[5] == 0x61)
            return "gif";

        throw new InvalidDataException("Only PNG, JPEG, and GIF images are supported.");
    }

    private static (long width, long height) ReadDimensions(byte[] bytes, string format)
    {
        if (format == "png")
        {
            if (bytes.Length < 24 ||
                bytes[12] != 0x49 || bytes[13] != 0x48 ||
                bytes[14] != 0x44 || bytes[15] != 0x52)
                throw new InvalidDataException("PNG is missing its IHDR header.");
            return (ReadUInt32BigEndian(bytes, 16), ReadUInt32BigEndian(bytes, 20));
        }

        if (format == "gif")
        {
            if (bytes.Length < 10)
                throw new InvalidDataException("GIF header is incomplete.");
            return (
                bytes[6] | (bytes[7] << 8),
                bytes[8] | (bytes[9] << 8));
        }

        for (var offset = 2; offset + 8 < bytes.Length;)
        {
            if (bytes[offset] != 0xFF)
            {
                offset++;
                continue;
            }

            while (offset < bytes.Length && bytes[offset] == 0xFF)
                offset++;
            if (offset >= bytes.Length)
                break;

            var marker = bytes[offset++];
            if (marker is 0xD8 or 0xD9 or 0x01 ||
                (marker >= 0xD0 && marker <= 0xD7))
                continue;
            if (offset + 1 >= bytes.Length)
                break;

            var segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
            if (segmentLength < 2 || offset + segmentLength > bytes.Length)
                throw new InvalidDataException("JPEG segment is invalid.");

            var isStartOfFrame =
                (marker >= 0xC0 && marker <= 0xC3) ||
                (marker >= 0xC5 && marker <= 0xC7) ||
                (marker >= 0xC9 && marker <= 0xCB) ||
                (marker >= 0xCD && marker <= 0xCF);
            if (isStartOfFrame)
            {
                if (segmentLength < 7)
                    throw new InvalidDataException("JPEG frame header is incomplete.");
                return (
                    (bytes[offset + 5] << 8) | bytes[offset + 6],
                    (bytes[offset + 3] << 8) | bytes[offset + 4]);
            }

            offset += segmentLength;
        }

        throw new InvalidDataException("JPEG is missing a supported frame header.");
    }

    private static long ReadUInt32BigEndian(byte[] bytes, int offset) =>
        ((long)bytes[offset] << 24) |
        ((long)bytes[offset + 1] << 16) |
        ((long)bytes[offset + 2] << 8) |
        bytes[offset + 3];

    private static void ValidateDimensions(long width, long height)
    {
        if (width <= 0 || height <= 0 ||
            width > MaxDimension || height > MaxDimension ||
            width * height > MaxPixels)
            throw new InvalidDataException("Image dimensions exceed the safety limit.");
    }

    private static BitmapImage CreateBitmap(byte[] bytes, int decodePixelWidth)
    {
        ValidateImage(bytes);
        using var stream = new MemoryStream(bytes, writable: false);
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.StreamSource = stream;
        image.DecodePixelWidth = Math.Max(1, Math.Min(decodePixelWidth, 2048));
        image.EndInit();
        image.Freeze();
        return image;
    }

    private static async Task<byte[]> DownloadBytesAsync(Uri initialUri)
    {
        var uri = initialUri;
        for (var redirect = 0; redirect <= 3; redirect++)
        {
            await EnsurePublicHostAsync(uri);
            using var response = await HttpClient.GetAsync(
                uri,
                HttpCompletionOption.ResponseHeadersRead);

            if ((int)response.StatusCode is 301 or 302 or 303 or 307 or 308)
            {
                if (redirect == 3 || response.Headers.Location == null)
                    throw new HttpRequestException("Remote image redirected too many times.");
                var next = response.Headers.Location.IsAbsoluteUri
                    ? response.Headers.Location
                    : new Uri(uri, response.Headers.Location);
                if (!TryCreateRemoteUri(next.AbsoluteUri, out var safeNext))
                    throw new HttpRequestException("Remote image redirected to a blocked URL.");
                uri = safeNext!;
                continue;
            }

            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength > MaxDownloadBytes)
                throw new InvalidDataException("Remote image exceeds the 8 MB limit.");

            using var input = await response.Content.ReadAsStreamAsync();
            using var output = new MemoryStream();
            var buffer = new byte[81920];
            while (true)
            {
                var read = await input.ReadAsync(buffer, 0, buffer.Length);
                if (read == 0)
                    return output.ToArray();
                if (output.Length + read > MaxDownloadBytes)
                    throw new InvalidDataException("Remote image exceeds the 8 MB limit.");
                output.Write(buffer, 0, read);
            }
        }

        throw new HttpRequestException("Remote image redirect failed.");
    }

    private static async Task EnsurePublicHostAsync(Uri uri)
    {
        var addresses = await Dns.GetHostAddressesAsync(uri.DnsSafeHost);
        if (addresses.Length == 0)
            throw new HttpRequestException("Remote image host did not resolve.");
        foreach (var address in addresses)
        {
            if (!IsPublicAddress(address))
                throw new HttpRequestException("Remote image host resolved to a private address.");
        }
    }
}
