using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Net;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LISSTech.Billboard.Services;
using Xunit;

namespace Billboard.Tests;

public class ImageServiceTests
{
    [Fact]
    public void GetCacheFile_SamePath_ReturnsSamePath()
    {
        var path1 = ImageService.GetCacheFile("https://example.com/logo.png");
        var path2 = ImageService.GetCacheFile("https://example.com/logo.png");
        Assert.Equal(path1, path2);
    }

    [Fact]
    public void GetCacheFile_DifferentPaths_DifferentCacheFiles()
    {
        var path1 = ImageService.GetCacheFile("https://example.com/logo1.png");
        var path2 = ImageService.GetCacheFile("https://example.com/logo2.png");
        Assert.NotEqual(path1, path2);
    }

    [Fact]
    public void GetCacheFile_HasFull64CharHex()
    {
        var cacheFile = ImageService.GetCacheFile("test");
        var filename = Path.GetFileNameWithoutExtension(cacheFile);
        Assert.Equal(64, filename.Length);
        Assert.Matches("^[0-9A-F]{64}$", filename);
    }

    [Fact]
    public void GetCacheFile_MatchesExpectedSha256()
    {
        const string input = "https://example.com/logo.png";
        byte[] hash;
        using (var sha = SHA256.Create())
            hash = sha.ComputeHash(Encoding.UTF8.GetBytes(input));
        var expectedHex = BitConverter.ToString(hash).Replace("-", "");

        var cacheFile = ImageService.GetCacheFile(input);
        var filename = Path.GetFileNameWithoutExtension(cacheFile);
        Assert.Equal(expectedHex, filename);
    }

    [Fact]
    public void GetCacheFile_HasOpaqueImageExtension()
    {
        var cacheFile = ImageService.GetCacheFile("https://example.com/logo.png");
        Assert.Equal(".img", Path.GetExtension(cacheFile));
    }

    [Fact]
    public void EvictStaleCache_NonExistentDirectory_DoesNotThrow()
    {
        // Should silently return without throwing even if cache dir doesn't exist
        ImageService.EvictStaleCache();
    }

    [StaFact]
    public void LoadImage_NullPath_ReturnsNull()
    {
        Assert.Null(ImageService.LoadImage(null, 96));
    }

    [StaFact]
    public void LoadImage_EmptyPath_ReturnsNull()
    {
        Assert.Null(ImageService.LoadImage("", 96));
    }

    [StaFact]
    public void LoadImage_WhitespacePath_ReturnsNull()
    {
        Assert.Null(ImageService.LoadImage("   ", 96));
    }

    [StaFact]
    public void LoadImage_NonExistentLocalFile_ReturnsNull()
    {
        Assert.Null(ImageService.LoadImage(@"C:\NonExistent\DoesNotExist\logo.png", 96));
    }

    [StaFact]
    public void LoadImage_RemoteUrlWithoutCacheHit_ReturnsNull()
    {
        Assert.Null(ImageService.LoadImage("https://example.com/logo-not-cached.png", 96));
    }

    [Theory]
    [InlineData("https://example.com/art.png", true)]
    [InlineData("http://example.com/art.png", false)]
    [InlineData("https://localhost/art.png", false)]
    [InlineData("https://example.internal/art.png", false)]
    [InlineData("https://user:pass@example.com/art.png", false)]
    [InlineData("https://example.com:8443/art.png", false)]
    public void TryCreateRemoteUri_EnforcesPublicHttpsShape(string source, bool expected)
    {
        Assert.Equal(expected, ImageService.TryCreateRemoteUri(source, out _));
    }

    [Theory]
    [InlineData("8.8.8.8", true)]
    [InlineData("127.0.0.1", false)]
    [InlineData("10.0.0.1", false)]
    [InlineData("100.64.0.1", false)]
    [InlineData("169.254.169.254", false)]
    [InlineData("172.16.0.1", false)]
    [InlineData("192.168.1.1", false)]
    [InlineData("224.0.0.1", false)]
    [InlineData("::1", false)]
    [InlineData("2001:4860:4860::8888", true)]
    public void IsPublicAddress_RejectsNonPublicNetworks(string value, bool expected)
    {
        Assert.Equal(expected, ImageService.IsPublicAddress(IPAddress.Parse(value)));
    }

    [StaFact]
    public void ValidateImage_AcceptsPngJpegAndGif()
    {
        Assert.Equal("png", ImageService.ValidateImage(Encode(new PngBitmapEncoder())));
        Assert.Equal("jpeg", ImageService.ValidateImage(Encode(new JpegBitmapEncoder())));
        Assert.Equal("gif", ImageService.ValidateImage(Encode(new GifBitmapEncoder())));
    }

    [StaFact]
    public void ValidateImage_RejectsNonImageBytes()
    {
        Assert.Throws<InvalidDataException>(() =>
            ImageService.ValidateImage(Encoding.UTF8.GetBytes("<script>alert(1)</script>")));
    }

    [StaFact]
    public void ValidateImage_RejectsOversizedHeaderBeforeDecode()
    {
        var bytes = Encode(new PngBitmapEncoder());
        bytes[16] = 0x00;
        bytes[17] = 0x00;
        bytes[18] = 0x20;
        bytes[19] = 0x01;

        var error = Assert.Throws<InvalidDataException>(() =>
            ImageService.ValidateImage(bytes));
        Assert.Contains("dimensions", error.Message, StringComparison.OrdinalIgnoreCase);
    }

    private static byte[] Encode(BitmapEncoder encoder)
    {
        var pixels = new byte[] { 0x20, 0x80, 0xE0, 0xFF };
        var bitmap = BitmapSource.Create(
            1, 1, 96, 96, PixelFormats.Bgra32, null, pixels, 4);
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }
}
