using JapanExpert.ExchangeRates;
using JapanExpert.Mcp.Accommodation;
using JapanExpert.Mcp.Attractions;
using JapanExpert.Mcp.Currency;
using JapanExpert.Mcp.Weather;
using JapanExpert.Tourism;
using JapanExpert.Weather;
using Microsoft.Extensions.Logging.Abstractions;

namespace JapanExpert.Mcp.Tools.Tests;

/// <summary>Offline stubs used for schema inspection and tool behaviour tests.</summary>
internal static class ToolStubs
{
    internal static object CreateTarget(Type toolType)
    {
        if (toolType == typeof(AttractionTools))
        {
            return new AttractionTools(
                new StubTourismProvider(),
                NullLogger<AttractionTools>.Instance);
        }

        if (toolType == typeof(AccommodationTools))
        {
            return new AccommodationTools(
                new StubTourismProvider(),
                NullLogger<AccommodationTools>.Instance);
        }

        if (toolType == typeof(WeatherTools))
        {
            return new WeatherTools(
                new StubCurrentWeatherProvider(),
                new StubForecastProvider(),
                new StubAlertProvider(),
                NullLogger<WeatherTools>.Instance);
        }

        if (toolType == typeof(ExchangeRateTools))
        {
            return new ExchangeRateTools(
                new StubExchangeRateProvider(),
                NullLogger<ExchangeRateTools>.Instance);
        }

        if (toolType == typeof(CurrencyTools))
        {
            return new CurrencyTools();
        }

        throw new InvalidOperationException($"No stub is registered for {toolType.Name}.");
    }

    internal sealed class StubTourismProvider : ITourismProvider
    {
        public Task<IReadOnlyList<TourismPlace>> SearchAttractionsAsync(
            TourismSearchRequest request,
            CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<TourismPlace>>([]);

        public Task<IReadOnlyList<TourismPlace>> SearchAccommodationAsync(
            TourismSearchRequest request,
            CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<TourismPlace>>([]);
    }

    internal sealed class StubCurrentWeatherProvider : ICurrentWeatherProvider
    {
        public Task<CurrentWeatherResult?> GetCurrentWeatherAsync(
            WeatherLocation location,
            CancellationToken cancellationToken = default) =>
            Task.FromResult<CurrentWeatherResult?>(null);
    }

    internal sealed class StubForecastProvider : IWeatherForecastProvider
    {
        public JapanArea? LastArea { get; private set; }

        public int LastDays { get; private set; }

        public Task<WeatherForecastResult> GetForecastAsync(
            JapanArea area,
            int days,
            CancellationToken cancellationToken = default)
        {
            LastArea = area;
            LastDays = days;
            return Task.FromResult(new WeatherForecastResult(
                area.OfficeCode,
                area.PrefectureEnglish,
                area.PrefectureJapanese,
                "東京地方",
                "気象庁",
                new DateTimeOffset(2026, 8, 30, 8, 0, 0, TimeSpan.Zero),
                [],
                new WeatherSource(
                    "Japan Meteorological Agency (気象庁) prefecture forecast",
                    "https://www.jma.go.jp/bosai/forecast/",
                    "JMA terms",
                    "Test notice",
                    new DateTimeOffset(2026, 8, 30, 9, 0, 0, TimeSpan.Zero))));
        }
    }

    internal sealed class StubAlertProvider : IWeatherAlertProvider
    {
        public JapanArea? LastArea { get; private set; }

        public int LastLimit { get; private set; }

        public Task<IReadOnlyList<WeatherAlert>> GetAlertsAsync(
            JapanArea area,
            int limit,
            CancellationToken cancellationToken = default)
        {
            LastArea = area;
            LastLimit = limit;
            return Task.FromResult<IReadOnlyList<WeatherAlert>>([]);
        }
    }

    internal sealed class StubExchangeRateProvider(decimal rate = 147.32m) : IExchangeRateProvider
    {
        public string? LastTargetCurrency { get; private set; }

        public Task<ExchangeRateQuote> GetRateAsync(
            string sourceCurrency,
            string targetCurrency,
            DateOnly? asOfDate = null,
            CancellationToken cancellationToken = default)
        {
            LastTargetCurrency = targetCurrency;
            var observationDate = asOfDate ?? new DateOnly(2026, 8, 28);
            var observedAt = new DateTimeOffset(
                observationDate.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc));
            return Task.FromResult(new ExchangeRateQuote(
                sourceCurrency.ToUpperInvariant(),
                targetCurrency.ToUpperInvariant(),
                rate,
                observationDate,
                observedAt,
                new ExchangeRateSource(
                    "Frankfurter v2 (European Central Bank reference rates)",
                    "https://frankfurter.dev/",
                    "Latest ECB reference rate",
                    "Test freshness",
                    observedAt)));
        }
    }
}
