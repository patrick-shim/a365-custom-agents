using System.ComponentModel.DataAnnotations;

namespace KoreaExpert.ExchangeRates;

public sealed class ForexRateApiOptions
{
    public const string SectionName = "ForexRateApi";

    public bool Enabled { get; init; }

    [Required]
    [Url]
    public string BaseAddress { get; init; } = "https://api.forexrateapi.com/v1/";

    public string ApiKey { get; init; } = string.Empty;
}
