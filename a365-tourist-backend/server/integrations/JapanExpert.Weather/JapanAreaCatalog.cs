using System.Collections.Frozen;

namespace JapanExpert.Weather;

/// <summary>A validated Japan Meteorological Agency forecast office for one prefecture.</summary>
public sealed record JapanArea(
    string OfficeCode,
    string PrefectureEnglish,
    string PrefectureJapanese,
    string MatchStem);

/// <summary>
/// Validated prefecture-to-JMA-forecast-office mapping covering all 47 prefectures, plus the
/// documented Hokkaido regional offices and Okinawa island offices. Only codes in this catalog
/// are accepted, so an arbitrary office code can never be injected into a JMA request path.
/// </summary>
public static class JapanAreaCatalog
{
    /// <summary>Tokyo, the documented default forecast office.</summary>
    public const string DefaultOfficeCode = "130000";

    /// <summary>Tokyo, the documented default prefecture name.</summary>
    public const string DefaultPrefecture = "Tokyo";

    private static readonly JapanArea[] Areas =
    [
        new("016000", "Hokkaido", "北海道", "北海道"),
        new("011000", "Hokkaido Soya", "北海道", "宗谷"),
        new("012000", "Hokkaido Kamikawa Rumoi", "北海道", "上川"),
        new("013000", "Hokkaido Abashiri Kitami Monbetsu", "北海道", "網走"),
        new("014100", "Hokkaido Kushiro Nemuro Tokachi", "北海道", "釧路"),
        new("015000", "Hokkaido Iburi Hidaka", "北海道", "胆振"),
        new("017000", "Hokkaido Oshima Hiyama", "北海道", "渡島"),
        new("020000", "Aomori", "青森県", "青森"),
        new("030000", "Iwate", "岩手県", "岩手"),
        new("040000", "Miyagi", "宮城県", "宮城"),
        new("050000", "Akita", "秋田県", "秋田"),
        new("060000", "Yamagata", "山形県", "山形"),
        new("070000", "Fukushima", "福島県", "福島"),
        new("080000", "Ibaraki", "茨城県", "茨城"),
        new("090000", "Tochigi", "栃木県", "栃木"),
        new("100000", "Gunma", "群馬県", "群馬"),
        new("110000", "Saitama", "埼玉県", "埼玉"),
        new("120000", "Chiba", "千葉県", "千葉"),
        new("130000", "Tokyo", "東京都", "東京"),
        new("140000", "Kanagawa", "神奈川県", "神奈川"),
        new("150000", "Niigata", "新潟県", "新潟"),
        new("160000", "Toyama", "富山県", "富山"),
        new("170000", "Ishikawa", "石川県", "石川"),
        new("180000", "Fukui", "福井県", "福井"),
        new("190000", "Yamanashi", "山梨県", "山梨"),
        new("200000", "Nagano", "長野県", "長野"),
        new("210000", "Gifu", "岐阜県", "岐阜"),
        new("220000", "Shizuoka", "静岡県", "静岡"),
        new("230000", "Aichi", "愛知県", "愛知"),
        new("240000", "Mie", "三重県", "三重"),
        new("250000", "Shiga", "滋賀県", "滋賀"),
        new("260000", "Kyoto", "京都府", "京都"),
        new("270000", "Osaka", "大阪府", "大阪"),
        new("280000", "Hyogo", "兵庫県", "兵庫"),
        new("290000", "Nara", "奈良県", "奈良"),
        new("300000", "Wakayama", "和歌山県", "和歌山"),
        new("310000", "Tottori", "鳥取県", "鳥取"),
        new("320000", "Shimane", "島根県", "島根"),
        new("330000", "Okayama", "岡山県", "岡山"),
        new("340000", "Hiroshima", "広島県", "広島"),
        new("350000", "Yamaguchi", "山口県", "山口"),
        new("360000", "Tokushima", "徳島県", "徳島"),
        new("370000", "Kagawa", "香川県", "香川"),
        new("380000", "Ehime", "愛媛県", "愛媛"),
        new("390000", "Kochi", "高知県", "高知"),
        new("400000", "Fukuoka", "福岡県", "福岡"),
        new("410000", "Saga", "佐賀県", "佐賀"),
        new("420000", "Nagasaki", "長崎県", "長崎"),
        new("430000", "Kumamoto", "熊本県", "熊本"),
        new("440000", "Oita", "大分県", "大分"),
        new("450000", "Miyazaki", "宮崎県", "宮崎"),
        new("460100", "Kagoshima", "鹿児島県", "鹿児島"),
        new("471000", "Okinawa", "沖縄県", "沖縄"),
        new("472000", "Okinawa Daito", "沖縄県", "大東"),
        new("473000", "Okinawa Miyako", "沖縄県", "宮古"),
        new("474000", "Okinawa Yaeyama", "沖縄県", "石垣")
    ];

    private static readonly FrozenDictionary<string, JapanArea> ByOfficeCode =
        Areas.ToFrozenDictionary(area => area.OfficeCode, StringComparer.Ordinal);

    private static readonly FrozenDictionary<string, JapanArea> ByName = BuildNameIndex();

    /// <summary>Every accepted JMA forecast office code.</summary>
    public static IReadOnlyList<string> OfficeCodes { get; } =
        [.. Areas.Select(area => area.OfficeCode).Order(StringComparer.Ordinal)];

    /// <summary>Prefecture names accepted by the weather tools, in stable order.</summary>
    public static IReadOnlyList<string> PrefectureNames { get; } =
        [.. Areas.Select(area => area.PrefectureEnglish).Distinct(StringComparer.Ordinal)];

    /// <summary>
    /// Resolves a prefecture name or an explicit documented office code to a validated area.
    /// An explicit office code always wins so an operator can target a Hokkaido or Okinawa office.
    /// </summary>
    public static JapanArea Resolve(string? prefecture, string? officeCode = null)
    {
        if (!string.IsNullOrWhiteSpace(officeCode))
        {
            var trimmed = officeCode.Trim();
            if (ByOfficeCode.TryGetValue(trimmed, out var byCode))
            {
                return byCode;
            }

            throw new ArgumentException(
                $"'{trimmed}' is not a documented JMA forecast office code. Supported codes are: "
                + string.Join(", ", OfficeCodes)
                + ".",
                nameof(officeCode));
        }

        var name = string.IsNullOrWhiteSpace(prefecture) ? DefaultPrefecture : prefecture.Trim();
        if (ByName.TryGetValue(Normalize(name), out var byName))
        {
            return byName;
        }

        throw new ArgumentException(
            $"'{name}' is not a supported Japanese prefecture. Supported prefectures are: "
            + string.Join(", ", PrefectureNames)
            + ".",
            nameof(prefecture));
    }

    private static FrozenDictionary<string, JapanArea> BuildNameIndex()
    {
        var index = new Dictionary<string, JapanArea>(StringComparer.Ordinal);
        foreach (var area in Areas)
        {
            Add(index, area.PrefectureEnglish, area);
            Add(index, area.PrefectureJapanese, area);
            Add(index, area.MatchStem, area);
        }

        return index.ToFrozenDictionary(StringComparer.Ordinal);
    }

    private static void Add(Dictionary<string, JapanArea> index, string key, JapanArea area)
    {
        var normalized = Normalize(key);
        if (normalized.Length > 0)
        {
            index.TryAdd(normalized, area);
        }
    }

    /// <summary>
    /// Normalizes a prefecture name: case-insensitive, whitespace and separators removed, and the
    /// common romanized suffixes (-ken, -fu, -to, -do, prefecture) dropped.
    /// </summary>
    private static string Normalize(string value)
    {
        var trimmed = value.Trim().ToUpperInvariant();
        var characters = trimmed
            .Where(character => character is not ('-' or ' ' or '\u2010' or '\u30fc' or '.'))
            .ToArray();
        var compact = new string(characters);
        string[] suffixes = ["PREFECTURE", "KEN", "FU", "TO", "DO"];
        foreach (var suffix in suffixes)
        {
            if (compact.Length > suffix.Length + 2
                && compact.EndsWith(suffix, StringComparison.Ordinal))
            {
                return compact[..^suffix.Length];
            }
        }

        return compact;
    }
}
