using System.ComponentModel.DataAnnotations;

namespace SeoulTourist.Weather;

public sealed class OpenWeatherOptions
{
    public const string SectionName = "OpenWeather";

    public bool Enabled { get; init; }

    [Required]
    [Url]
    public string BaseAddress { get; init; } = "https://api.openweathermap.org/data/4.0/";

    public string ApiKey { get; init; } = string.Empty;

    [Range(1, 10)]
    public int MaximumAlerts { get; init; } = 5;
}
