using System.ComponentModel;
using System.Text.RegularExpressions;
using ModelContextProtocol.Server;

namespace KoreaExpert.Mcp.Currency;

[McpServerToolType]
public sealed partial class CurrencyTools
{
    [McpServerTool(Name = "convert_currency_with_rate")]
    [Description("Converts an amount using a caller-supplied exchange rate. This tool performs arithmetic and does not claim the rate is current.")]
    public CurrencyConversion ConvertCurrency(
        [Description("Amount in the source currency.")] decimal amount,
        [Description("Three-letter source currency code, such as USD.")] string sourceCurrency,
        [Description("Three-letter target currency code, such as KRW.")] string targetCurrency,
        [Description("Target currency units per one source currency unit.")] decimal exchangeRate,
        [Description("When the supplied exchange rate was observed, if known.")] DateTimeOffset? rateObservedAt = null)
    {
        var source = NormalizeCurrencyCode(sourceCurrency);
        var target = NormalizeCurrencyCode(targetCurrency);
        ArgumentOutOfRangeException.ThrowIfNegative(amount);
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(exchangeRate, 0);

        return new CurrencyConversion(
            amount,
            source,
            decimal.Round(amount * exchangeRate, 2, MidpointRounding.ToEven),
            target,
            exchangeRate,
            rateObservedAt);
    }

    private static string NormalizeCurrencyCode(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        var normalized = value.Trim().ToUpperInvariant();
        if (!CurrencyCode().IsMatch(normalized))
        {
            throw new ArgumentException("Currency codes must contain exactly three ASCII letters.", nameof(value));
        }

        return normalized;
    }

    [GeneratedRegex("^[A-Z]{3}$", RegexOptions.CultureInvariant)]
    private static partial Regex CurrencyCode();
}

public sealed record CurrencyConversion(
    decimal SourceAmount,
    string SourceCurrency,
    decimal TargetAmount,
    string TargetCurrency,
    decimal ExchangeRate,
    DateTimeOffset? RateObservedAt);
