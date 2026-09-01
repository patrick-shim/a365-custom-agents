using System.Text.RegularExpressions;

namespace KoreaExpert.ExchangeRates;

internal static partial class CurrencyCodes
{
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

    [GeneratedRegex("^[A-Z]{3}$", RegexOptions.CultureInvariant)]
    private static partial Regex CurrencyCode();
}
