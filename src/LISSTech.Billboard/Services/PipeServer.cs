using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using LISSTech.Billboard.Models;

namespace LISSTech.Billboard.Services;

public sealed class PipeServer : IDisposable
{
    private readonly NamedPipeServerStream _pipe;

    public PipeServer(string pipeName)
    {
        _pipe = new NamedPipeServerStream(
            pipeName,
            PipeDirection.Out,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous);
    }

    public async Task WaitForConnectionAndWriteAsync(BillboardResult result)
    {
        var connectTask = _pipe.WaitForConnectionAsync();
        var completed = await Task.WhenAny(connectTask, Task.Delay(TimeSpan.FromSeconds(10)));
        if (completed != connectTask)
            throw new TimeoutException("No pipe client connected within 10 seconds.");
        await connectTask; // Propagate any exception from the connect task

        var json = JsonSerializer.Serialize(result);
        var bytes = Encoding.UTF8.GetBytes(json);

        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await _pipe.WriteAsync(bytes, 0, bytes.Length, cts.Token);
        await _pipe.FlushAsync(cts.Token);
        _pipe.Close();
    }

    public void Dispose()
    {
        _pipe.Dispose();
    }
}
