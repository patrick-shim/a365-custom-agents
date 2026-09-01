using System.ComponentModel.DataAnnotations;

namespace KoreaExpert.Weather;

public sealed class OpenMeteoOptions
{
    public const string SectionName = "OpenMeteo";

    [Required]
    [Url]
    public string BaseAddress { get; init; } = "https://api.open-meteo.com/v1/";

    public string ApiKey { get; init; } = string.Empty;

    public bool RequireCommercialLicense { get; init; }
}
