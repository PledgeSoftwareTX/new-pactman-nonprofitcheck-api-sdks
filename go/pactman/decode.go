package pactman

import (
	"bytes"
	"encoding/json"
	"math"
	"reflect"
	"strings"
)

var (
	stringType      = reflect.TypeOf("")
	stringPtrType   = reflect.TypeOf((*string)(nil))
	boolPtrType     = reflect.TypeOf((*bool)(nil))
	intPtrType      = reflect.TypeOf((*int)(nil))
	int64PtrType    = reflect.TypeOf((*int64)(nil))
	float64PtrType  = reflect.TypeOf((*float64)(nil))
	stringSliceType = reflect.TypeOf([]string(nil))
	orgTypesType    = reflect.TypeOf([]*OrganizationType(nil))
	apiErrorsType   = reflect.TypeOf([]APIErrorDetail(nil))
)

// decodeDeclared fills a model's json-tagged fields from the wire fields.
//
// Decoding is lenient field by field. A value of the wrong JSON type leaves its
// field nil instead of failing the record, so one field the API changes cannot
// cost a caller the other forty — and the value stays readable through Fields.
// The one exception is a string field, which keeps a non-string value as its
// JSON text: a field that turns from "01" into 1 is still visible, not gone.
//
// The struct tags are the single mapping between wire names and Go fields.
func decodeDeclared(model any, fields Object) {
	value := reflect.ValueOf(model).Elem()
	typ := value.Type()

	for i := 0; i < typ.NumField(); i++ {
		name := jsonName(typ.Field(i))
		if name == "" {
			continue
		}

		raw, ok := fields.values[name]
		if !ok || isJSONNull(raw) {
			continue
		}

		if decoded, ok := decodeValue(typ.Field(i).Type, raw); ok {
			value.Field(i).Set(decoded)
		}
	}
}

// jsonName is the wire name a struct field is tagged with, or "" for none.
func jsonName(field reflect.StructField) string {
	name, _, _ := strings.Cut(field.Tag.Get("json"), ",")
	if name == "-" {
		return ""
	}

	return name
}

func decodeValue(typ reflect.Type, raw json.RawMessage) (reflect.Value, bool) {
	switch typ {
	case stringPtrType:
		text := stringOrJSONText(raw)

		return reflect.ValueOf(&text), true
	case stringType:
		return reflect.ValueOf(stringOrJSONText(raw)), true
	case boolPtrType:
		var flag bool
		if json.Unmarshal(raw, &flag) != nil {
			return reflect.Value{}, false
		}

		return reflect.ValueOf(&flag), true
	case intPtrType:
		number, ok := integral(raw, math.MinInt32, math.MaxInt32)
		if !ok {
			return reflect.Value{}, false
		}

		narrowed := int(number)

		return reflect.ValueOf(&narrowed), true
	case int64PtrType:
		number, ok := integral(raw, -(1 << 53), 1<<53)
		if !ok {
			return reflect.Value{}, false
		}

		return reflect.ValueOf(&number), true
	case float64PtrType:
		var number float64
		if json.Unmarshal(raw, &number) != nil {
			return reflect.Value{}, false
		}

		return reflect.ValueOf(&number), true
	case stringSliceType:
		list := einList(raw)
		if list == nil {
			return reflect.Value{}, false
		}

		return reflect.ValueOf(list), true
	case orgTypesType:
		list, ok := organizationTypes(raw)
		if !ok {
			return reflect.Value{}, false
		}

		return reflect.ValueOf(list), true
	case apiErrorsType:
		return reflect.ValueOf(normalizeAPIErrors(raw)), true
	}

	return reflect.Value{}, false
}

func stringOrJSONText(raw json.RawMessage) string {
	var text string
	if json.Unmarshal(raw, &text) == nil {
		return text
	}

	return string(bytes.TrimSpace(raw))
}

// integral reads a JSON number that holds a whole value within [min, max].
func integral(raw json.RawMessage, min, max float64) (int64, bool) {
	var number float64
	if json.Unmarshal(raw, &number) != nil {
		return 0, false
	}

	if number != math.Trunc(number) || number < min || number > max {
		return 0, false
	}

	return int64(number), true
}

// einList reads EINs sent as an array of strings or as one comma-separated
// string. Non-string array entries are skipped.
func einList(raw json.RawMessage) []string {
	var joined string
	if json.Unmarshal(raw, &joined) == nil {
		list := []string{}

		for _, part := range strings.Split(joined, ",") {
			if part = strings.TrimSpace(part); part != "" {
				list = append(list, part)
			}
		}

		return list
	}

	var entries []json.RawMessage
	if json.Unmarshal(raw, &entries) != nil {
		return nil
	}

	list := []string{}

	for _, entry := range entries {
		var ein string
		if json.Unmarshal(entry, &ein) == nil {
			list = append(list, ein)
		}
	}

	return list
}

// organizationTypes reads the deductibility entries. A null entry stays a nil
// element — the API sends one where Publication 78 has a row it cannot
// resolve — and an entry that is not an object is skipped.
func organizationTypes(raw json.RawMessage) ([]*OrganizationType, bool) {
	var entries []json.RawMessage
	if json.Unmarshal(raw, &entries) != nil {
		return nil, false
	}

	list := []*OrganizationType{}

	for _, entry := range entries {
		if isJSONNull(entry) {
			list = append(list, nil)
			continue
		}

		fields, err := parseObject(entry)
		if err != nil {
			continue
		}

		item := &OrganizationType{Fields: fields}
		decodeDeclared(item, fields)
		list = append(list, item)
	}

	return list, true
}

// normalizeAPIErrors reads the envelope's errors, which the API sends as a
// list, a single object, a bare string, or null.
func normalizeAPIErrors(raw json.RawMessage) []APIErrorDetail {
	if len(bytes.TrimSpace(raw)) == 0 || isJSONNull(raw) {
		return []APIErrorDetail{}
	}

	var reason string
	if json.Unmarshal(raw, &reason) == nil {
		if strings.TrimSpace(reason) == "" {
			return []APIErrorDetail{}
		}

		fields, _ := parseObject(mustMarshal(map[string]string{"reason": reason}))

		return []APIErrorDetail{{Reason: reason, Fields: fields}}
	}

	if fields, err := parseObject(raw); err == nil {
		return []APIErrorDetail{errorDetailFrom(fields)}
	}

	var entries []json.RawMessage
	if json.Unmarshal(raw, &entries) != nil {
		return []APIErrorDetail{}
	}

	details := []APIErrorDetail{}

	for _, entry := range entries {
		if fields, err := parseObject(entry); err == nil {
			details = append(details, errorDetailFrom(fields))
		}
	}

	return details
}

func errorDetailFrom(fields Object) APIErrorDetail {
	detail := APIErrorDetail{Fields: fields}
	decodeDeclared(&detail, fields)

	return detail
}

func mustMarshal(value any) []byte {
	data, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}

	return data
}
