namespace KoreaExpert.ExchangeRates;

public sealed record ExchangeRateSource(
    string Name,
    string AttributionUrl,
    string RateType,
    string FreshnessNote,
    DateTimeOffset RetrievedAt);

public sealed record ExchangeRateQuote(
    string SourceCurrency,
    string TargetCurrency,
    decimal Rate,
    DateTimeOffset ObservedAt,
    ExchangeRateSource Source);
