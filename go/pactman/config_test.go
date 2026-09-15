package pactman

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"net/url"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"
)

func TestClientConstruction(t *testing.T) {
	t.Run("builds a client from the minimum documented configuration", func(t *testing.T) {
		client, err := NewClient(testAPIKey)
		if err != nil {
			t.Fatal(err)
		}

		production, _ := BaseURLForEnvironment(EnvironmentProduction)

		if client.BaseURL() != production || client.Environment() != DefaultEnvironment || client.Timeout() != 30*time.Second {
			t.Errorf("client = %s, %s, %s", client.BaseURL(), client.Environment(), client.Timeout())
		}

		if client.Timeout() != DefaultTimeout {
			t.Errorf("Timeout = %s, want DefaultTimeout", client.Timeout())
		}
	})

	for label, key := range map[string]string{"empty": "", "whitespace-only": "   \t"} {
		t.Run("rejects an "+label+" API key locally", func(t *testing.T) {
			_, err := NewClient(key)

			var cerr *ConfigurationError
			if !errors.As(err, &cerr) || !errors.Is(err, ErrConfiguration) {
				t.Fatalf("err = %v", err)
			}

			if cerr.Category() != CategoryConfiguration || cerr.Origin() != OriginLocal {
				t.Errorf("category/origin = %s/%s", cerr.Category(), cerr.Origin())
			}
		})
	}

	t.Run("sends no request when the API key is empty", func(t *testing.T) {
		doer := serving(stub{})

		if _, err := NewClient("", WithHTTPClient(doer)); err == nil {
			t.Fatal("an empty key was accepted")
		}

		if doer.calls() != 0 {
			t.Errorf("requests = %d", doer.calls())
		}
	})

	t.Run("skips a nil option", func(t *testing.T) {
		var none ClientOption

		if _, err := NewClient(testAPIKey, none); err != nil {
			t.Fatal(err)
		}
	})
}

func TestEnvironmentSelection(t *testing.T) {
	t.Run("resolves an https URL for every named environment", func(t *testing.T) {
		for _, environment := range SupportedEnvironments() {
			client, err := NewClient(testAPIKey, WithEnvironment(environment))
			if err != nil {
				t.Fatal(err)
			}

			parsed, err := url.Parse(client.BaseURL())
			if err != nil || parsed.Scheme != "https" {
				t.Errorf("%s resolves to %s", environment, client.BaseURL())
			}
		}
	})

	t.Run("exposes production only; internal QA and sandbox hosts are not selectable", func(t *testing.T) {
		if !slices.Equal(SupportedEnvironments(), []Environment{EnvironmentProduction}) {
			t.Fatalf("SupportedEnvironments = %v", SupportedEnvironments())
		}

		internal := regexp.MustCompile(`(?i)sandbox|sit|qa|hllc\.mobi`)

		for _, environment := range SupportedEnvironments() {
			if baseURL, _ := BaseURLForEnvironment(environment); internal.MatchString(baseURL) {
				t.Errorf("%s points at an internal host: %s", environment, baseURL)
			}
		}
	})

	t.Run("accepts a custom base URL for a local mock server", func(t *testing.T) {
		client, err := NewClient(testAPIKey, WithBaseURL("http://127.0.0.1:4010"))
		if err != nil {
			t.Fatal(err)
		}

		if client.BaseURL() != "http://127.0.0.1:4010" || client.Environment() != "" {
			t.Errorf("client = %s, environment %q", client.BaseURL(), client.Environment())
		}
	})

	t.Run("strips a trailing slash, the query and credentials from a custom base URL", func(t *testing.T) {
		client, err := NewClient(testAPIKey, WithBaseURL("https://user:pass@Example.TEST/proxy/?x=1"))
		if err != nil {
			t.Fatal(err)
		}

		if client.BaseURL() != "https://example.test/proxy" {
			t.Errorf("BaseURL = %s", client.BaseURL())
		}
	})

	for label, baseURL := range map[string]string{
		"not a url":             "not a url",
		"a host without scheme": "entities.pactman.org",
		"empty":                 "",
		"an unsupported scheme": "ftp://entities.pactman.org",
	} {
		t.Run("rejects "+label+" base URLs locally", func(t *testing.T) {
			if _, err := NewClient(testAPIKey, WithBaseURL(baseURL)); !errors.Is(err, ErrConfiguration) {
				t.Errorf("err = %v", err)
			}
		})
	}

	t.Run("rejects an unknown environment name", func(t *testing.T) {
		if _, err := NewClient(testAPIKey, WithEnvironment("staging")); !errors.Is(err, ErrConfiguration) {
			t.Errorf("err = %v", err)
		}
	})
}

func TestOptionValidation(t *testing.T) {
	halfFactor := DefaultRetryPolicy()
	halfFactor.BackoffFactor = 0.5

	negativeDelay := DefaultRetryPolicy()
	negativeDelay.InitialDelay = -time.Second

	rejected := map[string]ClientOption{
		"a zero timeout":                     WithTimeout(0),
		"a negative timeout":                 WithTimeout(-time.Second),
		"a negative retry count":             WithMaxRetries(-1),
		"a backoff factor below 1":           WithRetryPolicy(halfFactor),
		"a zero backoff factor":              WithRetryPolicy(RetryPolicy{}),
		"a negative delay":                   WithRetryPolicy(negativeDelay),
		"a zero request-per-second cap":      WithMaxRequestsPerSecond(0),
		"an infinite request-per-second cap": WithMaxRequestsPerSecond(math.Inf(1)),
		"a NaN request-per-second cap":       WithMaxRequestsPerSecond(math.NaN()),
		"a nil HTTP client":                  WithHTTPClient(nil),
		"an invalid header name":             WithHeader("Bad Header", "x"),
		"a header value with a line break":   WithHeader("X-Trace", "a\r\nInjected: yes"),
	}

	for label, opt := range rejected {
		t.Run("rejects "+label, func(t *testing.T) {
			if _, err := NewClient(testAPIKey, opt); !errors.Is(err, ErrConfiguration) {
				t.Errorf("err = %v", err)
			}
		})
	}

	t.Run("rejects an unusable per-request option as validation, without sending", func(t *testing.T) {
		doer := serving(stub{body: envelope(wireNonprofit()).encode()})

		_, err := newTestClient(t, doer, nil).Nonprofits.Check(context.Background(), "411787097", WithTimeout(0))

		if !errors.Is(err, ErrValidation) || doer.calls() != 0 {
			t.Fatalf("err = %v, requests = %d", err, doer.calls())
		}
	})

	t.Run("honours an explicit timeout", func(t *testing.T) {
		client, err := NewClient(testAPIKey, WithTimeout(1500*time.Millisecond))
		if err != nil || client.Timeout() != 1500*time.Millisecond {
			t.Fatalf("Timeout = %v, %v", client.Timeout(), err)
		}
	})

	t.Run("returns a copy of the retry policy", func(t *testing.T) {
		client, _ := NewClient(testAPIKey)
		policy := client.RetryPolicy()
		policy.RetryableStatuses[0] = 418

		if client.RetryPolicy().RetryableStatuses[0] != 429 {
			t.Error("changing the returned policy changed the client's")
		}
	})
}

func TestHeaders(t *testing.T) {
	t.Run("sends default and per-request headers, and cannot be made to override the owned ones", func(t *testing.T) {
		doer := serving(stub{body: envelope(wireNonprofit()).encode()})
		client := newTestClient(t, doer, nil,
			WithHeader("X-Tenant", "acme"),
			WithHeader("Authorization", "Bearer someone-else"),
			WithHeader("Content-Type", "text/plain"))

		_, err := client.Nonprofits.Check(context.Background(), "411787097",
			WithHeader("X-Trace", "t-1"),
			WithHeader("User-Agent", "spoofed"))
		if err != nil {
			t.Fatal(err)
		}

		header := doer.request(0).Header

		if header.Get("X-Tenant") != "acme" || header.Get("X-Trace") != "t-1" {
			t.Errorf("custom headers = %q, %q", header.Get("X-Tenant"), header.Get("X-Trace"))
		}

		if got := header.Values("Authorization"); !slices.Equal(got, []string{"Bearer " + testAPIKey}) {
			t.Errorf("Authorization = %q", got)
		}

		if !strings.HasPrefix(header.Get("User-Agent"), PackageName) || header.Get("Content-Type") != "" {
			t.Errorf("User-Agent = %q, Content-Type = %q", header.Get("User-Agent"), header.Get("Content-Type"))
		}
	})
}

func TestCredentialRedaction(t *testing.T) {
	client, err := NewClient(testAPIKey, WithMaxRequestsPerSecond(3))
	if err != nil {
		t.Fatal(err)
	}

	t.Run("keeps the key out of JSON", func(t *testing.T) {
		data, err := json.Marshal(client)
		if err != nil {
			t.Fatal(err)
		}

		if strings.Contains(string(data), testAPIKey) || !strings.Contains(string(data), "[redacted]") {
			t.Errorf("json = %s", data)
		}
	})

	t.Run("keeps the key out of every fmt verb", func(t *testing.T) {
		for _, verb := range []string{"%v", "%+v", "%#v", "%s", "%q", "%x", "%d", "%T"} {
			for _, target := range []fmt.Formatter{client, client.Nonprofits} {
				if out := fmt.Sprintf(verb, target); strings.Contains(out, testAPIKey) {
					t.Errorf("%s leaked the key: %s", verb, out)
				}
			}
		}

		if out := fmt.Sprintf("%+v", *client); strings.Contains(out, testAPIKey) {
			t.Errorf("the dereferenced client leaked the key: %s", out)
		}
	})

	t.Run("keeps the key out of slog", func(t *testing.T) {
		var buf bytes.Buffer

		slog.New(slog.NewJSONHandler(&buf, nil)).Info("built", "client", client)
		slog.New(slog.NewTextHandler(&buf, nil)).Info("built", "client", client, "resource", client.Nonprofits)

		if strings.Contains(buf.String(), testAPIKey) {
			t.Errorf("slog leaked the key: %s", buf.String())
		}
	})

	t.Run("keeps the key out of String", func(t *testing.T) {
		if strings.Contains(client.String(), testAPIKey) {
			t.Error(client.String())
		}
	})
}

func TestUserAgent(t *testing.T) {
	ua := userAgent()

	if !strings.HasPrefix(ua, PackageName+"/"+Version+" (go/go") {
		t.Errorf("User-Agent = %q", ua)
	}

	if !regexp.MustCompile(`^\d+\.\d+\.\d+$`).MatchString(Version) {
		t.Errorf("Version %q is not semver-shaped", Version)
	}
}
