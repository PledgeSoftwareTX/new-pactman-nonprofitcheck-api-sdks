package pactman

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
)

// Object is the set of fields the API returned for one JSON object, exactly as
// it sent them and in the order it sent them.
//
// It is the seam that keeps this SDK forward compatible. A field a newer API
// version adds is not declared on the typed models, but it is here, readable
// without a decoding failure or an SDK upgrade. It is also the only place that
// can tell "the API returned this field as null" apart from "the API did not
// return this field": the typed models read both as nil, and Has does not.
//
// An Object is immutable. Its zero value holds no fields.
type Object struct {
	src    json.RawMessage
	names  []string
	values map[string]json.RawMessage
}

var errNotObject = errors.New("pactman: JSON value is not an object")

// Has reports whether the API returned the field, including when it returned
// it as null.
func (o Object) Has(name string) bool {
	_, ok := o.values[name]

	return ok
}

// IsNull reports whether the API returned the field as JSON null. An absent
// field is not null.
func (o Object) IsNull(name string) bool {
	raw, ok := o.values[name]

	return ok && isJSONNull(raw)
}

// Get returns the field's value as raw JSON, and whether the API returned it.
// Decode the value with json.Unmarshal into whatever type you expect.
func (o Object) Get(name string) (json.RawMessage, bool) {
	raw, ok := o.values[name]

	return raw, ok
}

// Names returns the field names the API returned, in the order it returned them.
func (o Object) Names() []string {
	return append([]string(nil), o.names...)
}

// Len returns how many fields the API returned.
func (o Object) Len() int {
	return len(o.names)
}

// MarshalJSON returns the object exactly as it was received. The zero Object
// marshals as null.
func (o Object) MarshalJSON() ([]byte, error) {
	if o.src == nil {
		return []byte("null"), nil
	}

	return o.src, nil
}

// UnmarshalJSON reads a JSON object. JSON null leaves the Object empty; any
// other non-object value is an error.
func (o *Object) UnmarshalJSON(data []byte) error {
	if isJSONNull(data) {
		*o = Object{}

		return nil
	}

	parsed, err := parseObject(data)
	if err != nil {
		return err
	}

	*o = parsed

	return nil
}

// parseObject reads a JSON object, keeping every field's raw value and the
// order the fields arrived in. A repeated key keeps its first position and its
// last value, as JSON.parse does.
func parseObject(data []byte) (Object, error) {
	trimmed := bytes.TrimSpace(data)
	dec := json.NewDecoder(bytes.NewReader(trimmed))

	open, err := dec.Token()
	if err != nil {
		return Object{}, err
	}

	if delim, ok := open.(json.Delim); !ok || delim != '{' {
		return Object{}, errNotObject
	}

	object := Object{
		src:    append(json.RawMessage(nil), trimmed...),
		values: map[string]json.RawMessage{},
	}

	for dec.More() {
		key, err := dec.Token()
		if err != nil {
			return Object{}, err
		}

		var raw json.RawMessage
		if err := dec.Decode(&raw); err != nil {
			return Object{}, err
		}

		name, _ := key.(string)

		if _, seen := object.values[name]; !seen {
			object.names = append(object.names, name)
		}

		object.values[name] = raw
	}

	if _, err := dec.Token(); err != nil {
		return Object{}, err
	}

	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return Object{}, errors.New("pactman: unexpected data after a JSON object")
	}

	return object, nil
}

func isJSONNull(raw []byte) bool {
	return string(bytes.TrimSpace(raw)) == "null"
}
