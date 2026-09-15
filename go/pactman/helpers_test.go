package pactman

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"
)

const (
	// testAPIKey must never appear in any diagnostic output.
	testAPIKey  = "pactman_test_key_do_not_leak_8f2b"
	testBaseURL = "http://mock.test"

	ofacNoMatch = "This organization was NOT included in the Office of Foreign Assets Control " +
		"Specially Designated Nationals (SDN) list."
)

func ptr[T any](value T) *T { return &value }

// str reads an optional string for an assertion, showing nil distinctly.
func str(value *string) string {
	if value == nil {
		return "<nil>"
	}

	return *value
}

// stub is a canned HTTP response, or a failure in place of one.
type stub struct {
	status  int // 200 when zero
	body    json.RawMessage
	text    string // sent when body is nil
	headers map[string]string
	err     error // returned by Do instead of a response
	hang    bool  // blocks until the request's context ends
}

type recordedRequest struct {
	Method string
	URL    string
	Header http.Header
	Body   []byte
}

// fakeDoer serves stubs in order; the last one repeats once the queue runs
// out, so a retry test ends on a stable outcome.
type fakeDoer struct {
	mu        sync.Mutex
	stubs     []stub
	requests  []recordedRequest
	onRequest func(n int)
}

func serving(stubs ...stub) *fakeDoer { return &fakeDoer{stubs: stubs} }

func (f *fakeDoer) Do(req *http.Request) (*http.Response, error) {
	var body []byte
	if req.Body != nil {
		body, _ = io.ReadAll(req.Body)
	}

	f.mu.Lock()
	f.requests = append(f.requests, recordedRequest{req.Method, req.URL.String(), req.Header.Clone(), body})
	n := len(f.requests)
	next := f.stubs[min(n, len(f.stubs))-1]
	hook := f.onRequest
	f.mu.Unlock()

	if hook != nil {
		hook(n)
	}

	if next.hang {
		<-req.Context().Done()

		return nil, req.Context().Err()
	}

	if next.err != nil {
		return nil, next.err
	}

	status := next.status
	if status == 0 {
		status = http.StatusOK
	}

	header := http.Header{"Content-Type": {"application/json"}}
	for name, value := range next.headers {
		header.Set(name, value)
	}

	payload := next.text
	if next.body != nil {
		payload = string(next.body)
	}

	return &http.Response{
		StatusCode: status,
		Header:     header,
		Body:       io.NopCloser(strings.NewReader(payload)),
		Request:    req,
	}, nil
}

func (f *fakeDoer) calls() int {
	f.mu.Lock()
	defer f.mu.Unlock()

	return len(f.requests)
}

func (f *fakeDoer) request(i int) recordedRequest {
	f.mu.Lock()
	defer f.mu.Unlock()

	return f.requests[i]
}

// fakeClock records the delays it is asked for instead of waiting, so retry
// tests stay instant, and holds time still so throttle spacing is exact.
type fakeClock struct {
	mu     sync.Mutex
	delays []time.Duration
	jitter float64
	now    time.Time
}

func newClock() *fakeClock {
	return &fakeClock{jitter: 1, now: time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)}
}

func (c *fakeClock) hooks() hooks {
	return hooks{
		sleep: func(ctx context.Context, d time.Duration) error {
			if err := ctx.Err(); err != nil {
				return err
			}

			c.mu.Lock()
			c.delays = append(c.delays, d)
			c.mu.Unlock()

			return nil
		},
		random: func() float64 { return c.jitter },
		now:    func() time.Time { return c.now },
	}
}

func (c *fakeClock) recorded() []time.Duration {
	c.mu.Lock()
	defer c.mu.Unlock()

	return append([]time.Duration(nil), c.delays...)
}

// newTestClient builds a client against the fake transport and clock.
func newTestClient(t *testing.T, doer HTTPDoer, clock *fakeClock, opts ...ClientOption) *Client {
	t.Helper()

	if clock == nil {
		clock = newClock()
	}

	base := []ClientOption{WithBaseURL(testBaseURL), WithHTTPClient(doer)}

	client, err := newClient(testAPIKey, clock.hooks(), append(base, opts...))
	if err != nil {
		t.Fatalf("newClient: %v", err)
	}

	return client
}

// nonprofitFixture is the published response example, as the typed model.
func nonprofitFixture() Nonprofit {
	return Nonprofit{
		PactmanOrgURL:                ptr("https://pactman.org/profile/nonprofit/example-nonprofit-r5U9r8yRcZ"),
		OrganizationInfoLastModified: ptr("2/22/2026 1:16:30 AM"),
		EIN:                          ptr("411787097"),
		OrganizationName:             ptr("EXAMPLE NONPROFIT"),
		OrganizationNameAKA:          ptr("EXAMPLE N.P"),
		AddressLine1:                 ptr("50 LOWELL AVE"),
		AddressLine2:                 ptr("APT 3B"),
		City:                         ptr("WESTFIELD"),
		State:                        ptr("MA"),
		StateName:                    ptr("Massachusetts"),
		ZIP:                          ptr("01085-2643"),
		FilingReqCode:                ptr("00"),
		Pub78OrganizationName:        ptr("Example Nonprofit"),
		Pub78EIN:                     ptr("411787097"),
		Pub78Verified:                ptr(true),
		Pub78City:                    ptr("Westfield"),
		Pub78State:                   ptr("MA"),
		Pub78Indicator:               ptr("0"),
		OrganizationTypes: []*OrganizationType{{
			OrganizationType:               ptr("Deductions for donations to public charities are generally limited..."),
			DeductibilityLimitation:        ptr("50%"),
			DeductibilityStatusDescription: ptr("PC"),
		}},
		MostRecentPub78:           ptr("12/12/2025 12:00:00 AM"),
		BMFOrganizationName:       ptr("EXAMPLE NONPROFIT"),
		BMFEIN:                    ptr("411787097"),
		BMFStatus:                 ptr(true),
		MostRecentBMF:             ptr("12/09/2025 12:00:00 AM"),
		BMFSubsection:             ptr("03"),
		SubsectionDescription:     ptr("501(c)(3) Public Charity"),
		FoundationCode:            ptr("10"),
		FoundationCodeDescription: ptr("Public charity described in section 509(a)(1) or (2)"),
		FoundationTypeCode:        ptr("pc"),
		FoundationTypeDescription: ptr("Public charity described in section 509(a)(1) or (2)"),
		Foundation509aStatus:      ptr("N/A"),
		RulingMonth:               ptr("07"),
		RulingYear:                ptr("2024"),
		GroupExemption:            ptr("0000"),
		ExemptStatusCode:          ptr("01"),
		OFACStatus:                ptr(ofacNoMatch),
		IRSBMFPub78Conflict:       ptr(false),
		ReportDate:                ptr("3/25/2026 3:28:54 PM"),
	}
}

// The fields the published example sends as null. A typed model cannot say
// "null" (nil means "leave it out"), so they are patched in on the wire.
var fixtureNulls = []string{
	"pub78_church_message", "bmf_church_message", "revocation_code", "revocation_date", "reinstatement_date",
}

// patch replaces one field of an encoded object with raw JSON. "null" sends it
// as null, a name the SDK does not declare sends a field newer than it, and an
// empty raw value removes the field.
type patch struct {
	name string
	raw  string
}

func setNull(name string) patch     { return patch{name, "null"} }
func setRaw(name, raw string) patch { return patch{name, raw} }
func remove(name string) patch      { return patch{name, ""} }

// encode marshals a typed value, then applies the patches.
func encode[T any](value T, patches ...patch) json.RawMessage {
	data, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}

	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		panic(err)
	}

	for _, p := range patches {
		if p.raw == "" {
			delete(fields, p.name)
		} else {
			fields[p.name] = json.RawMessage(p.raw)
		}
	}

	out, err := json.Marshal(fields)
	if err != nil {
		panic(err)
	}

	return out
}

// wireNonprofit is the fixture as the API sends it: the typed record, the
// fields the published example carries as null, then any patches.
func wireNonprofit(patches ...patch) json.RawMessage {
	all := make([]patch, 0, len(fixtureNulls)+len(patches))

	for _, name := range fixtureNulls {
		all = append(all, setNull(name))
	}

	return encode(nonprofitFixture(), append(all, patches...)...)
}

// decodedNonprofit is wireNonprofit read back through the SDK's decoder.
func decodedNonprofit(t *testing.T, patches ...patch) *Nonprofit {
	t.Helper()

	var nonprofit Nonprofit
	if err := json.Unmarshal(wireNonprofit(patches...), &nonprofit); err != nil {
		t.Fatalf("decode fixture: %v", err)
	}

	return &nonprofit
}

// wireEnvelope is the response wrapper, typed as the API documents it.
type wireEnvelope struct {
	Code                int             `json:"code"`
	Message             string          `json:"message"`
	Errors              json.RawMessage `json:"errors"`
	Data                json.RawMessage `json:"data"`
	TimeTaken           *float64        `json:"timeTaken,omitempty"`
	NonprofitCheckCount *int64          `json:"nonprofit_check_count,omitempty"`
}

// envelope wraps data the way a successful response does.
func envelope(data json.RawMessage) wireEnvelope {
	return wireEnvelope{
		Code:                200,
		Message:             "OK",
		Data:                data,
		TimeTaken:           ptr(3.0),
		NonprofitCheckCount: ptr[int64](1),
	}
}

// errorEnvelope is the body of an error response.
func errorEnvelope(code int, message string, details ...APIErrorDetail) wireEnvelope {
	body := wireEnvelope{Code: code, Message: message}

	if len(details) > 0 {
		body.Errors = encodeList(details...)
	}

	return body
}

func (e wireEnvelope) encode(patches ...patch) json.RawMessage { return encode(e, patches...) }

func encodeList[T any](items ...T) json.RawMessage {
	data, err := json.Marshal(items)
	if err != nil {
		panic(err)
	}

	return data
}

func rawList(items ...json.RawMessage) json.RawMessage { return encodeList(items...) }

// repeat is n copies of one EIN. (slices.Repeat is newer than the go.mod floor.)
func repeat(ein string, n int) []string {
	eins := make([]string, n)
	for i := range eins {
		eins[i] = ein
	}

	return eins
}

// sentEINs decodes a bulk request body.
func sentEINs(t *testing.T, request recordedRequest) []string {
	t.Helper()

	var eins []string
	if err := json.Unmarshal(request.Body, &eins); err != nil {
		t.Fatalf("request body %q is not a JSON array of strings: %v", request.Body, err)
	}

	return eins
}
