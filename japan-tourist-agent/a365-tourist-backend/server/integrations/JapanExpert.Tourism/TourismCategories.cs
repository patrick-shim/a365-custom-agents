using System.Collections.Frozen;

namespace JapanExpert.Tourism;

/// <summary>
/// Fixed Overpass tag selectors for Japan travel. Selectors are compile-time literals, so no
/// caller-supplied text is ever interpolated into an Overpass QL program.
/// </summary>
public static class TourismCategories
{
    /// <summary>Category accepted by every search tool that means "no category narrowing".</summary>
    public const string All = "all";

    private const string Named = "[\"name\"]";

    private static readonly string[] AllAttractionSelectors =
    [
        "[\"tourism\"~\"^(attraction|museum|viewpoint|gallery|artwork|theme_park|zoo|aquarium)$\"]" + Named,
        "[\"historic\"~\"^(castle|monument|memorial|ruins|archaeological_site)$\"]" + Named,
        "[\"amenity\"=\"place_of_worship\"][\"religion\"~\"^(shinto|buddhist)$\"]" + Named,
        "[\"heritage\"]" + Named
    ];

    private static readonly string[] AllAccommodationSelectors =
    [
        "[\"tourism\"~\"^(hotel|hostel|guest_house|motel|apartment|camp_site|alpine_hut)$\"]" + Named
    ];

    private static readonly FrozenDictionary<string, string[]> AttractionSelectors =
        new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            [All] = AllAttractionSelectors,
            ["attraction"] = ["[\"tourism\"=\"attraction\"]" + Named],
            ["museum"] = ["[\"tourism\"=\"museum\"]" + Named],
            ["viewpoint"] = ["[\"tourism\"=\"viewpoint\"]" + Named],
            ["gallery"] = ["[\"tourism\"=\"gallery\"]" + Named],
            ["artwork"] = ["[\"tourism\"=\"artwork\"]" + Named],
            ["theme_park"] = ["[\"tourism\"=\"theme_park\"]" + Named],
            ["zoo"] = ["[\"tourism\"=\"zoo\"]" + Named],
            ["aquarium"] = ["[\"tourism\"=\"aquarium\"]" + Named],
            ["castle"] = ["[\"historic\"=\"castle\"]" + Named],
            ["monument"] = ["[\"historic\"~\"^(monument|memorial)$\"]" + Named],
            ["ruins"] = ["[\"historic\"~\"^(ruins|archaeological_site)$\"]" + Named],
            ["shrine"] = ["[\"amenity\"=\"place_of_worship\"][\"religion\"=\"shinto\"]" + Named],
            ["temple"] = ["[\"amenity\"=\"place_of_worship\"][\"religion\"=\"buddhist\"]" + Named],
            ["heritage"] = ["[\"heritage\"]" + Named]
        }.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);

    private static readonly FrozenDictionary<string, string[]> AccommodationSelectors =
        new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            [All] = AllAccommodationSelectors,
            ["hotel"] = ["[\"tourism\"=\"hotel\"]" + Named],
            ["hostel"] = ["[\"tourism\"=\"hostel\"]" + Named],
            ["guest_house"] = ["[\"tourism\"=\"guest_house\"]" + Named],
            ["motel"] = ["[\"tourism\"=\"motel\"]" + Named],
            ["apartment"] = ["[\"tourism\"=\"apartment\"]" + Named],
            ["camp_site"] = ["[\"tourism\"=\"camp_site\"]" + Named],
            ["alpine_hut"] = ["[\"tourism\"=\"alpine_hut\"]" + Named]
        }.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);

    /// <summary>Supported attraction categories, in the order surfaced to the model.</summary>
    public static IReadOnlyList<string> AttractionCategories { get; } =
        [.. AttractionSelectors.Keys.Order(StringComparer.Ordinal)];

    /// <summary>Supported accommodation types, in the order surfaced to the model.</summary>
    public static IReadOnlyList<string> AccommodationTypes { get; } =
        [.. AccommodationSelectors.Keys.Order(StringComparer.Ordinal)];

    /// <summary>Resolves an attraction category to its fixed Overpass selectors.</summary>
    public static IReadOnlyList<string> ResolveAttractionSelectors(string category) =>
        Resolve(AttractionSelectors, category, AttractionCategories, nameof(category));

    /// <summary>Resolves an accommodation type to its fixed Overpass selectors.</summary>
    public static IReadOnlyList<string> ResolveAccommodationSelectors(string accommodationType) =>
        Resolve(
            AccommodationSelectors,
            accommodationType,
            AccommodationTypes,
            nameof(accommodationType));

    private static string[] Resolve(
        FrozenDictionary<string, string[]> selectors,
        string value,
        IReadOnlyList<string> supported,
        string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        if (selectors.TryGetValue(value.Trim(), out var resolved))
        {
            return resolved;
        }

        throw new ArgumentException(
            $"Unsupported value '{value.Trim()}'. Supported values are: {string.Join(", ", supported)}.",
            parameterName);
    }
}
