package pactman

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"testing"
	"time"
)

// checkWith sends one check through a client with retries off.
func checkWith(t *testing.T, response stub) error {
	t.Helper()

	client := newTestClient(t, serving(response), nil, WithoutRetries())
	_, err := client.Nonprofits.Check(context.Background(), "411787097")

	return err
}

func TestStatusMapping(t *testing.T) {
	sentinels := map[ErrorCategory]error{
		CategoryBadRequest:     ErrBadRequest,
		CategoryAuthentication: ErrAuthentication,
		CategoryAuthorization:  ErrAuthorization,
		CategoryNotFound:       ErrNotFound,
		CategoryRateLimit:      ErrRateLimit,
		CategoryServer:         ErrServer,
	}

	cases := []struct {
		status   int
		category ErrorCategory
	}{
		{400, CategoryBadRequest},
		{401, CategoryAuthentication},
		{403, CategoryAuthorization},
		{404, CategoryNotFound},
		{429, CategoryRateLimit},
		{500, CategoryServer},
		{503, CategoryServer},
	}

	for _, tc := range cases {
		t.Run(fmt.Sprintf("maps HTTP %d to %s", tc.status, tc.category), func(t *testing.T) {
			err := checkWith(t, stub{status: tc.status, body: errorEnvelope(tc.status, "failed").encode()})

			var apiErr *APIError
			if !errors.As(err, &apiErr) {
				t.Fatalf("err = %v, want *APIError", err)
			}

			if apiErr.Category() != tc.category || apiErr.Origin() != OriginAPI || apiErr.Status != tc.status {
				t.Errorf("category %s, origin %s, status %d", apiErr.Category(), apiErr.Origin(), apiErr.Status)
			}

			for category, sentinel := range sentinels {
				if errors.Is(err, sentinel) != (category == tc.category) {
					t.Errorf("errors.Is(err, Err for %s) = %v", category, !(category == tc.category))
				}
			}

			if !errors.Is(fmt.Errorf("wrapped: %w", err), sentinels[tc.category]) {
				t.Error("the sentinel does not match through wrapping")
			}
		})
	}

	t.Run("falls back to a general API error for an unexpected status", func(t *testing.T) {
		err := checkWith(t, stub{status: 418, body: json.RawMessage(`{"message":"I'm a teapot"}`)})

		var apiErr *APIError
		if !errors.As(err, &apiErr) || apiErr.Category() != CategoryAPI || apiErr.Status != 418 || apiErr.APIMessage != "I'm a teapot" {
			t.Fatalf("err = %v", err)
		}
	})

	t.Run("keeps response metadata when the body cannot be decoded", func(t *testing.T) {
		err := checkWith(t, stub{
			status:  502,
			text:    "<html>gateway error</html>",
			headers: map[string]string{"Content-Type": "text/html", "X-Request-Id": "req-html-1"},
		})

		var apiErr *APIError
		if !errors.As(err, &apiErr) || apiErr.Category() != CategoryServer {
			t.Fatalf("err = %v", err)
		}

		if apiErr.Status != 502 || apiErr.RequestID != "req-html-1" || string(apiErr.Body) != "<html>gateway error</html>" {
			t.Errorf("status %d, request %q, body %q", apiErr.Status, apiErr.RequestID, apiErr.Body)
		}

		if apiErr.APIMessage != "<html>gateway error</html>" {
			t.Errorf("APIMessage = %q", apiErr.APIMessage)
		}
	})

	t.Run("uses a default message when the API sends none", func(t *testing.T) {
		err := checkWith(t, stub{status: 404})

		if err == nil || !strings.Contains(err.Error(), "no matching record") {
			t.Errorf("err = %v", err)
		}
	})
}

func TestErrorDetail(t *testing.T) {
	t.Run("exposes Retry-After on a 429", func(t *testing.T) {
		err := checkWith(t, stub{status: 429, body: errorEnvelope(429, "Too Many Requests").encode(), headers: map[string]string{"Retry-After": "12"}})

		var apiErr *APIError
		if !errors.As(err, &apiErr) || apiErr.RetryAfter == nil || *apiErr.RetryAfter != 12*time.Second {
			t.Fatalf("err = %v", err)
		}
	})

	t.Run("retains the request ID on a server error", func(t *testing.T) {
		err := checkWith(t, stub{status: 500, body: errorEnvelope(500, "Internal Server Error").encode(), headers: map[string]string{"X-Request-Id": "req-abc-123"}})

		var apiErr *APIError
		if !errors.As(err, &apiErr) || apiErr.RequestID != "req-abc-123" {
			t.Fatalf("err = %v", err)
		}
	})

	t.Run("surfaces the API reason list without string parsing", func(t *testing.T) {
		body := errorEnvelope(400, "Bad Request",
			APIErrorDetail{Resource: "nonprofitcheck", Reason: "Invalid EIN format", Code: ptr(400)},
			APIErrorDetail{Resource: "nonprofitcheck", Reason: "EIN must contain 9 digits"})

		err := checkWith(t, stub{status: 400, body: body.encode()})

		var apiErr *APIError
		if !errors.As(err, &apiErr) {
			t.Fatalf("err = %v", err)
		}

		if len(apiErr.APIErrors) != 2 || apiErr.APIErrors[0].Reason != "Invalid EIN format" {
			t.Errorf("APIErrors = %+v", apiErr.APIErrors)
		}

		if apiErr.APICode == nil || *apiErr.APICode != 400 {
			t.Errorf("APICode = %v", apiErr.APICode)
		}

		if apiErr.APIMessage != "Invalid EIN format; EIN must contain 9 digits" {
			t.Errorf("APIMessage = %q", apiErr.APIMessage)
		}
	})

	t.Run("reports transport failures as network errors that unwrap to the cause", func(t *testing.T) {
		err := checkWith(t, stub{err: io.ErrUnexpectedEOF})

		var nerr *NetworkError
		if !errors.As(err, &nerr) || nerr.Category() != CategoryNetwork || nerr.Origin() != OriginLocal || nerr.Attempts != 1 {
			t.Fatalf("err = %v", err)
		}

		if !errors.Is(err, io.ErrUnexpectedEOF) || !errors.Is(err, ErrNetwork) {
			t.Error("the network error does not match its cause and its sentinel")
		}
	})

	t.Run("distinguishes local errors from API errors", func(t *testing.T) {
		client := newTestClient(t, serving(stub{status: 400, body: json.RawMessage(`{"message":"Bad Request"}`)}), nil, WithoutRetries())

		_, local := client.Nonprofits.Check(context.Background(), "bad-ein")
		_, remote := client.Nonprofits.Check(context.Background(), "411787097")

		var localErr, remoteErr Error
		if !errors.As(local, &localErr) || !errors.As(remote, &remoteErr) {
			t.Fatalf("local %v, remote %v", local, remote)
		}

		if localErr.Origin() != OriginLocal || localErr.Category() != CategoryValidation || remoteErr.Origin() != OriginAPI {
			t.Errorf("local %s/%s, remote %s", localErr.Origin(), localErr.Category(), remoteErr.Origin())
		}
	})

	t.Run("renders a sanitized JSON form without the body", func(t *testing.T) {
		err := checkWith(t, stub{status: 404, body: errorEnvelope(404, "Not Found").encode(), headers: map[string]string{"X-Request-Id": "req-1"}})

		data, marshalErr := json.Marshal(err)
		if marshalErr != nil {
			t.Fatal(marshalErr)
		}

		var rendered struct {
			Name      string  `json:"name"`
			Category  string  `json:"category"`
			Origin    string  `json:"origin"`
			Status    int     `json:"status"`
			RequestID string  `json:"requestId"`
			Attempts  int     `json:"attempts"`
			Body      *string `json:"body"`
		}

		if err := json.Unmarshal(data, &rendered); err != nil {
			t.Fatal(err)
		}

		if rendered.Name != "APIError" || rendered.Category != "not_found" || rendered.Origin != "api" ||
			rendered.Status != 404 || rendered.RequestID != "req-1" || rendered.Attempts != 1 || rendered.Body != nil {
			t.Errorf("json = %s", data)
		}
	})
}

func TestCredentialSafetyInErrors(t *testing.T) {
	cases := map[string]stub{
		"401":             {status: 401, body: errorEnvelope(401, "Unauthorized").encode()},
		"429":             {status: 429, body: errorEnvelope(429, "Too Many Requests").encode(), headers: map[string]string{"Retry-After": "3"}},
		"500":             {status: 500, body: errorEnvelope(500, "Internal Server Error").encode()},
		"network failure": {err: errors.New("connection reset by peer")},
	}

	for label, response := range cases {
		t.Run("keeps the API key out of a "+label+" error", func(t *testing.T) {
			assertNoKey(t, checkWith(t, response))
		})
	}

	t.Run("keeps the API key out of a timeout error", func(t *testing.T) {
		client := newTestClient(t, serving(stub{hang: true}), nil, WithoutRetries(), WithTimeout(5*time.Millisecond))
		_, err := client.Nonprofits.Check(context.Background(), "411787097")

		if !errors.Is(err, ErrTimeout) {
			t.Fatalf("err = %v", err)
		}

		assertNoKey(t, err)
	})
}

func assertNoKey(t *testing.T, err error) {
	t.Helper()

	if err == nil {
		t.Fatal("expected an error")
	}

	data, _ := json.Marshal(err)

	for _, surface := range []string{err.Error(), fmt.Sprintf("%v %+v %#v", err, err, err), string(data)} {
		if strings.Contains(surface, testAPIKey) {
			t.Errorf("the API key appeared in %q", surface)
		}
	}
}
