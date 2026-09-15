// Package mockapi is a stand-in for the Nonprofit Check Plus API, so the
// examples run in CI without a real key or network access.
//
// Scenarios like a revoked exemption, an OFAC match, a cross-source conflict
// or a field newer than the SDK cannot be summoned on demand from production.
// They are declared here once, so an example can demonstrate the handling and
// the server can serve the record. Field names and values mirror the shapes the
// Pactman API reference documents; the EINs are illustrative, not real
// organizations.
//
// This is a port of the Node SDK's scripts/fixtures.mjs and
// scripts/mock-server.mjs, which remain the source of truth.
package mockapi

import (
	"bytes"
	"encoding/json"
	"regexp"
	"strings"
	"time"
)

// The two OFAC sentences the API returns. It reports prose, not a boolean.
const (
	OFACNoMatch = "This organization was NOT included in the Office of Foreign Assets Control " +
		"Specially Designated Nationals (SDN) list."
	OFACPossibleMatch = "This organization may be included in the Office of Foreign Assets Control " +
		"Specially Designated Nationals(SDN) list. " +
		"A close match was found with the Special Designated National with UID: 41234"
)

// EINs the fixture records are filed under, so no example hard-codes a bare number.
const (
	// PublicCharity is a 501(c)(3) public charity with every source returned and nothing adverse.
	PublicCharity = "411787097"
	// PublicCharitySecond is a second clean organization, for bulk examples.
	PublicCharitySecond = "996589560"
	// PrivateFoundation is a 501(c)(3) private foundation — different foundation and filing codes.
	PrivateFoundation = "042103594"
	// SparseIdentity has most optional identity fields returned as null, and no OFAC field at all.
	SparseIdentity = "060646700"
	// InconsistentAddress has address fields that are present but disagree with each other.
	InconsistentAddress = "311580204"
	// StaleData has every source date well in the past.
	StaleData = "362167048"
	// Revoked is listed in the IRS Automatic Revocation of Exemption data, not reinstated.
	Revoked = "237112796"
	// Reinstated was revoked and later reinstated — both dates present.
	Reinstated = "133039601"
	// OFACMatch is a possible OFAC SDN match.
	OFACMatch = "954367818"
	// OFACUnavailable has OFAC screening returned as null.
	OFACUnavailable = "061553389"
	// Conflicted has BMF and Publication 78 disagreeing; irs_bmf_pub78_conflict is true.
	Conflicted = "521693387"
	// FutureFields carries fields and an enum value this SDK version does not know about.
	FutureFields = "237324370"
	// PendingSourceFields is production's shape plus the source fields only newer deployments return.
	PendingSourceFields = "046001341"
	// NoRecord is well-formed, but no record exists.
	NoRecord = "999999999"
)

// EINs the server answers with a specific failure, for the error examples.
const (
	// RateLimited always answers HTTP 429 with Retry-After: 1.
	RateLimited = "900000429"
	// TransientFailure answers HTTP 503 twice per server, then succeeds.
	TransientFailure = "900000503"
	// Slow holds the response open, so a short timeout expires.
	Slow = "900000408"
)

// APIDate formats a date the way the API does — M/DD/YYYY h:mm:ss AM — daysAgo
// before now. Fixture dates are relative to today so the freshness examples
// stay meaningful however long after they were written they run.
func APIDate(now time.Time, daysAgo int) string {
	return now.Add(-time.Duration(daysAgo) * 24 * time.Hour).Format("1/02/2006 3:04:05 PM")
}

// Record is one JSON object, with its fields in the order the API sends them.
type Record struct {
	names  []string
	values map[string]json.RawMessage
}

type field struct {
	name  string
	value json.RawMessage
}

func object(fields ...field) Record {
	record := Record{values: map[string]json.RawMessage{}}

	for _, f := range fields {
		record.set(f.name, f.value)
	}

	return record
}

func (r *Record) set(name string, value json.RawMessage) {
	if _, ok := r.values[name]; !ok {
		r.names = append(r.names, name)
	}

	r.values[name] = value
}

// without removes fields outright, so a record can say "the API returned no
// field at all" as distinct from "the API returned null".
func (r Record) without(names ...string) Record {
	out := object()

	for _, name := range r.names {
		skip := false

		for _, removed := range names {
			skip = skip || name == removed
		}

		if !skip {
			out.set(name, r.values[name])
		}
	}

	return out
}

func (r Record) with(overrides ...field) Record {
	out := r.without()

	for _, f := range overrides {
		out.set(f.name, f.value)
	}

	return out
}

// Has reports whether the record carries the field, null included.
func (r Record) Has(name string) bool {
	_, ok := r.values[name]

	return ok
}

// MarshalJSON writes the fields in order.
func (r Record) MarshalJSON() ([]byte, error) {
	var buf bytes.Buffer

	buf.WriteByte('{')

	for i, name := range r.names {
		if i > 0 {
			buf.WriteByte(',')
		}

		key, _ := json.Marshal(name)
		buf.Write(key)
		buf.WriteByte(':')
		buf.Write(r.values[name])
	}

	buf.WriteByte('}')

	return buf.Bytes(), nil
}

var null = json.RawMessage("null")

func text(value string) json.RawMessage {
	data, _ := json.Marshal(value)

	return data
}

func flag(value bool) json.RawMessage {
	if value {
		return json.RawMessage("true")
	}

	return json.RawMessage("false")
}

func list(values ...json.RawMessage) json.RawMessage {
	data, _ := json.Marshal(values)

	return data
}

func raw(value Record) json.RawMessage {
	data, _ := value.MarshalJSON()

	return data
}

func f(name string, value json.RawMessage) field { return field{name, value} }

func deductibilityPublicCharity() Record {
	return object(
		f("organization_type", text("Deductions for donations to public charities are generally limited to 50 percent "+
			"of adjusted gross income (AGI). This limit increases to 60% of AGI for cash donations. "+
			"For Non-Cash assets held for more than one year, the limit is 30% of AGI.")),
		f("deductibility_limitation", text("50%")),
		f("deductibility_status_description", text("PC")),
	)
}

func deductibilityPrivateFoundation() Record {
	return object(
		f("organization_type", text("Deductions for donations to private foundations are generally limited to 30 percent "+
			"of adjusted gross income (AGI). For Non-Cash assets held for more than one year, the limit is 20% of AGI.")),
		f("deductibility_limitation", text("30%")),
		f("deductibility_status_description", text("PF")),
	)
}

var nonSlug = regexp.MustCompile(`[^a-z0-9]+`)

func slug(name string) string {
	return strings.Trim(nonSlug.ReplaceAllString(strings.ToLower(name), "-"), "-")
}

// publicCharity is a complete, unremarkable public charity. Scenarios override
// from here.
func publicCharity(now time.Time, ein, name string) Record {
	return object(
		f("pactman_org_url", text("https://pactman.org/profile/nonprofit/"+slug(name)+"-"+ein[len(ein)-4:])),
		f("organization_info_last_modified", text(APIDate(now, 40))),

		f("ein", text(ein)),
		f("organization_name", text(strings.ToUpper(name))),
		f("organization_name_aka", null),
		f("address_line1", text("50 LOWELL AVE")),
		f("address_line2", text("APT 3B")),
		f("city", text("WESTFIELD")),
		f("state", text("MA")),
		f("state_name", text("Massachusetts")),
		f("zip", text("01085-2643")),
		f("filing_req_code", text("01")),

		f("pub78_church_message", null),
		f("pub78_organization_name", text(name)),
		f("pub78_ein", text(ein)),
		f("pub78_verified", flag(true)),
		f("pub78_city", text("Westfield")),
		f("pub78_state", text("MA")),
		f("pub78_indicator", text("0")),
		f("organization_types", list(raw(deductibilityPublicCharity()))),
		f("most_recent_pub78", text(APIDate(now, 26))),

		f("bmf_church_message", null),
		f("bmf_organization_name", text(strings.ToUpper(name))),
		f("bmf_ein", text(ein)),
		f("bmf_status", flag(true)),
		f("bmf_subsection", text("03")),
		f("most_recent_bmf", text(APIDate(now, 20))),
		f("subsection_description", text("501(c)(3) Public Charity")),
		f("foundation_code", text("10")),
		f("foundation_code_description", text("Public charity described in section 509(a)(1) or (2)")),
		f("foundation_type_code", text("pc")),
		f("foundation_type_description", text("Public charity described in section 509(a)(1) or (2)")),
		f("foundation_509a_status", text("N/A")),
		f("ruling_month", text("07")),
		f("ruling_year", text("2024")),
		f("group_exemption", text("0000")),
		f("exempt_status_code", text("01")),

		f("ofac_status", text(OFACNoMatch)),

		f("revocation_code", null),
		f("revocation_date", null),
		f("reinstatement_date", null),

		f("irs_bmf_pub78_conflict", flag(false)),
		f("report_date", text(APIDate(now, 0))),
	)
}

// Organizations is every record the server can return, keyed by EIN, with
// dates relative to now.
func Organizations(now time.Time) map[string]Record {
	charity := func(ein, name string, overrides ...field) Record {
		return publicCharity(now, ein, name).with(overrides...)
	}

	return map[string]Record{
		PublicCharity: charity(PublicCharity, "Meals Today Example Nonprofit",
			f("organization_name_aka", text("MEALS TODAY E.N")),
			f("pub78_organization_name", text("Meals Today Example Nonprofit, Inc.")),
		),

		PublicCharitySecond: charity(PublicCharitySecond, "Aborjaily Example Nonprofit",
			f("organization_name_aka", text("ABORJAILY E.N")),
			f("city", text("SPRINGFIELD")),
			f("pub78_city", text("Springfield")),
			f("zip", text("01103-1420")),
			f("address_line1", text("19 HAMPDEN ST")),
			f("address_line2", null),
		),

		// A private foundation files a 990-PF, so it carries no general 990
		// filing requirement.
		PrivateFoundation: charity(PrivateFoundation, "Hartwell Family Example Foundation",
			f("organization_name_aka", null),
			f("filing_req_code", text("00")),
			f("organization_types", list(raw(deductibilityPrivateFoundation()))),
			f("subsection_description", text("501(c)(3) Private Foundation")),
			f("foundation_code", text("04")),
			f("foundation_code_description", text("Private non-operating foundation")),
			f("foundation_type_code", text("pf")),
			f("foundation_type_description", text("Private non-operating foundation")),
			f("foundation_509a_status", text("N/A")),
			f("ruling_month", text("11")),
			f("ruling_year", text("1998")),
		),

		// Optional identity fields the API had no value for, and no OFAC key at
		// all: the source was not reported, which is not a null status or a
		// no-match result.
		SparseIdentity: charity(SparseIdentity, "Quiet Harbor Example Trust",
			f("organization_name_aka", null),
			f("address_line1", text("PO BOX 118")),
			f("address_line2", null),
			f("city", text("ROCKPORT")),
			f("state", text("ME")),
			f("state_name", null),
			f("zip", null),
			f("pub78_city", null),
			f("pub78_state", null),
			f("group_exemption", null),
			f("ruling_month", null),
			f("ruling_year", null),
		).without("ofac_status"),

		// Every address component is present, and they contradict one another:
		// the state code says Massachusetts, the state name and the ZIP say
		// Maine, and address_line2 holds a placeholder.
		InconsistentAddress: charity(InconsistentAddress, "Harbor Light Example Alliance",
			f("organization_name_aka", null),
			f("address_line1", text("12 SEA STREET")),
			f("address_line2", text("N/A")),
			f("city", text("ROCKPORT")),
			f("state", text("MA")),
			f("state_name", text("Maine")),
			f("zip", text("04856")),
			f("pub78_city", text("Rockport")),
			f("pub78_state", text("MA")),
		),

		// Nothing adverse, but every source is well out of date.
		StaleData: charity(StaleData, "Long Quiet Example Foundation",
			f("organization_info_last_modified", text(APIDate(now, 700))),
			f("most_recent_pub78", text(APIDate(now, 640))),
			f("most_recent_bmf", text(APIDate(now, 610))),
		),

		Revoked: charity(Revoked, "Lapsed Filings Example Society",
			f("organization_name_aka", null),
			f("pub78_verified", flag(false)),
			f("pub78_indicator", null),
			f("organization_types", null),
			f("bmf_status", flag(false)),
			f("subsection_description", text("501(c)(3) Public Charity")),
			f("exempt_status_code", text("25")),
			f("revocation_code", text("01")),
			f("revocation_date", text(APIDate(now, 1260))),
			f("reinstatement_date", null),
		),

		Reinstated: charity(Reinstated, "Second Chance Example Alliance",
			f("organization_name_aka", text("SECOND CHANCE E.A")),
			f("revocation_code", text("01")),
			f("revocation_date", text(APIDate(now, 1260))),
			f("reinstatement_date", text(APIDate(now, 520))),
		),

		OFACMatch: charity(OFACMatch, "Overseas Relief Example Fund",
			f("organization_name_aka", text("OVERSEAS RELIEF E.F")),
			f("ofac_status", text(OFACPossibleMatch)),
		),

		// The API returned nothing for OFAC. Absent is not the same as "no match".
		OFACUnavailable: charity(OFACUnavailable, "Riverbend Example Coalition",
			f("ofac_status", null),
		),

		// BMF says exempt, Publication 78 does not list the organization, and
		// the API flags the disagreement rather than picking a winner.
		Conflicted: charity(Conflicted, "Crosscheck Example Institute",
			f("organization_name", text("CROSSCHECK EXAMPLE INSTITUTE")),
			f("pub78_organization_name", null),
			f("pub78_ein", null),
			f("pub78_verified", flag(false)),
			f("pub78_city", null),
			f("pub78_state", null),
			f("pub78_indicator", null),
			f("organization_types", null),
			f("most_recent_pub78", text(APIDate(now, 26))),
			f("bmf_organization_name", text("CROSSCHECK EXAMPLE INST")),
			f("bmf_status", flag(true)),
			f("irs_bmf_pub78_conflict", flag(true)),
		),

		// A response from a newer API version: fields this SDK has never heard
		// of, and an enum value outside the documented set.
		FutureFields: charity(FutureFields, "Forward Compatible Example Trust",
			f("foundation_type_code", text("zz")),
			f("foundation_type_description", text("A classification added after this SDK was published")),
			f("organization_types", list(raw(deductibilityPublicCharity().with(
				f("deductibility_status_description", text("XX")),
				f("future_deductibility_note", text("An unknown member of a known object")),
			)))),
			f("state_charity_registration_status", text("ACTIVE")),
			f("watchlist_screening", raw(object(
				f("provider", text("example")),
				f("matches", json.RawMessage("0")),
				f("list_published_date", text(APIDate(now, 5))),
			))),
		),

		// A deployment running ahead of production: the ten source fields that
		// are built but not yet released there. The SDK does not declare them,
		// so they exercise the path that keeps undeclared fields readable.
		PendingSourceFields: charity(PendingSourceFields, "Ahead Of Production Example Fund",
			f("organization_name_aka", null),
			f("pub78_source_org_type_1", text("PC")),
			f("pub78_source_org_type_2", null),
			f("pub78_source_org_type_3", null),
			f("bmf_city", text("WESTFIELD")),
			f("bmf_state", text("MA")),
			f("bmf_street_address", text("50 LOWELL AVE APT 3B")),
			f("bmf_source_pf_filing_req_cd", text("0")),
			f("bmf_deductability_text", text("Contributions are deductible")),
			f("ofac_list_published_date", text(APIDate(now, 5))),
			f("aroe_list_published_date", text(APIDate(now, 12))),
		),
	}
}
