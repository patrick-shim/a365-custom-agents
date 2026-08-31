using System.Text.RegularExpressions;
using JapanExpert.Direct;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace JapanExpert.Direct.Tests;

[TestClass]
public sealed class SensitivePromptListTests
{
    [TestMethod]
    public async Task LoadAsyncReadsTheFrontendOwnedSyntheticPromptList()
    {
        var promptPath = Path.Combine(GetRepositoryRoot(), "direct", "sensitive-information-type-test.json");

        var prompts = await SensitivePromptList.LoadAsync(promptPath);

        Assert.HasCount(3, prompts);
        Assert.IsTrue(prompts.All(prompt => !string.IsNullOrWhiteSpace(prompt)));
        Assert.IsTrue(prompts.Any(prompt => prompt.Contains("Japan passport", StringComparison.Ordinal)));
        Assert.IsTrue(prompts.Any(prompt => prompt.Contains("Japanese residence card", StringComparison.Ordinal)));
        Assert.IsTrue(prompts.Any(prompt => prompt.Contains("Credit card", StringComparison.Ordinal)));
        Assert.HasCount(1, prompts.Where(prompt => Regex.IsMatch(prompt, @"\bZZ[0-9]{7}\b")));
        Assert.HasCount(1, prompts.Where(prompt => Regex.IsMatch(prompt, @"\bZZ[0-9]{8}ZZ\b")));
        Assert.HasCount(1, prompts.Where(prompt => Regex.IsMatch(prompt, @"\b4111(?:-1111){3}\b")));
        Assert.IsFalse(prompts.Any(prompt =>
            prompt.Contains("South Korean", StringComparison.OrdinalIgnoreCase)
            || prompt.Contains("resident-registration", StringComparison.OrdinalIgnoreCase)));
    }

    [TestMethod]
    public async Task LoadAsyncRejectsEmptyLists()
    {
        var temporaryPath = Path.GetTempFileName();
        try
        {
            await File.WriteAllTextAsync(temporaryPath, "[]");

            await Assert.ThrowsExactlyAsync<SensitivePromptListException>(
                () => SensitivePromptList.LoadAsync(temporaryPath));
        }
        finally
        {
            File.Delete(temporaryPath);
        }
    }

    private static string GetRepositoryRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            if (File.Exists(Path.Combine(current.FullName, "backend-contract.lock.json")))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        throw new InvalidOperationException("Could not locate the OBO Direct Line frontend root.");
    }
}
