namespace JapanExpert.AgentHost.Tests;

/// <summary>
/// Locates backend source files for tests that assert on host source structure.
/// The backend root is matched structurally rather than by solution file name so that
/// product renames do not break discovery.
/// </summary>
internal static class RepositoryPaths
{
    public const string RepositoryRootVariable = "JAPAN_EXPERT_REPOSITORY_ROOT";

    public static string BackendRoot { get; } = FindBackendRoot();

    public static string AgentHostFile(string fileName) =>
        Path.Combine(BackendRoot, "server", "agent-host", "JapanExpert.AgentHost", fileName);

    public static string ReadAgentHostFile(string fileName) =>
        File.ReadAllText(AgentHostFile(fileName));

    private static string FindBackendRoot()
    {
        var configuredRoot = Environment.GetEnvironmentVariable(RepositoryRootVariable);
        if (!string.IsNullOrWhiteSpace(configuredRoot) && IsBackendRoot(configuredRoot))
        {
            return configuredRoot;
        }

        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !IsBackendRoot(directory.FullName))
        {
            directory = directory.Parent;
        }

        return directory?.FullName
            ?? throw new DirectoryNotFoundException("Could not locate the backend repository root.");
    }

    private static bool IsBackendRoot(string path) =>
        Directory.Exists(Path.Combine(path, "server"))
        && File.Exists(Path.Combine(path, "Directory.Packages.props"))
        && Directory.EnumerateFiles(path, "*.slnx").Any();
}
