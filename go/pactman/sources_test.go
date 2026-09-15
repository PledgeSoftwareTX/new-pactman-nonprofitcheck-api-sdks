package pactman

import (
	"encoding/json"
	"reflect"
	"regexp"
	"strings"
	"testing"
)

func TestSourceProjections(t *testing.T) {
	t.Run("maps Publication 78 fields from the response", func(t *testing.T) {
		pub78 := decodedNonprofit(t).Pub78()

		if pub78 == nil || pub78.Verified == nil || !*pub78.Verified {
			t.Fatalf("pub78 = %+v", pub78)
		}

		if str(pub78.EIN) != "411787097" || str(pub78.OrganizationName) != "Example Nonprofit" || str(pub78.MostRecent) != "12/12/2025 12:00:00 AM" {
			t.Errorf("pub78 = %s, %s, %s", str(pub78.EIN), str(pub78.OrganizationName), str(pub78.MostRecent))
		}

		if len(pub78.OrganizationTypes) != 1 || str(pub78.OrganizationTypes[0].DeductibilityLimitation) != "50%" {
			t.Errorf("organization types = %+v", pub78.OrganizationTypes)
		}
	})

	t.Run("maps Business Master File fields from the response", func(t *testing.T) {
		bmf := decodedNonprofit(t).BMF()

		if bmf == nil || bmf.Status == nil || !*bmf.Status {
			t.Fatalf("bmf = %+v", bmf)
		}

		if str(bmf.Subsection) != "03" || str(bmf.SubsectionDescription) != "501(c)(3) Public Charity" ||
			str(bmf.FoundationCodeDescription) != "Public charity described in section 509(a)(1) or (2)" ||
			str(bmf.MostRecent) != "12/09/2025 12:00:00 AM" || str(bmf.FilingReqCode) != "00" {
			t.Errorf("bmf = %+v", bmf)
		}
	})

	t.Run("maps Automatic Revocation fields from the response", func(t *testing.T) {
		aroe := decodedNonprofit(t,
			setRaw("revocation_code", `"01"`),
			setRaw("revocation_date", `"3/06/2026 9:41:03 PM"`),
			setRaw("reinstatement_date", `"3/07/2026 9:41:03 PM"`)).AROE()

		if aroe == nil || str(aroe.RevocationCode) != "01" || str(aroe.ReinstatementDate) != "3/07/2026 9:41:03 PM" {
			t.Fatalf("aroe = %+v", aroe)
		}
	})

	t.Run("maps OFAC verbatim, without deriving a boolean", func(t *testing.T) {
		ofac := decodedNonprofit(t).OFAC()

		if ofac == nil || !strings.Contains(str(ofac.Status), "NOT included") {
			t.Fatalf("ofac = %+v", ofac)
		}

		if fields := reflect.TypeOf(OFACSource{}).NumField(); fields != 1 {
			t.Errorf("OFACSource has %d fields; it should carry the status and nothing derived from it", fields)
		}
	})

	t.Run("keeps a missing source distinct from an explicit negative", func(t *testing.T) {
		var bare Nonprofit
		if err := json.Unmarshal([]byte(`{"ein":"411787097","organization_name":"NO SOURCES"}`), &bare); err != nil {
			t.Fatal(err)
		}

		if bare.OFAC() != nil || bare.Pub78() != nil || bare.BMF() != nil || bare.AROE() != nil {
			t.Error("a source the API did not return was reported as present")
		}

		// No OFAC field at all is "not screened"; a null status is "screened,
		// no value". The two route differently, so they must read differently.
		unscreened := decodedNonprofit(t, remove("ofac_status"))
		if unscreened.OFAC() != nil || unscreened.Fields.Has("ofac_status") {
			t.Error("an omitted ofac_status was reported as returned")
		}

		if nullStatus := decodedNonprofit(t, setNull("ofac_status")).OFAC(); nullStatus == nil || nullStatus.Status != nil {
			t.Errorf("a null ofac_status should be a present source with no status, got %+v", nullStatus)
		}

		negative := decodedNonprofit(t, setRaw("pub78_verified", "false")).Pub78()
		if negative == nil || negative.Verified == nil || *negative.Verified {
			t.Errorf("negative pub78 = %+v", negative)
		}

		allNull := decodedNonprofit(t,
			setNull("pub78_verified"), setNull("pub78_organization_name"), setNull("pub78_ein"),
			setNull("pub78_city"), setNull("pub78_state"), setNull("pub78_indicator"),
			setNull("organization_types"), setNull("most_recent_pub78")).Pub78()

		if allNull == nil || allNull.Verified != nil {
			t.Errorf("a source returned as nulls should be present with nil values, got %+v", allNull)
		}
	})

	t.Run("reports a source as present when only some of its fields were returned", func(t *testing.T) {
		var partial Nonprofit
		if err := json.Unmarshal([]byte(`{"ein":"411787097","bmf_status":false}`), &partial); err != nil {
			t.Fatal(err)
		}

		bmf := partial.BMF()
		if bmf == nil || bmf.Status == nil || *bmf.Status || bmf.Subsection != nil {
			t.Errorf("bmf = %+v", bmf)
		}
	})

	t.Run("treats a field set in code as returned", func(t *testing.T) {
		built := Nonprofit{BMFStatus: ptr(false)}

		if bmf := built.BMF(); bmf == nil || bmf.Status == nil || *bmf.Status {
			t.Errorf("bmf = %+v", bmf)
		}
	})

	t.Run("is safe on a nil record", func(t *testing.T) {
		var missing *Nonprofit

		if missing.Pub78() != nil || missing.BMF() != nil || missing.AROE() != nil || missing.OFAC() != nil {
			t.Error("a nil record reported a source")
		}
	})

	t.Run("never produces a composite verdict field", func(t *testing.T) {
		verdict := regexp.MustCompile(`(?i)approved|eligible|safe|passed|verdict|match`)

		for _, source := range []reflect.Type{
			reflect.TypeOf(Pub78Source{}), reflect.TypeOf(BMFSource{}),
			reflect.TypeOf(AROESource{}), reflect.TypeOf(OFACSource{}),
		} {
			for i := 0; i < source.NumField(); i++ {
				if name := source.Field(i).Name; verdict.MatchString(name) {
					t.Errorf("%s.%s reads as a verdict", source.Name(), name)
				}
			}
		}
	})
}
