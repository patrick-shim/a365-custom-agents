using System.ComponentModel;
using JapanExpert.ExchangeRates;
using ModelContextProtocol.Server;

namespace JapanExpert.Mcp.Currency;

/// <summary>
/// Arithmetic-only currency conversion for a rate the caller already holds. It never claims the
/// supplied rate is current and never contacts a provider.
/// </summary>
[McpServerToolType]
public sealed class CurrencyTools
{
    [McpServerTool(Name = "convert_currency_with_rate")]
    [Description(
        "Converts an amount using a caller-supplied exchange rate. This tool performs arithmetic "
        + "only, does not claim the rate is current, and formats the result with the target "
        + "currency's minor-unit precision, so Japanese yen amounts have no decimal places.")]
    public CurrencyConversion ConvertCurrency(
        [Description("Amount in the source currency.")] decimal amount,
        [Description("Three-letter source currency code, such as USD.")] string sourceCurrency,
        [Description("Target currency units per one source currency unit.")] decimal exchangeRate,
        [Description("Three-letter target currency code. Defaults to JPY.")]
        string targetCurrency = CurrencyCodes.DefaultTravelCurrency,
        [Description("When the supplied exchange rate was observed, if known.")]
        DateTimeOffset? rateObservedAt = null)
    {
        var source = CurrencyCodes.Normalize(sourceCurrency, nameof(sourceCurrency));
        var target = CurrencyCodes.Normalize(targetCurrency, nameof(targetCurrency));
        ArgumentOutOfRangeException.ThrowIfNegative(amount);
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(exchangeRate, 0);

        var converted = CurrencyCodes.Round(amount * exchangeRate, target);
        return new CurrencyConversion(
            amount,
            source,
            converted,
            target,
            CurrencyCodes.Format(converted, target),
            CurrencyCodes.GetDecimalDigits(target),
            exchangeRate,
            rateObservedAt);
    }
}

/// <summary>Result of an arithmetic-only conversion.</summary>
public sealed record CurrencyConversion(
    decimal SourceAmount,
    string SourceCurrency,
    decimal TargetAmount,
    string TargetCurrency,
    string FormattedTargetAmount,
    int TargetCurrencyDecimalDigits,
    decimal ExchangeRate,
    DateTimeOffset? RateObservedAt);
