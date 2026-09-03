using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pactman.NonprofitCheckPlus.Models;
using Xunit;

namespace Pactman.NonprofitCheckPlus.Tests;

/// <summary>
/// Holds <c>response-contract.json</c> and the typed model in sync.
/// </summary>
/// <remarks>
/// The contract is what this package promises each response looks like. The typed
/// properties on <see cref="Nonprofit"/> are what an editor tells a developer to
/// expect. A field in one and not the other is drift, and drift is how an SDK starts
/// lying about the API.
/// <para>
/// Rather than re-deriving wire names from property names — a mapping that would
/// itself need testing — these tests feed the model a sentinel response built from the
/// contract and watch which properties light up. Removing one contract field must
/// darken exactly one property, which pins the mapping in both directions without
/// naming it twice.
/// </para>
/// </remarks>
public class ResponseContractTests
{
    private const string Sentinel = "sentinel";

    private static JsonObject Contract { get; } =
        JsonNode.Parse(File.ReadAllText("response-contract.json"))!.AsObject();

    private static JsonObject Section(string name)
    {
        Assert.True(Contract.ContainsKey(name), $"The contract declares no `{name}` section.");

        return Contract[name]!.AsObject();
    }

    private static IReadOnlyList<string> NonprofitFields() => Section("nonprofit").Select(f => f.Key).ToList();

    private static PropertyInfo[] TypedProperties(Type type) => type
        .GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
        .Where(property => property.GetIndexParameters().Length == 0)
        .ToArray();

    /// <summary>A response carrying every contract field, minus the one named.</summary>
    private static Nonprofit SentinelNonprofit(string? without = null)
    {
        var organization = new JsonObject();

        foreach (var field in Section("nonprofit"))
        {
            if (field.Key == without)
            {
                continue;
            }

            organization[field.Key] = SentinelFor(field.Value!.GetValue<string>());
        }

        return new Nonprofit(JsonSerializer.Deserialize<JsonElement>(organization.ToJsonString()));
    }

    private static JsonNode SentinelFor(string shape)
    {
        if (shape.Contains("boolean", StringComparison.Ordinal))
        {
            return JsonValue.Create(true)!;
        }

        if (shape.Contains("array", StringComparison.Ordinal))
        {
            return new JsonArray { new JsonObject { ["organization_type"] = Sentinel } };
        }

        return JsonValue.Create(Sentinel)!;
    }

    private static bool IsSet(PropertyInfo property, object target)
    {
        var value = property.GetValue(target);

        return value switch
        {
            null => false,
            ICollection collection => collection.Count > 0,
            IEnumerable enumerable and not string => enumerable.Cast<object>().Any(),
            _ => true,
        };
    }

    [Fact]
    public void EveryTypedPropertyReadsAFieldTheContractDeclares()
    {
        var organization = SentinelNonprofit();

        var unbacked = TypedProperties(typeof(Nonprofit))
            .Where(property => !IsSet(property, organization))
            .Select(property => property.Name)
            .ToList();

        Assert.True(
            unbacked.Count == 0,
            "These Nonprofit properties read a field response-contract.json does not declare: "
            + string.Join(", ", unbacked));
    }

    [Fact]
    public void EveryContractFieldIsReadByExactlyOneTypedProperty()
    {
        var properties = TypedProperties(typeof(Nonprofit));
        var complete = SentinelNonprofit();

        foreach (var field in NonprofitFields())
        {
            var reduced = SentinelNonprofit(without: field);

            var darkened = properties
                .Where(property => IsSet(property, complete) && !IsSet(property, reduced))
                .Select(property => property.Name)
                .ToList();

            Assert.True(
                darkened.Count == 1,
                $"Contract field '{field}' is read by {darkened.Count} typed properties "
                + $"({string.Join(", ", darkened)}); expected exactly one.");
        }
    }

    [Theory]
    [InlineData("Pub78Fields", typeof(Pub78Source))]
    [InlineData("BmfFields", typeof(BmfSource))]
    [InlineData("AroeFields", typeof(AroeSource))]
    [InlineData("OfacFields", typeof(OfacSource))]
    public void EveryProjectedFieldExistsInTheContract(string mappingName, Type sourceType)
    {
        var contract = NonprofitFields();

        foreach (var pair in Mapping(mappingName))
        {
            Assert.True(
                contract.Contains(pair.Value),
                $"{sourceType.Name} maps '{pair.Key}' to '{pair.Value}', which the contract does not declare.");
        }
    }

    [Theory]
    [InlineData("Pub78Fields", typeof(Pub78Source))]
    [InlineData("BmfFields", typeof(BmfSource))]
    [InlineData("AroeFields", typeof(AroeSource))]
    [InlineData("OfacFields", typeof(OfacSource))]
    public void EveryProjectedFieldIsReadByExactlyOneSourceProperty(string mappingName, Type sourceType)
    {
        var mapping = Mapping(mappingName);
        var properties = TypedProperties(sourceType);
        var complete = BuildSource(sourceType, mapping, null);

        var unbacked = properties.Where(property => !IsSet(property, complete)).Select(p => p.Name).ToList();

        Assert.True(
            unbacked.Count == 0,
            $"These {sourceType.Name} properties read a key the projection does not produce: "
            + string.Join(", ", unbacked));

        foreach (var pair in mapping)
        {
            var reduced = BuildSource(sourceType, mapping, pair.Key);

            var darkened = properties
                .Where(property => IsSet(property, complete) && !IsSet(property, reduced))
                .Select(property => property.Name)
                .ToList();

            Assert.True(
                darkened.Count == 1,
                $"{sourceType.Name} key '{pair.Key}' is read by {darkened.Count} properties "
                + $"({string.Join(", ", darkened)}); expected exactly one.");
        }
    }

    [Fact]
    public void TheEnvelopeContractCoversTheFieldsTheResultReads()
    {
        var envelope = Section("envelope");

        foreach (var field in new[] { "code", "message", "errors", "timeTaken", "nonprofit_check_count" })
        {
            Assert.True(envelope.ContainsKey(field), $"The envelope contract omits `{field}`.");
        }
    }

    [Fact]
    public void TheErrorDetailContractCoversTheFieldsTheModelReads()
    {
        var detail = Section("errorDetail");

        foreach (var field in new[] { "resource", "reason", "code", "eins" })
        {
            Assert.True(detail.ContainsKey(field), $"The errorDetail contract omits `{field}`.");
        }
    }

    [Fact]
    public void TheOrganizationTypeContractCoversTheFieldsTheModelReads()
    {
        var entry = Section("organizationType");

        foreach (var field in new[]
                 {
                     "organization_type", "deductibility_limitation", "deductibility_status_description",
                 })
        {
            Assert.True(entry.ContainsKey(field), $"The organizationType contract omits `{field}`.");
        }
    }

    [Fact]
    public void TheContractStatesShapesAndNeverValues()
    {
        foreach (var field in Section("nonprofit"))
        {
            var shape = field.Value as JsonValue;

            Assert.True(shape is not null, $"{field.Key} declares a non-string shape.");
            Assert.False(
                string.IsNullOrWhiteSpace(shape!.GetValue<string>()),
                $"{field.Key} declares an empty shape.");
        }
    }

    private static IReadOnlyList<KeyValuePair<string, string>> Mapping(string name)
    {
        var field = typeof(Sources).GetField(name, BindingFlags.NonPublic | BindingFlags.Static);

        Assert.True(field is not null, $"Sources declares no {name} mapping.");

        return (KeyValuePair<string, string>[])field!.GetValue(null)!;
    }

    private static object BuildSource(
        Type sourceType,
        IReadOnlyList<KeyValuePair<string, string>> mapping,
        string? without)
    {
        var contract = Section("nonprofit");
        var fields = new List<KeyValuePair<string, JsonElement>>();

        foreach (var pair in mapping)
        {
            if (pair.Key == without)
            {
                continue;
            }

            var shape = contract[pair.Value]!.GetValue<string>();
            var element = JsonSerializer.Deserialize<JsonElement>(SentinelFor(shape).ToJsonString());

            fields.Add(new KeyValuePair<string, JsonElement>(pair.Key, element));
        }

        return Activator.CreateInstance(sourceType, fields)!;
    }
}
