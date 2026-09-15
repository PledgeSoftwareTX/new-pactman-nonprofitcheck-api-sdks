package pactman

import (
	"encoding/json"
	"slices"
	"testing"
)

func TestObject(t *testing.T) {
	t.Run("keeps every field, in order, exactly as sent", func(t *testing.T) {
		input := `{"b":1,"a":null,"c":{"x":[1, 2]}}`

		var object Object
		if err := json.Unmarshal([]byte(input), &object); err != nil {
			t.Fatal(err)
		}

		if !slices.Equal(object.Names(), []string{"b", "a", "c"}) || object.Len() != 3 {
			t.Errorf("names = %v", object.Names())
		}

		if !object.Has("a") || !object.IsNull("a") || object.Has("missing") || object.IsNull("missing") {
			t.Error("Has/IsNull disagree with the input")
		}

		if raw, ok := object.Get("c"); !ok || string(raw) != `{"x":[1, 2]}` {
			t.Errorf("c = %s", raw)
		}

		if data, _ := json.Marshal(object); string(data) != `{"b":1,"a":null,"c":{"x":[1,2]}}` {
			t.Errorf("marshaled = %s", data)
		}
	})

	t.Run("keeps a repeated key's first position and last value", func(t *testing.T) {
		object, err := parseObject([]byte(`{"a":1,"b":2,"a":3}`))
		if err != nil {
			t.Fatal(err)
		}

		if raw, _ := object.Get("a"); !slices.Equal(object.Names(), []string{"a", "b"}) || string(raw) != "3" {
			t.Errorf("names %v, a = %s", object.Names(), raw)
		}
	})

	t.Run("rejects values that are not one JSON object", func(t *testing.T) {
		for _, input := range []string{`[1]`, `"text"`, `{"a":1} {"b":2}`, `{"a":`} {
			var object Object
			if err := json.Unmarshal([]byte(input), &object); err == nil {
				t.Errorf("%s was accepted", input)
			}
		}
	})

	t.Run("the zero Object holds nothing and marshals as null", func(t *testing.T) {
		var object Object

		if data, _ := json.Marshal(object); string(data) != "null" || object.Has("a") || object.Len() != 0 {
			t.Errorf("zero object = %s", data)
		}
	})
}

func TestModelDecoding(t *testing.T) {
	t.Run("a decoded record marshals back exactly as it arrived", func(t *testing.T) {
		wire := wireNonprofit(setRaw("future_field", `{"deep":[true]}`))

		var nonprofit Nonprofit
		if err := json.Unmarshal(wire, &nonprofit); err != nil {
			t.Fatal(err)
		}

		if data, _ := json.Marshal(nonprofit); string(data) != string(wire) {
			t.Errorf("round trip changed the record:\n got %s\nwant %s", data, wire)
		}
	})

	t.Run("a record built in code marshals only the fields it sets", func(t *testing.T) {
		data, err := json.Marshal(Nonprofit{EIN: ptr("411787097"), BMFStatus: ptr(false)})
		if err != nil || string(data) != `{"bmf_status":false,"ein":"411787097"}` {
			t.Errorf("marshaled = %s, %v", data, err)
		}
	})

	t.Run("decoding into a used record starts from nothing", func(t *testing.T) {
		nonprofit := *decodedNonprofit(t)

		if err := json.Unmarshal([]byte(`{"ein":"996589560"}`), &nonprofit); err != nil {
			t.Fatal(err)
		}

		if nonprofit.OrganizationName != nil || str(nonprofit.EIN) != "996589560" || nonprofit.Fields.Len() != 1 {
			t.Errorf("stale fields survived: %s, %d fields", str(nonprofit.OrganizationName), nonprofit.Fields.Len())
		}
	})

	t.Run("keeps null deductibility entries and skips ones that are not objects", func(t *testing.T) {
		nonprofit := decodedNonprofit(t, setRaw("organization_types", `[null, {"deductibility_limitation":"30%"}, "stray"]`))

		types := nonprofit.OrganizationTypes
		if len(types) != 2 || types[0] != nil || str(types[1].DeductibilityLimitation) != "30%" {
			t.Errorf("organization types = %+v", types)
		}
	})

	t.Run("normalizes the envelope's errors whatever shape they arrive in", func(t *testing.T) {
		cases := map[string][]string{
			`null`:              {},
			`""`:                {},
			`"Invalid API Key"`: {"Invalid API Key"},
			`{"reason":"one"}`:  {"one"},
			`[{"reason":"a"}, "stray", {"reason":"b"}]`: {"a", "b"},
		}

		for raw, want := range cases {
			details := normalizeAPIErrors(json.RawMessage(raw))

			var reasons []string
			for _, detail := range details {
				reasons = append(reasons, detail.Reason)
			}

			if details == nil || !slices.Equal(reasons, want) && !(len(reasons) == 0 && len(want) == 0) {
				t.Errorf("errors %s read as %v, want %v", raw, reasons, want)
			}
		}
	})

	t.Run("reads only whole numbers as counts", func(t *testing.T) {
		cases := map[string]*int64{`42`: ptr[int64](42), `42.0`: ptr[int64](42), `12.5`: nil, `"42"`: nil, `true`: nil}

		for raw, want := range cases {
			var envelope Envelope
			if err := json.Unmarshal([]byte(`{"nonprofit_check_count":`+raw+`}`), &envelope); err != nil {
				t.Fatal(err)
			}

			got := envelope.NonprofitCheckCount
			if (got == nil) != (want == nil) || (got != nil && *got != *want) {
				t.Errorf("nonprofit_check_count %s read as %v", raw, got)
			}
		}
	})

	t.Run("a non-object record is an error and null is nothing", func(t *testing.T) {
		var nonprofit Nonprofit

		if err := json.Unmarshal([]byte(`"not a record"`), &nonprofit); err == nil {
			t.Error("a string decoded as a record")
		}

		if err := json.Unmarshal([]byte(`null`), &nonprofit); err != nil || nonprofit.Fields.Len() != 0 {
			t.Errorf("null: %v", err)
		}
	})
}
