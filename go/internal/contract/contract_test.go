package contract

import (
	"bytes"
	"encoding/json"
	"os"
	"reflect"
	"slices"
	"sort"
	"strings"
	"testing"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

// The smallest expectation that still has a nested object and an array in it.
var expected = Signature{
	"code":                      "number",
	"data":                      "null|object",
	"data.ein":                  "digits:9",
	"data.organization_types":   "array|null",
	"data.organization_types[]": "object",
	"data.organization_types[].organization_type": "null|string",
	"errors":          "array|null|string",
	"errors[]":        "object",
	"errors[].reason": "string",
}

// A successful response: no errors, and this organization has no types.
var success = Signature{
	"code":                    "number",
	"data":                    "object",
	"data.ein":                "digits:9",
	"data.organization_types": "null",
	"errors":                  "null",
}

func with(base Signature, changes map[string]string) Signature {
	out := Signature{}

	for path, token := range base {
		out[path] = token
	}

	for path, token := range changes {
		if token == "" {
			delete(out, path)
		} else {
			out[path] = token
		}
	}

	return out
}

func assertChanges(t *testing.T, got Diff, want ...Change) {
	t.Helper()

	if want == nil {
		want = []Change{}
	}

	if !reflect.DeepEqual(got.Changes, want) || got.Total != len(want) {
		t.Errorf("changes = %+v, want %+v", got.Changes, want)
	}
}

func TestCoverageDiff(t *testing.T) {
	t.Run("passes a response whose absent paths all sit under a null parent", func(t *testing.T) {
		result := CoverageDiff(expected, success, nil)

		assertChanges(t, result)

		// errors[], errors[].reason, organization_types[] and its one field.
		if result.Unreachable != 4 {
			t.Errorf("unreachable = %d", result.Unreachable)
		}
	})

	t.Run("fails a field that went missing while its parent was there", func(t *testing.T) {
		assertChanges(t, CoverageDiff(expected, with(success, map[string]string{"data.ein": ""}), nil),
			Change{Kind: "removed", Path: "data.ein", Token: "digits:9"})
	})

	t.Run("fails a field the API invented", func(t *testing.T) {
		assertChanges(t, CoverageDiff(expected, with(success, map[string]string{"data.new_field": "text"}), nil),
			Change{Kind: "added", Path: "data.new_field", Token: "text"})
	})

	t.Run("reports a container that vanished once, not once per field under it", func(t *testing.T) {
		assertChanges(t, CoverageDiff(expected, Signature{"code": "number", "errors": "null"}, nil),
			Change{Kind: "removed", Path: "data", Token: "null|object"})
	})

	t.Run("treats an array that arrived empty as having no room for its elements", func(t *testing.T) {
		assertChanges(t, CoverageDiff(expected, with(success, map[string]string{"data.organization_types": "array"}), nil))
	})

	t.Run("fails a field missing from the elements an array did return", func(t *testing.T) {
		observed := with(success, map[string]string{"data.organization_types": "array", "data.organization_types[]": "object"})

		assertChanges(t, CoverageDiff(expected, observed, nil),
			Change{Kind: "removed", Path: "data.organization_types[].organization_type", Token: "null|string"})
	})

	t.Run("counts an absent optional field instead of failing it", func(t *testing.T) {
		result := CoverageDiff(expected, with(success, map[string]string{"data.ein": ""}), map[string]bool{"data": true})

		assertChanges(t, result)

		if result.OptionalAbsent != 1 {
			t.Errorf("optional absent = %d", result.OptionalAbsent)
		}
	})
}

func TestRecordedBaseline(t *testing.T) {
	recorded := Signature{"code": "number", "data.ein": "digits:9", "data.city": "text"}

	t.Run("reports a path that appeared and a path that disappeared", func(t *testing.T) {
		now := Signature{"code": "number", "data.ein": "digits:9", "data.county": "text"}

		assertChanges(t, SchemaDiff(recorded, now),
			Change{Kind: "removed", Path: "data.city", Token: "text"},
			Change{Kind: "added", Path: "data.county", Token: "text"})
	})

	t.Run("reports a value whose form moved, on a path both have", func(t *testing.T) {
		assertChanges(t, TypeDiff(recorded, with(recorded, map[string]string{"data.ein": "digits:2-7"})),
			Change{Kind: "changed", Path: "data.ein", From: "digits:9", To: "digits:2-7"})
	})

	t.Run("sees no difference in an identical signature", func(t *testing.T) {
		if SchemaDiff(recorded, with(recorded, nil)).Total != 0 || TypeDiff(recorded, with(recorded, nil)).Total != 0 {
			t.Error("an identical signature differed")
		}
	})
}

func TestBaselineDiff(t *testing.T) {
	// One organization, recorded on an afternoon its Pub 78 row was populated.
	recorded := Signature{
		"code":                      "number",
		"data.ein":                  "digits:9",
		"data.pub78_city":           "text",
		"data.organization_types":   "array",
		"data.organization_types[]": "object",
		"data.organization_types[].organization_type": "text",
		"errors": "null",
	}

	t.Run("passes a subject whose nullable fields came back empty this time", func(t *testing.T) {
		now := Signature{
			"code":                    "number",
			"data.ein":                "digits:9",
			"data.pub78_city":         "null",
			"data.organization_types": "null",
			"errors":                  "null",
		}

		result := BaselineDiff(recorded, now)

		assertChanges(t, result)

		if result.Nullable != 2 || result.Unreachable != 2 {
			t.Errorf("nullable %d, unreachable %d", result.Nullable, result.Unreachable)
		}
	})

	t.Run("passes a field that filled in since the recording", func(t *testing.T) {
		result := BaselineDiff(Signature{"data.pub78_city": "null"}, Signature{"data.pub78_city": "text"})

		assertChanges(t, result)

		if result.Nullable != 1 {
			t.Errorf("nullable = %d", result.Nullable)
		}
	})

	t.Run("passes a token that only gained or lost null", func(t *testing.T) {
		result := BaselineDiff(Signature{"data[].address_line2": "digits:4|null"}, Signature{"data[].address_line2": "digits:4"})

		assertChanges(t, result)
	})

	t.Run("passes the paths under a parent that was null when it was recorded", func(t *testing.T) {
		result := BaselineDiff(Signature{"errors": "null"},
			Signature{"errors": "array", "errors[]": "object", "errors[].code": "number"})

		assertChanges(t, result)

		if result.Unreachable != 2 {
			t.Errorf("unreachable = %d", result.Unreachable)
		}
	})

	t.Run("still fails a value whose form moved between two real forms", func(t *testing.T) {
		result := BaselineDiff(Signature{"data.ein": "digits:9"}, Signature{"data.ein": "text"})

		assertChanges(t, result, Change{Kind: "changed", Path: "data.ein", From: "digits:9", To: "text"})
	})

	t.Run("still fails a form that moved while the field also turned nullable", func(t *testing.T) {
		assertChanges(t, BaselineDiff(Signature{"data.ein": "digits:9"}, Signature{"data.ein": "null|text"}),
			Change{Kind: "changed", Path: "data.ein", From: "digits:9", To: "null|text"})
	})

	t.Run("still fails a field that vanished while its parent was there", func(t *testing.T) {
		assertChanges(t, BaselineDiff(recorded, with(recorded, map[string]string{"data.ein": ""})),
			Change{Kind: "removed", Path: "data.ein", Token: "digits:9"})
	})

	t.Run("still fails a field the API invented", func(t *testing.T) {
		assertChanges(t, BaselineDiff(recorded, with(recorded, map[string]string{"data.county": "text"})),
			Change{Kind: "added", Path: "data.county", Token: "text"})
	})
}

func TestComposeExpected(t *testing.T) {
	contract := Contract{
		Envelope:         map[string]string{"code": "number", "errors": "array|null|string"},
		ErrorDetail:      map[string]string{"reason": "string"},
		Nonprofit:        map[string]string{"ein": "digits:9|null"},
		OrganizationType: map[string]string{"organization_type": "null|string"},
	}

	single, bulk := ComposeExpected(contract, "single"), ComposeExpected(contract, "bulk")

	if single["data.ein"] != "digits:9|null" || bulk["data[].ein"] != "digits:9|null" {
		t.Errorf("record paths: %q, %q", single["data.ein"], bulk["data[].ein"])
	}

	if single["data"] != "null|object" || bulk["data"] != "array|null" {
		t.Errorf("data: %q, %q", single["data"], bulk["data"])
	}

	if single["data.organization_types[]"] != "null|object" || bulk["data[].organization_types[]"] != "null|object" {
		t.Error("an element of organization_types should be allowed to be null")
	}
}

func TestSignatureOf(t *testing.T) {
	body := []byte(`{
		"code": 200, "errors": null,
		"data": [
			{"ein": "411787097", "zip": "01085-2643", "most_recent_bmf": "12/09/2025 12:00:00 AM",
			 "organization_types": [{"deductibility_limitation": "50%"}]},
			{"ein": "996589560", "zip": null, "most_recent_bmf": "12/09/2025 12:00:00 AM",
			 "organization_types": []}
		]
	}`)

	signature, err := SignatureOf(body)
	if err != nil {
		t.Fatal(err)
	}

	want := Signature{
		"code":                        "number",
		"errors":                      "null",
		"data":                        "array",
		"data[]":                      "object",
		"data[].ein":                  "digits:9",
		"data[].zip":                  "digits:5-4|null",
		"data[].most_recent_bmf":      "date",
		"data[].organization_types":   "array",
		"data[].organization_types[]": "object",
		"data[].organization_types[].deductibility_limitation": "text",
	}

	if !reflect.DeepEqual(signature, want) {
		t.Errorf("signature = %v", signature)
	}
}

func TestFormatOf(t *testing.T) {
	cases := map[string]string{
		"411787097":              "digits:9",
		"01085-2643":             "digits:5-4",
		"00":                     "digits:2",
		"12/09/2025 12:00:00 AM": "date",
		"3/7/2026, 9:41:03 PM":   "date",
		"2025-12-09T00:00:00Z":   "date:iso",
		"https://pactman.org/x":  "url",
		"":                       "empty",
		"   ":                    "empty",
		"EXAMPLE NONPROFIT":      "text",
		"This organization was NOT included in the Office of Foreign Assets Control Specially Designated Nationals (SDN) list.":                                       "ofac-sentence",
		"This organization may be included in the Office of Foreign Assets Control Specially Designated Nationals(SDN) list. A close match was found with UID: 41234": "ofac-sentence",
	}

	for value, want := range cases {
		if got := FormatOf(value); got != want {
			t.Errorf("FormatOf(%q) = %s, want %s", value, got, want)
		}
	}
}

// --- the contract against the Node SDK and against the Go models ----------

func TestContractIsTheNodeSDKsCopy(t *testing.T) {
	node, err := os.ReadFile("../../../nodejs/src/response-contract.json")
	if err != nil {
		t.Skipf("the Node SDK is not checked out beside this one: %v", err)
	}

	if !bytes.Equal(node, contractJSON) {
		t.Fatal("internal/contract/response-contract.json has drifted from nodejs/src/response-contract.json; " +
			"copy the Node file over it — the Node SDK is the source of truth for the contract")
	}
}

// shapes pairs each contract section with the model that reads it.
var shapes = []struct {
	section string
	model   reflect.Type
}{
	{"nonprofit", reflect.TypeOf(pactman.Nonprofit{})},
	{"envelope", reflect.TypeOf(pactman.Envelope{})},
	{"errorDetail", reflect.TypeOf(pactman.APIErrorDetail{})},
	{"organizationType", reflect.TypeOf(pactman.OrganizationType{})},
}

func section(t *testing.T, name string) map[string]string {
	t.Helper()

	contract, err := Load()
	if err != nil {
		t.Fatal(err)
	}

	return map[string]map[string]string{
		"nonprofit":        contract.Nonprofit,
		"envelope":         contract.Envelope,
		"errorDetail":      contract.ErrorDetail,
		"organizationType": contract.OrganizationType,
	}[name]
}

// tagged maps each json tag on a model to its field index.
func tagged(model reflect.Type) map[string]int {
	fields := map[string]int{}

	for i := 0; i < model.NumField(); i++ {
		name, _, _ := strings.Cut(model.Field(i).Tag.Get("json"), ",")
		if name != "" && name != "-" {
			fields[name] = i
		}
	}

	return fields
}

func keys[V any](m map[string]V) []string {
	out := make([]string, 0, len(m))
	for key := range m {
		out = append(out, key)
	}

	sort.Strings(out)

	return out
}

func TestModelsDeclareExactlyTheContractFields(t *testing.T) {
	for _, shape := range shapes {
		if got, want := keys(tagged(shape.model)), keys(section(t, shape.section)); !slices.Equal(got, want) {
			t.Errorf("%s declares %v\ncontract %s predicts %v", shape.model.Name(), got, shape.section, want)
		}
	}
}

// sentinelFor is a JSON value of the kind a token predicts. A shape, never a
// realistic value: a test fed real EINs would pass for the wrong reason the
// day a decoder began parsing them. The list holds an object and a string so
// it satisfies both the record list and the EIN list.
func sentinelFor(token string) string {
	switch token {
	case "null":
		return "null"
	case "boolean":
		return "true"
	case "number":
		return "1"
	case "array":
		return `[{"organization_type":"sentinel"},"sentinel"]`
	case "object":
		return `{"field":"sentinel"}`
	case "empty":
		return `""`
	}

	return `"sentinel"`
}

func TestEveryPredictedShapeIsReadable(t *testing.T) {
	for _, shape := range shapes {
		fields := tagged(shape.model)

		for field, tokens := range section(t, shape.section) {
			for _, token := range strings.Split(tokens, "|") {
				body := []byte(`{"` + field + `":` + sentinelFor(token) + `}`)
				decoded := reflect.New(shape.model)

				if err := json.Unmarshal(body, decoded.Interface()); err != nil {
					t.Fatalf("%s: %v", body, err)
				}

				value := decoded.Elem().Field(fields[field])
				wire := decoded.Elem().FieldByName("Fields").Interface().(pactman.Object)

				if token == "null" {
					if !wire.Has(field) || !value.IsZero() {
						t.Errorf("%s.%s returned as null should be present in Fields and nil on the model", shape.section, field)
					}

					continue
				}

				if value.IsZero() || (value.Kind() == reflect.Slice && value.Len() == 0) {
					t.Errorf("%s.%s predicts a %s value, but %s.%s reads nothing from one",
						shape.section, field, token, shape.model.Name(), shape.model.Field(fields[field]).Name)
				}
			}
		}
	}
}

func TestContractVocabulary(t *testing.T) {
	known := map[string]bool{"null": true, "boolean": true, "number": true, "array": true, "object": true, "string": true}

	contract, err := Load()
	if err != nil {
		t.Fatal(err)
	}

	for _, shape := range shapes {
		for field, tokens := range section(t, shape.section) {
			for _, token := range strings.Split(tokens, "|") {
				if !known[token] && !IsStringToken(token) {
					t.Errorf("%s.%s uses unknown token %q", shape.section, field, token)
				}
			}

			if strings.Contains(tokens, "411787097") || strings.Contains(tokens, "EXAMPLE") {
				t.Errorf("%s.%s looks like a value, not a shape", shape.section, field)
			}
		}

		// Every model field is optional, so this package makes no presence
		// promise at all; an entry here would be one the types cannot keep.
		required, ok := contract.Required[shape.section]
		if !ok || len(required) != 0 {
			t.Errorf("required.%s = %v, want an empty list", shape.section, required)
		}
	}
}

func TestEmbeddedBaselineReads(t *testing.T) {
	baseline, err := LoadBaseline()
	if err != nil || baseline.Single == nil || baseline.Bulk == nil || len(baseline.Single.Signature) == 0 {
		t.Fatalf("baseline = %+v, %v", baseline, err)
	}
}
