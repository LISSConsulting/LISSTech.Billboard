using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using LISSTech.Billboard.Services;
using Xunit;

namespace Billboard.Tests;

public class LogoServiceTests
{
    [Fact]
    public void GetCacheFile_SamePath_ReturnsSamePath()
    {
        var path1 = LogoService.GetCacheFile("https://example.com/logo.png");
        var path2 = LogoService.GetCacheFile("https://example.com/logo.png");
        Assert.Equal(path1, path2);
    }

    [Fact]
    public void GetCacheFile_DifferentPaths_DifferentCacheFiles()
    {
        var path1 = LogoService.GetCacheFile("https://example.com/logo1.png");
        var path2 = LogoService.GetCacheFile("https://example.com/logo2.png");
        Assert.NotEqual(path1, path2);
    }

    [Fact]
    public void GetCacheFile_HasFull64CharHex()
    {
        var cacheFile = LogoService.GetCacheFile("test");
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

        var cacheFile = LogoService.GetCacheFile(input);
        var filename = Path.GetFileNameWithoutExtension(cacheFile);
        Assert.Equal(expectedHex, filename);
    }

    [Fact]
    public void GetCacheFile_HasPngExtension()
    {
        var cacheFile = LogoService.GetCacheFile("https://example.com/logo.png");
        Assert.Equal(".png", Path.GetExtension(cacheFile));
    }

    [Fact]
    public void EvictStaleCache_NonExistentDirectory_DoesNotThrow()
    {
        // Should silently return without throwing even if cache dir doesn't exist
        LogoService.EvictStaleCache();
    }

    [StaFact]
    public void LoadMspLogo_NullPath_ReturnsNull()
    {
        Assert.Null(LogoService.LoadMspLogo(null));
    }

    [StaFact]
    public void LoadMspLogo_EmptyPath_ReturnsNull()
    {
        Assert.Null(LogoService.LoadMspLogo(""));
    }

    [StaFact]
    public void LoadMspLogo_WhitespacePath_ReturnsNull()
    {
        Assert.Null(LogoService.LoadMspLogo("   "));
    }

    [StaFact]
    public void LoadMspLogo_NonExistentLocalFile_ReturnsNull()
    {
        Assert.Null(LogoService.LoadMspLogo(@"C:\NonExistent\DoesNotExist\logo.png"));
    }

    [StaFact]
    public void LoadMspLogo_RemoteUrlWithoutCacheHit_ReturnsNull()
    {
        // Remote URL with no cached file returns null immediately (async download is caller's responsibility)
        Assert.Null(LogoService.LoadMspLogo("https://example.com/logo-not-cached.png"));
    }
}
