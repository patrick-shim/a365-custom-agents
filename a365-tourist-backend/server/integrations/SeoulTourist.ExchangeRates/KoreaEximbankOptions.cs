using System.ComponentModel.DataAnnotations;

namespace SeoulTourist.ExchangeRates;

public sealed class KoreaEximbankOptions
{
    public const string SectionName = "KoreaEximbank";

    public bool Enabled { get; init; }

    [Required]
    [Url]
    public string BaseAddress { get; init; } = "https://oapi.koreaexim.go.kr/";

    public string AuthKey { get; init; } = string.Empty;

    [Range(0, 7)]
    public int MaximumLookbackDays { get; init; } = 7;
}
