using Microsoft.VisualStudio.TestTools.UnitTesting;
using SeoulTourist.Direct;

namespace SeoulTourist.Direct.Tests;

[TestClass]
public sealed class SensitivePromptListTests
{
    [TestMethod]
    public async Task LoadAsyncReadsTheFrontendOwnedSyntheticPromptList()
    {
        var promptPath = Path.Combine(GetRepositoryRoot(), "direct", "sensitive-information-type-test.json");

        var prompts = await SensitivePromptList.LoadAsync(promptPath);

        Assert.IsNotEmpty(prompts);
        Assert.IsTrue(prompts.All(prompt => !string.IsNullOrWhiteSpace(prompt)));
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
