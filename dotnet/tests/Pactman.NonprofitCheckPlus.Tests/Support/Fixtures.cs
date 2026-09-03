using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text.Json.Nodes;
using Pactman.NonprofitCheckPlus.Configuration;

namespace Pactman.NonprofitCheckPlus.Tests.Support;

/// <summary>Shared fixtures for the test suite.</summary>
public static class Fixtures
{
    /// <summary>A key that must never appear in any diagnostic output.</summary>
    public const string ApiKey = "pactman_test_key_do_not_leak_8f2b";

    public const string BaseUrl = "http://mock.test";

    /// <summary>A client wired to <paramref name="handler"/>, using the documented setup.</summary>
    public static PactmanClient Client(
        FakeHandler handler,
        Clock? clock = null,
        TimeSpan? timeout = null,
        RetryOptions? retry = null,
        double? maxRequestsPerSecond = null,
        IReadOnlyDictionary<string, string>? defaultHeaders = null)
    {
        var options = new PactmanClientOptions
        {
            ApiKey = ApiKey,
            BaseUrl = BaseUrl,
            Timeout = timeout,
            Retry = retry,
            MaxRequestsPerSecond = maxRequestsPerSecond,
            HttpClient = new HttpClient(handler) { Timeout = System.Threading.Timeout.InfiniteTimeSpan },
            DisposeHttpClient = true,
        };

        if (defaultHeaders is not null)
        {
            foreach (var header in defaultHeaders)
            {
                options.DefaultHeaders[header.Key] = header.Value;
            }
        }

        return new PactmanClient(options, clock?.Hooks());
    }

    /// <summary>A representative organization, mirroring the published response example.</summary>
    public static JsonObject Nonprofit(Action<JsonObject>? customize = null)
    {
        var organization = new JsonObject
        {
            ["pactman_org_url"] = "https://pactman.org/profile/nonprofit/example-nonprofit-r5U9r8yRcZ",
            ["organization_info_last_modified"] = "2/22/2026 1:16:30 AM",
            ["ein"] = "411787097",
            ["organization_name"] = "EXAMPLE NONPROFIT",
            ["organization_name_aka"] = "EXAMPLE N.P",
            ["address_line1"] = "50 LOWELL AVE",
            ["address_line2"] = "APT 3B",
            ["city"] = "WESTFIELD",
            ["state"] = "MA",
            ["state_name"] = "Massachusetts",
            ["zip"] = "01085-2643",
            ["filing_req_code"] = "00",
            ["pub78_church_message"] = null,
            ["pub78_organization_name"] = "Example Nonprofit",
            ["pub78_ein"] = "411787097",
            ["pub78_verified"] = true,
            ["pub78_city"] = "Westfield",
            ["pub78_state"] = "MA",
            ["pub78_indicator"] = "0",
            ["organization_types"] = new JsonArray
            {
                new JsonObject
                {
                    ["organization_type"] = "Deductions for donations to public charities are generally limited...",
                    ["deductibility_limitation"] = "50%",
                    ["deductibility_status_description"] = "PC",
                },
            },
            ["most_recent_pub78"] = "12/12/2025 12:00:00 AM",
            ["bmf_church_message"] = null,
            ["bmf_organization_name"] = "EXAMPLE NONPROFIT",
            ["bmf_ein"] = "411787097",
            ["bmf_status"] = true,
            ["most_recent_bmf"] = "12/09/2025 12:00:00 AM",
            ["bmf_subsection"] = "03",
            ["subsection_description"] = "501(c)(3) Public Charity",
            ["foundation_code"] = "10",
            ["foundation_code_description"] = "Public charity described in section 509(a)(1) or (2)",
            ["ruling_month"] = "07",
            ["ruling_year"] = "2024",
            ["group_exemption"] = "0000",
            ["exempt_status_code"] = "01",
            ["ofac_status"] = "This organization was NOT included in the Office of Foreign Assets "
                + "Control Specially Designated Nationals (SDN) list.",
            ["revocation_code"] = null,
            ["revocation_date"] = null,
            ["reinstatement_date"] = null,
            ["irs_bmf_pub78_conflict"] = false,
            ["foundation_509a_status"] = "N/A",
            ["report_date"] = "3/25/2026 3:28:54 PM",
            ["foundation_type_code"] = "pc",
            ["foundation_type_description"] = "Public charity described in section 509(a)(1) or (2)",
        };

        customize?.Invoke(organization);

        return organization;
    }

    /// <summary>Wraps data in the envelope the API returns.</summary>
    public static JsonObject Envelope(JsonNode? data, Action<JsonObject>? customize = null)
    {
        var envelope = new JsonObject
        {
            ["code"] = 200,
            ["message"] = "OK",
            ["errors"] = null,
            ["data"] = data,
            ["timeTaken"] = 3,
            ["nonprofit_check_count"] = 1,
        };

        customize?.Invoke(envelope);

        return envelope;
    }

    /// <summary>An organization list, as the bulk endpoint returns it.</summary>
    public static JsonArray Organizations(params JsonNode[] organizations)
    {
        var list = new JsonArray();

        foreach (var organization in organizations)
        {
            list.Add(organization);
        }

        return list;
    }
}
