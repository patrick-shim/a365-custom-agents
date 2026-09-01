namespace JapanExpert.ExchangeRates;

/// <summary>Provenance for a published exchange rate observation.</summary>
public sealed record ExchangeRateSource(
    string Name,
    string AttributionUrl,
    string RateType,
    string FreshnessNote,
    DateTimeOffset RetrievedAt);

/// <summary>
/// A single exchange rate observation. <see cref="ObservedAt"/> is the publication date of the
/// underlying reference rate, not the time the tool ran.
/// </summary>
public sealed record ExchangeRateQuote(
    string SourceCurrency,
    string TargetCurrency,
    decimal Rate,
    DateOnly ObservationDate,
    DateTimeOffset ObservedAt,
    ExchangeRateSource Source);
