using System.Text;

namespace JapanExpert.Weather;

/// <summary>
/// Documented, bounded transformation of Japan Meteorological Agency forecast text and weather
/// telop codes into short English summaries. The original Japanese text is always preserved on
/// the result so the JMA wording remains available and attributable.
/// </summary>
public static class JmaWeatherSummary
{
    private static readonly (string Token, string English)[] Tokens =
    [
        ("くもり", "cloudy"),
        ("時々", "at times"),
        ("一時", "briefly"),
        ("のち", "later"),
        ("所により", "in places"),
        ("晴", "clear"),
        ("曇", "cloudy"),
        ("雨", "rain"),
        ("雪", "snow"),
        ("雷", "thunder"),
        ("風", "windy")
    ];

    /// <summary>Fallback English summary derived from a JMA weather telop code.</summary>
    public static string DescribeCode(string? weatherCode)
    {
        if (!int.TryParse(weatherCode, out var code))
        {
            return "Unknown conditions";
        }

        return (code / 100) switch
        {
            1 => "Clear",
            2 => "Cloudy",
            3 => "Rain",
            4 => "Snow",
            _ => "Unknown conditions"
        };
    }

    /// <summary>
    /// Builds an English summary from JMA Japanese forecast text, falling back to the telop code
    /// band when the text contains no recognized token.
    /// </summary>
    public static string Describe(string? japanese, string? weatherCode)
    {
        if (string.IsNullOrWhiteSpace(japanese))
        {
            return DescribeCode(weatherCode);
        }

        var words = new List<string>(6);
        var index = 0;
        while (index < japanese.Length && words.Count < 6)
        {
            var matched = false;
            foreach (var (token, english) in Tokens)
            {
                if (index + token.Length <= japanese.Length
                    && string.CompareOrdinal(japanese, index, token, 0, token.Length) == 0)
                {
                    if (words.Count == 0
                        || !string.Equals(words[^1], english, StringComparison.Ordinal))
                    {
                        words.Add(english);
                    }

                    index += token.Length;
                    matched = true;
                    break;
                }
            }

            if (!matched)
            {
                index++;
            }
        }

        if (words.Count == 0)
        {
            return DescribeCode(weatherCode);
        }

        var builder = new StringBuilder(string.Join(' ', words));
        builder[0] = char.ToUpperInvariant(builder[0]);
        return builder.ToString();
    }
}
