// Polyfill for init-only setters on .NET Framework 4.7.2
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("LISSTech.Billboard.Tests")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("LISSTech.Billboard.Host")]

namespace System.Runtime.CompilerServices
{
    internal static class IsExternalInit { }
}
