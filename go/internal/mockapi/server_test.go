package mockapi

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"testing"
	"time"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/contract"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

const key = "mock-test-key"

func start(t *testing.T) *Server {
	t.Helper()

	server, err := Start(Options{APIKey: key})
	if err != nil {
		t.Fatal(err)
	}

	t.Cleanup(server.Close)

	return server
}

func client(t *testing.T, server *Server, apiKey string, opts ...pactman.ClientOption) *pactman.Client {
	t.Helper()

	c, err := pactman.NewClient(apiKey, append([]pactman.ClientOption{pactman.WithBaseURL(server.URL)}, opts...)...)
	if err != nil {
		t.Fatal(err)
	}

	return c
}

func fastRetries(maxRetries int) pactman.ClientOption {
	policy := pactman.DefaultRetryPolicy()
	policy.MaxRetries = maxRetries
	policy.InitialDelay = time.Millisecond
	policy.Jitter = false

	return pactman.WithRetryPolicy(policy)
}

func TestServer(t *testing.T) {
	ctx := context.Background()

	t.Run("serves a record and counts it", func(t *testing.T) {
		result, err := client(t, start(t), key).Nonprofits.Check(ctx, "41-1787097")
		if err != nil {
			t.Fatal(err)
		}

		if result.Nonprofit == nil || *result.Nonprofit.OrganizationName != "MEALS TODAY EXAMPLE NONPROFIT" {
			t.Fatalf("nonprofit = %+v", result.Nonprofit)
		}

		if result.CheckCount == nil || *result.CheckCount != 1 || result.RequestID == "" {
			t.Errorf("count %v, request id %q", result.CheckCount, result.RequestID)
		}
	})

	t.Run("matches a batch by set membership and bills what it served", func(t *testing.T) {
		result, err := client(t, start(t), key).Nonprofits.CheckBulk(ctx,
			[]string{PublicCharitySecond, NoRecord, PublicCharity, PublicCharitySecond})
		if err != nil {
			t.Fatal(err)
		}

		var eins []string
		for _, org := range result.Organizations {
			eins = append(eins, *org.EIN)
		}

		if !slices.Equal(eins, []string{PublicCharity, PublicCharitySecond}) {
			t.Errorf("organizations = %v, want sorted and collapsed", eins)
		}

		if !slices.Equal(result.NotFoundEINs, []string{NoRecord}) || *result.CheckCount != 3 {
			t.Errorf("not found %v, count %d", result.NotFoundEINs, *result.CheckCount)
		}
	})

	t.Run("answers a batch with no matches as a 404", func(t *testing.T) {
		_, err := client(t, start(t), key).Nonprofits.CheckBulk(ctx, []string{NoRecord})

		if !errors.Is(err, pactman.ErrNotFound) {
			t.Fatalf("err = %v", err)
		}
	})

	t.Run("rejects the wrong key", func(t *testing.T) {
		_, err := client(t, start(t), "wrong-key").Nonprofits.Check(ctx, PublicCharity)

		if !errors.Is(err, pactman.ErrAuthentication) {
			t.Fatalf("err = %v", err)
		}
	})

	t.Run("answers an unknown EIN with a 404", func(t *testing.T) {
		if _, err := client(t, start(t), key).Nonprofits.Check(ctx, NoRecord); !errors.Is(err, pactman.ErrNotFound) {
			t.Fatalf("err = %v", err)
		}
	})

	t.Run("rate limits the control EIN with Retry-After", func(t *testing.T) {
		_, err := client(t, start(t), key, pactman.WithoutRetries()).Nonprofits.Check(ctx, RateLimited)

		var apiErr *pactman.APIError
		if !errors.As(err, &apiErr) || apiErr.Status != 429 || apiErr.RetryAfter == nil || *apiErr.RetryAfter != time.Second {
			t.Fatalf("err = %v", err)
		}
	})

	t.Run("fails the transient control EIN twice, then serves it", func(t *testing.T) {
		c := client(t, start(t), key, fastRetries(2))

		result, err := c.Nonprofits.Check(ctx, TransientFailure)
		if err != nil || result.Nonprofit == nil {
			t.Fatalf("result %+v, err %v", result, err)
		}

		if _, err := c.Nonprofits.Check(ctx, TransientFailure, pactman.WithoutRetries()); !errors.Is(err, pactman.ErrServer) {
			t.Errorf("the failure budget did not reset after a success: %v", err)
		}
	})

	t.Run("holds the slow control EIN open past a short timeout, and closes cleanly", func(t *testing.T) {
		server := start(t)
		started := time.Now()

		_, err := client(t, server, key, pactman.WithTimeout(50*time.Millisecond), pactman.WithoutRetries()).
			Nonprofits.Check(ctx, Slow)

		if !errors.Is(err, pactman.ErrTimeout) || time.Since(started) > 2*time.Second {
			t.Fatalf("err %v after %s", err, time.Since(started))
		}

		server.Close()
	})
}

func TestFixtures(t *testing.T) {
	predicted, err := contract.Load()
	if err != nil {
		t.Fatal(err)
	}

	extras := map[string][]string{
		FutureFields:        {"state_charity_registration_status", "watchlist_screening"},
		PendingSourceFields: {"aroe_list_published_date", "bmf_city", "bmf_deductability_text", "bmf_source_pf_filing_req_cd", "bmf_state", "bmf_street_address", "ofac_list_published_date", "pub78_source_org_type_1", "pub78_source_org_type_2", "pub78_source_org_type_3"},
	}

	for ein, record := range Organizations(time.Now()) {
		data, _ := record.MarshalJSON()

		var nonprofit pactman.Nonprofit
		if err := json.Unmarshal(data, &nonprofit); err != nil {
			t.Fatalf("%s does not decode: %v", ein, err)
		}

		if nonprofit.EIN == nil || *nonprofit.EIN != ein {
			t.Errorf("record filed under %s carries EIN %v", ein, nonprofit.EIN)
		}

		var unknown []string

		for _, name := range nonprofit.Fields.Names() {
			if _, ok := predicted.Nonprofit[name]; !ok {
				unknown = append(unknown, name)
			}
		}

		slices.Sort(unknown)

		if want := extras[ein]; !slices.Equal(unknown, want) {
			t.Errorf("%s carries fields the contract does not predict: %v, want %v", ein, unknown, want)
		}

		for name := range predicted.Nonprofit {
			if !record.Has(name) && !(ein == SparseIdentity && name == "ofac_status") {
				t.Errorf("%s is missing %s", ein, name)
			}
		}
	}
}
