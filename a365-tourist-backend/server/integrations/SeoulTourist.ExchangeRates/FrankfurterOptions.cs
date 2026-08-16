using System.ComponentModel.DataAnnotations;

namespace SeoulTourist.ExchangeRates;

public sealed class FrankfurterOptions
{
    public const string SectionName = "Frankfurter";

    public bool Enabled { get; init; }

    [Url]
    public string BaseAddress { get; init; } = "https://api.frankfurter.dev/v1/";
}
