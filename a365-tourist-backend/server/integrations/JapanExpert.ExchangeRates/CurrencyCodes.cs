using System.Collections.Frozen;
using System.Globalization;
using System.Text.RegularExpressions;

namespace JapanExpert.ExchangeRates;

/// <summary>
/// ISO 4217 helpers for the Japan Tourist Assistant currency contract, including the zero-decimal
/// currencies (Japanese yen among them) that must not be rounded to two decimal places.
/// </summary>
public static partial class CurrencyCodes
{
    /// <summary>Default travel currency for the Japan Tourist Assistant product.</summary>
    public const string DefaultTravelCurrency = "JPY";

    /// <summary>Base currency published by the European Central Bank reference rates.</summary>
    public const string EuroCurrency = "EUR";

    private static readonly FrozenSet<string> ZeroDecimalCurrencies =
        new[]
        {
            "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW",
            "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"
        }.ToFrozenSet(StringComparer.Ordinal);

    private static readonly FrozenSet<string> ThreeDecimalCurrencies =
        new[] { "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND" }
            .ToFrozenSet(StringComparer.Ordinal);

    /// <summary>Normalizes and validates a three-letter ISO 4217 code.</summary>
    public static string Normalize(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        var normalized = value.Trim().ToUpperInvariant();
        if (!CurrencyCode().IsMatch(normalized))
        {
            throw new ArgumentException(
                "Currency codes must contain exactly three ASCII letters.",
                parameterName);
        }

        return normalized;
    }

    /// <summary>Minor-unit digits for a currency; the Japanese yen is zero-decimal.</summary>
    public static int GetDecimalDigits(string currencyCode)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(currencyCode);
        var normalized = currencyCode.Trim().ToUpperInvariant();
        if (ZeroDecimalCurrencies.Contains(normalized))
        {
            return 0;
        }

        return ThreeDecimalCurrencies.Contains(normalized) ? 3 : 2;
    }

    /// <summary>Rounds an amount to the currency's minor-unit precision.</summary>
    public static decimal Round(decimal amount, string currencyCode) =>
        decimal.Round(amount, GetDecimalDigits(currencyCode), MidpointRounding.ToEven);

    /// <summary>
    /// Formats an amount using the currency's minor-unit precision and an invariant grouped
    /// layout, so a yen amount never renders with misleading decimal places.
    /// </summary>
    public static string Format(decimal amount, string currencyCode)
    {
        var code = currencyCode.Trim().ToUpperInvariant();
        var digits = GetDecimalDigits(code);
        var rounded = decimal.Round(amount, digits, MidpointRounding.ToEven);
        var formatted = rounded.ToString(
            "N" + digits.ToString(CultureInfo.InvariantCulture),
            CultureInfo.InvariantCulture);
        return string.Create(CultureInfo.InvariantCulture, $"{formatted} {code}");
    }

    [GeneratedRegex("^[A-Z]{3}$", RegexOptions.CultureInvariant)]
    private static partial Regex CurrencyCode();
}
