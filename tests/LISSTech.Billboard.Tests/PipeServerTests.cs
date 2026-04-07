using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using LISSTech.Billboard.Models;
using LISSTech.Billboard.Services;
using Xunit;

namespace Billboard.Tests;

public class PipeServerTests
{
    [Fact]
    public async Task WriteResult_ClientReceivesJson()
    {
        var pipeName = $"Billboard.Test.{Guid.NewGuid():N}";
        var result = BillboardResult.FromButton(
            new ButtonDefinition { Label = "OK", Value = "ok", Style = ButtonStyle.Primary }, 0);

        using var server = new PipeServer(pipeName);
        var serverTask = server.WaitForConnectionAndWriteAsync(result);

        using var client = new NamedPipeClientStream(".", pipeName, PipeDirection.In);
        await client.ConnectAsync(5000);

        // Read concurrently with the server write to avoid pipe buffer deadlock
        using var reader = new StreamReader(client, Encoding.UTF8);
        var readTask = reader.ReadToEndAsync();

        await serverTask;

        var json = await readTask;
        var received = JsonSerializer.Deserialize<BillboardResult>(json);

        Assert.NotNull(received);
        Assert.Equal("OK", received!.Button);
        Assert.Equal("ok", received.Value);
        Assert.Equal(0, received.Index);
        Assert.False(received.Dismissed);
    }

    [Fact]
    public async Task WriteResult_DismissResult_ClientReceivesNull()
    {
        var pipeName = $"Billboard.Test.{Guid.NewGuid():N}";
        var result = BillboardResult.FromDismiss();

        using var server = new PipeServer(pipeName);
        var serverTask = server.WaitForConnectionAndWriteAsync(result);

        using var client = new NamedPipeClientStream(".", pipeName, PipeDirection.In);
        await client.ConnectAsync(5000);

        // Read concurrently with the server write to avoid pipe buffer deadlock
        using var reader = new StreamReader(client, Encoding.UTF8);
        var readTask = reader.ReadToEndAsync();

        await serverTask;

        var json = await readTask;
        var received = JsonSerializer.Deserialize<BillboardResult>(json);

        Assert.NotNull(received);
        Assert.Null(received!.Button);
        Assert.True(received.Dismissed);
    }

    [Fact]
    public async Task WaitForConnection_NoClientConnects_ThrowsTimeoutException()
    {
        // Use a unique pipe name that no client will connect to
        var pipeName = $"Billboard.Test.NoClient.{Guid.NewGuid():N}";
        // Reduce the connect window by testing that the constructor does not pre-connect
        using var server = new PipeServer(pipeName);

        // The server waits 10 seconds for a client — this test verifies it throws rather
        // than hanging forever. We patch with a short delay by not connecting any client.
        // To keep the test fast, we cancel via the task itself: wrap in a short overall timeout.
        var cts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(15));
        var serverTask = server.WaitForConnectionAndWriteAsync(BillboardResult.FromDismiss());

        // The server will throw TimeoutException after 10 s on its own.
        var ex = await Assert.ThrowsAsync<TimeoutException>(() => serverTask);
        Assert.Contains("10 seconds", ex.Message);
    }
}
