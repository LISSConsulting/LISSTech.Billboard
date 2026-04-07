// Polyfill for init-only setters on .NET Framework 4.7.2
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("Billboard.Tests")]

namespace System.Runtime.CompilerServices
{
    internal static class IsExternalInit { }
}
