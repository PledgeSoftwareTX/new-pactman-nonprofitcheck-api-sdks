package pactman

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"
)

func TestCheck(t *testing.T) {
	ctx := context.Background()

	t.Run("sends exactly one authenticated request and returns a decoded model", func(t *testing.T) {
		doer := serving(stub{body: envelope(wireNonprofit()).encode()})

		result, err := newTestClient(t, doer, nil).Nonprofits.Check(ctx, "411787097")
		if err != nil {
			t.Fatal(err)
		}

		if doer.calls() != 1 {
			t.Fatalf("sent %d requests, want 1", doer.calls())
		}

		request := doer.request(0)

		if request.Method != "GET" || request.URL != testBaseURL+"/api/entities/nonprofitcheck/v1/us/ein/411787097" {
			t.Errorf("request = %s %s", request.Method, request.URL)
		}

		if got := request.Header.Get("Authorization"); got != "Bearer "+testAPIKey {
			t.Errorf("Authorization = %q", got)
		}

		if got := request.Header.Get("Accept"); got != "application/json" {
			t.Errorf("Accept = %q", got)
		}

		if got := request.Header.Get("User-Agent"); !strings.HasPrefix(got, PackageName+"/"+Version) {
			t.Errorf("User-Agent = %q", got)
		}

		if request.Header.Get("Content-Type") != "" {
			t.Errorf("a GET carried Content-Type %q", request.Header.Get("Content-Type"))
		}

		if str(result.Nonprofit.OrganizationName) != "EXAMPLE NONPROFIT" || str(result.Nonprofit.EIN) != "411787097" {
			t.Errorf("nonprofit = %s / %s", str(result.Nonprofit.OrganizationName), str(result.Nonprofit.EIN))
		}
	})

	t.Run("normalizes a hyphenated EIN before building the URL", func(t *testing.T) {
		doer := serving(stub{body: envelope(wireNonprofit()).encode()})

		if _, err := newTestClient(t, doer, nil).Nonprofits.Check(ctx, " 41-1787097 "); err != nil {
			t.Fatal(err)
		}

		if url := doer.request(0).URL; !strings.HasSuffix(url, "/us/ein/411787097") {
			t.Errorf("URL = %s", url)
		}
	})

	t.Run("maps usage information from the envelope", func(t *testing.T) {
		body := envelope(wireNonprofit())
		body.NonprofitCheckCount = ptr[int64](7)
		body.TimeTaken = ptr(42.0)

		result, err := newTestClient(t, serving(stub{body: body.encode()}), nil).Nonprofits.Check(ctx, "411787097")
		if err != nil {
			t.Fatal(err)
		}

		if result.CheckCount == nil || *result.CheckCount != 7 {
			t.Errorf("CheckCount = %v", result.CheckCount)
		}

		if result.TimeTaken == nil || *result.TimeTaken != 42*time.Millisecond {
			t.Errorf("TimeTaken = %v", result.TimeTaken)
		}

		if result.Status != 200 {
			t.Errorf("Status = %d", result.Status)
		}

		if result.Errors == nil || len(result.Errors) != 0 {
			t.Errorf("Errors = %#v, want an empty list", result.Errors)
		}
	})

	t.Run("keeps null and false distinct", func(t *testing.T) {
		data := wireNonprofit(setRaw("pub78_verified", "false"), setNull("bmf_status"), setRaw("irs_bmf_pub78_conflict", "false"))

		result, err := newTestClient(t, serving(stub{body: envelope(data).encode()}), nil).Nonprofits.Check(ctx, "411787097")
		if err != nil {
			t.Fatal(err)
		}

		n := result.Nonprofit

		if n.Pub78Verified == nil || *n.Pub78Verified {
			t.Errorf("Pub78Verified = %v, want false", n.Pub78Verified)
		}

		if n.BMFStatus != nil || !n.Fields.Has("bmf_status") || !n.Fields.IsNull("bmf_status") {
			t.Errorf("bmf_status: typed %v, has %v, null %v", n.BMFStatus, n.Fields.Has("bmf_status"), n.Fields.IsNull("bmf_status"))
		}

		if n.RevocationCode != nil || !n.Fields.IsNull("revocation_code") {
			t.Error("revocation_code should read as nil and be recorded as null")
		}

		if n.IRSBMFPub78Conflict == nil || *n.IRSBMFPub78Conflict {
			t.Errorf("IRSBMFPub78Conflict = %v, want false", n.IRSBMFPub78Conflict)
		}

		if !strings.Contains(str(n.OFACStatus), "NOT included") {
			t.Errorf("OFACStatus = %s", str(n.OFACStatus))
		}
	})

	t.Run("keeps unknown future fields readable", func(t *testing.T) {
		body := envelope(wireNonprofit(setRaw("future_source_status", `"listed"`))).
			encode(setRaw("future_envelope_field", `{"nested":true}`))

		result, err := newTestClient(t, serving(stub{body: body}), nil).Nonprofits.Check(ctx, "411787097")
		if err != nil {
			t.Fatal(err)
		}

		if str(result.Nonprofit.OrganizationName) != "EXAMPLE NONPROFIT" {
			t.Error("a known field was lost alongside an unknown one")
		}

		if raw, ok := result.Nonprofit.Fields.Get("future_source_status"); !ok || string(raw) != `"listed"` {
			t.Errorf("future_source_status = %s, %v", raw, ok)
		}

		if raw, ok := result.Raw.Fields.Get("future_envelope_field"); !ok || string(raw) != `{"nested":true}` {
			t.Errorf("future_envelope_field = %s, %v", raw, ok)
		}

		marshaled, err := json.Marshal(result.Raw)
		if err != nil || string(marshaled) != string(body) {
			t.Errorf("json.Marshal(result.Raw) = %s, %v; want the body as received", marshaled, err)
		}
	})

	t.Run("keeps a record whose field changed type", func(t *testing.T) {
		data := wireNonprofit(setRaw("bmf_status", `"true"`), setRaw("ruling_year", "2024"))

		result, err := newTestClient(t, serving(stub{body: envelope(data).encode()}), nil).Nonprofits.Check(ctx, "411787097")
		if err != nil {
			t.Fatal(err)
		}

		n := result.Nonprofit

		if n.BMFStatus != nil {
			t.Errorf("a string bmf_status read as a boolean: %v", *n.BMFStatus)
		}

		if raw, _ := n.Fields.Get("bmf_status"); string(raw) != `"true"` {
			t.Errorf("the original bmf_status is not in Fields: %s", raw)
		}

		if str(n.RulingYear) != "2024" {
			t.Errorf("a numeric ruling_year should stay readable as its JSON text, got %s", str(n.RulingYear))
		}

		if str(n.OrganizationName) != "EXAMPLE NONPROFIT" {
			t.Error("one mistyped field cost the rest of the record")
		}
	})

	t.Run("returns a nil record rather than an error when data is null", func(t *testing.T) {
		body := envelope(nil)
		body.NonprofitCheckCount = ptr[int64](0)

		result, err := newTestClient(t, serving(stub{body: body.encode()}), nil).Nonprofits.Check(ctx, "411787097")
		if err != nil {
			t.Fatal(err)
		}

		if result.Nonprofit != nil {
			t.Errorf("Nonprofit = %+v, want nil", result.Nonprofit)
		}

		if result.CheckCount == nil || *result.CheckCount != 0 {
			t.Errorf("CheckCount = %v, want 0", result.CheckCount)
		}
	})

	t.Run("reads the first record when data arrives as a list", func(t *testing.T) {
		body := envelope(rawList(wireNonprofit()))

		result, err := newTestClient(t, serving(stub{body: body.encode()}), nil).Nonprofits.Check(ctx, "411787097")
		if err != nil || result.Nonprofit == nil || str(result.Nonprofit.EIN) != "411787097" {
			t.Fatalf("result = %+v, %v", result, err)
		}
	})

	t.Run("survives an empty successful body", func(t *testing.T) {
		result, err := newTestClient(t, serving(stub{}), nil).Nonprofits.Check(ctx, "411787097")
		if err != nil || result.Nonprofit != nil || result.CheckCount != nil {
			t.Fatalf("result = %+v, %v", result, err)
		}
	})

	t.Run("fails locally on a malformed EIN without sending a request", func(t *testing.T) {
		doer := serving(stub{body: envelope(wireNonprofit()).encode()})

		_, err := newTestClient(t, doer, nil).Nonprofits.Check(ctx, "41178709")

		if !errors.Is(err, ErrValidation) || doer.calls() != 0 {
			t.Fatalf("err = %v, requests = %d", err, doer.calls())
		}
	})

	t.Run("rejects a nil context without sending a request", func(t *testing.T) {
		doer := serving(stub{body: envelope(wireNonprofit()).encode()})

		//lint:ignore SA1012 a nil context is the input under test
		_, err := newTestClient(t, doer, nil).Nonprofits.Check(nil, "411787097")

		if !errors.Is(err, ErrValidation) || doer.calls() != 0 {
			t.Fatalf("err = %v, requests = %d", err, doer.calls())
		}
	})
}

func TestCheckBulk(t *testing.T) {
	ctx := context.Background()
	emptyBulk := func() json.RawMessage { return envelope(rawList()).encode() }

	t.Run("sends one request with a bare JSON array of normalized EINs", func(t *testing.T) {
		second := wireNonprofit(setRaw("ein", `"996589560"`))
		doer := serving(stub{body: envelope(rawList(wireNonprofit(), second)).encode()})

		result, err := newTestClient(t, doer, nil).Nonprofits.CheckBulk(ctx, []string{"41-1787097", "996589560"})
		if err != nil {
			t.Fatal(err)
		}

		request := doer.request(0)

		if doer.calls() != 1 || request.Method != "POST" || request.URL != testBaseURL+"/api/entities/nonprofitcheckbulk/v1/us/eins" {
			t.Fatalf("%d requests; first %s %s", doer.calls(), request.Method, request.URL)
		}

		if got := request.Header.Get("Content-Type"); got != "application/json" {
			t.Errorf("Content-Type = %q", got)
		}

		if got := sentEINs(t, request); !slices.Equal(got, []string{"411787097", "996589560"}) {
			t.Errorf("body = %v", got)
		}

		if len(result.Organizations) != 2 || str(result.Organizations[1].EIN) != "996589560" {
			t.Errorf("organizations = %d", len(result.Organizations))
		}

		if result.NotFoundEINs == nil || len(result.NotFoundEINs) != 0 {
			t.Errorf("NotFoundEINs = %#v, want an empty list", result.NotFoundEINs)
		}
	})

	t.Run("preserves input order and duplicates by default", func(t *testing.T) {
		doer := serving(stub{body: emptyBulk()})

		if _, err := newTestClient(t, doer, nil).Nonprofits.CheckBulk(ctx, []string{"996589560", "41-1787097", "996589560"}); err != nil {
			t.Fatal(err)
		}

		if got := sentEINs(t, doer.request(0)); !slices.Equal(got, []string{"996589560", "411787097", "996589560"}) {
			t.Errorf("body = %v", got)
		}
	})

	t.Run("removes duplicates only when dedupe is requested", func(t *testing.T) {
		doer := serving(stub{body: emptyBulk()})

		if _, err := newTestClient(t, doer, nil).Nonprofits.CheckBulk(ctx, []string{"996589560", "99-6589560", "41-1787097"}, WithDedupe()); err != nil {
			t.Fatal(err)
		}

		if got := sentEINs(t, doer.request(0)); !slices.Equal(got, []string{"996589560", "411787097"}) {
			t.Errorf("body = %v", got)
		}
	})

	t.Run("rejects an empty or nil list locally", func(t *testing.T) {
		for _, eins := range [][]string{{}, nil} {
			doer := serving(stub{body: emptyBulk()})

			_, err := newTestClient(t, doer, nil).Nonprofits.CheckBulk(ctx, eins)

			if !errors.Is(err, ErrValidation) || doer.calls() != 0 {
				t.Fatalf("eins %#v: err = %v, requests = %d", eins, err, doer.calls())
			}
		}
	})

	t.Run("rejects the whole batch when one EIN is malformed, before sending", func(t *testing.T) {
		doer := serving(stub{body: emptyBulk()})

		_, err := newTestClient(t, doer, nil).Nonprofits.CheckBulk(ctx, []string{"411787097", "not-an-ein"})

		var verr *ValidationError
		if !errors.As(err, &verr) || len(verr.Issues) != 1 || verr.Issues[0].Index != 1 || doer.calls() != 0 {
			t.Fatalf("err = %v, requests = %d", err, doer.calls())
		}
	})

	t.Run("enforces the server batch limit locally, from a single constant", func(t *testing.T) {
		doer := serving(stub{body: emptyBulk()})

		_, err := newTestClient(t, doer, nil).Nonprofits.CheckBulk(ctx, repeat("411787097", MaxBulkEINs+1))

		if !errors.Is(err, ErrValidation) || !strings.Contains(err.Error(), "at most 50 EINs") || doer.calls() != 0 {
			t.Fatalf("err = %v, requests = %d", err, doer.calls())
		}
	})

	t.Run("accepts exactly the batch limit", func(t *testing.T) {
		doer := serving(stub{body: emptyBulk()})

		if _, err := newTestClient(t, doer, nil).Nonprofits.CheckBulk(ctx, repeat("411787097", MaxBulkEINs)); err != nil {
			t.Fatal(err)
		}

		if doer.calls() != 1 {
			t.Errorf("requests = %d", doer.calls())
		}
	})

	t.Run("collapses duplicates before the limit applies", func(t *testing.T) {
		doer := serving(stub{body: emptyBulk()})

		var eins []string
		for i := range MaxBulkEINs + 10 {
			eins = append(eins, "10000000"+string(rune('0'+i%10)))
		}

		if _, err := newTestClient(t, doer, nil).Nonprofits.CheckBulk(ctx, eins, WithDedupe()); err != nil {
			t.Fatal(err)
		}

		if got := sentEINs(t, doer.request(0)); len(got) != 10 {
			t.Errorf("sent %d EINs, want 10", len(got))
		}
	})

	t.Run("surfaces per-item not-found results from a successful response", func(t *testing.T) {
		body := envelope(rawList(wireNonprofit()))
		body.Errors = encodeList(APIErrorDetail{
			Resource: "nonprofitcheckbulk",
			Reason:   "There are no matching nonprofits in our records for this set of EINs",
			Code:     ptr(404),
			EINs:     []string{"996589560"},
		})

		result, err := newTestClient(t, serving(stub{body: body.encode()}), nil).Nonprofits.CheckBulk(ctx, []string{"411787097", "996589560"})
		if err != nil {
			t.Fatal(err)
		}

		if len(result.Organizations) != 1 || !slices.Equal(result.NotFoundEINs, []string{"996589560"}) {
			t.Errorf("organizations = %d, not found = %v", len(result.Organizations), result.NotFoundEINs)
		}

		if len(result.Errors) != 1 || result.Errors[0].Code == nil || *result.Errors[0].Code != 404 {
			t.Errorf("errors = %+v", result.Errors)
		}

		if result.CheckCount == nil || *result.CheckCount != 1 {
			t.Errorf("CheckCount = %v", result.CheckCount)
		}
	})

	t.Run("reads not-found EINs sent as a comma-separated string", func(t *testing.T) {
		body := envelope(rawList())
		body.Errors = json.RawMessage(`[{"reason":"no matching nonprofits","eins":"996589560, 411787098"}]`)

		result, err := newTestClient(t, serving(stub{body: body.encode()}), nil).Nonprofits.CheckBulk(ctx, []string{"996589560", "411787098"})
		if err != nil {
			t.Fatal(err)
		}

		if !slices.Equal(result.NotFoundEINs, []string{"996589560", "411787098"}) {
			t.Errorf("NotFoundEINs = %v", result.NotFoundEINs)
		}
	})

	t.Run("reads organizations from a wrapped data object as well as a bare array", func(t *testing.T) {
		body := envelope(json.RawMessage(`{"organizations":` + string(rawList(wireNonprofit())) + `}`))

		result, err := newTestClient(t, serving(stub{body: body.encode()}), nil).Nonprofits.CheckBulk(ctx, []string{"411787097"})
		if err != nil || len(result.Organizations) != 1 {
			t.Fatalf("result = %+v, %v", result, err)
		}
	})

	t.Run("does not modify the caller's slice", func(t *testing.T) {
		supplied := []string{"41-1787097", "41-1787097"}

		if _, err := newTestClient(t, serving(stub{body: emptyBulk()}), nil).Nonprofits.CheckBulk(ctx, supplied, WithDedupe()); err != nil {
			t.Fatal(err)
		}

		if !slices.Equal(supplied, []string{"41-1787097", "41-1787097"}) {
			t.Errorf("caller's slice = %v", supplied)
		}
	})
}
