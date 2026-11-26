---
paths:
  - "**/*.cs"
  - "**/*.csproj"
  - "**/*.sln"
  - "**/*.slnx"
  - "**/Directory.Build.props"
  - "**/Directory.Packages.props"
---

# C# / .NET (claude-kit)

- Build and test through `.claude/kit/check.sh`, which names the solution explicitly. Adding or upgrading a package
  is an ask-first change: use `dotnet add package`, and with central package management (`Directory.Packages.props`)
  set the version there, never in the `.csproj`.
- Nullable reference types stay on. `!` (null-forgiving) needs a one-line reason; prefer a guard or a better type.
  Don't silence warnings with `#pragma` or `<NoWarn>` to get a green build.
- Async all the way: `async Task` (never `async void` outside event handlers), pass `CancellationToken` through,
  and never block on `.Result` or `.Wait()`. `ConfigureAwait(false)` in libraries, not in app code.
- Immutable by default: `record` for values and DTOs, `init` setters, `readonly` fields, `sealed` classes unless
  designed for inheritance. Return `IReadOnlyList<T>`/`IReadOnlyCollection<T>` from public APIs.
- Dependencies come in through constructors (primary constructors are fine) and are registered in one place per
  feature (an `IServiceCollection` extension). No service locator, no `static` mutable state.
- Configuration through the options pattern (`IOptions<T>` bound and validated at startup), never raw
  `IConfiguration["key"]` reads deep in the code. Secrets come from user-secrets or the environment, never `appsettings.json`.
- Errors: throw specific exceptions for bugs; return a result type for expected failures if the project uses one.
  Never catch `Exception` without rethrowing or logging it with context.
- Logging with `ILogger<T>` and message templates (`"Order {OrderId} paid"`), not string interpolation. Never log
  secrets or personal data.
- EF Core: `AsNoTracking()` for reads, project to DTOs with `Select`, no queries inside loops (N+1), and migrations
  are reviewed like code.
- Tests: one behaviour per test, named after it, using the project's framework (xUnit, NUnit, MSTest or TUnit).
  Real dependencies through Testcontainers or `WebApplicationFactory` at the edges; fakes over mocks for your own interfaces.
- Formatting follows `.editorconfig` and `dotnet format`; don't hand-format around it.
- Deeper guidance is optional: `.claude/kit/dotnet-pack.sh --list` shows third-party C# skills you can install.
