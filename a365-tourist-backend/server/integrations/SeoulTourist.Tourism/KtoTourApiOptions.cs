using System.ComponentModel.DataAnnotations;

namespace SeoulTourist.Tourism;

public sealed class KtoTourApiOptions
{
    public const string SectionName = "KtoTourApi";

    [Required]
    [Url]
    public string BaseAddress { get; init; } = "https://apis.data.go.kr/B551011/";

    [Required]
    [RegularExpression("^(Kor|Eng|Jpn|Chs|Cht|Ger|Fre|Spn|Rus)Service2$")]
    public string ServiceName { get; init; } = "EngService2";

    public string ServiceKey { get; init; } = string.Empty;

    [Required]
    public string MobileApplication { get; init; } = "SeoulTouristAgent";

    [Required]
    [RegularExpression("^(IOS|AND|WEB|ETC)$")]
    public string MobileOperatingSystem { get; init; } = "ETC";
}
