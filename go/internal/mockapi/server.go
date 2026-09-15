package mockapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand/v2"
	"net"
	"net/http"
	"os"
	"regexp"
	"sort"
	"strconv"
	"sync"
	"time"
)

// maxBulkEINs mirrors the real service's limit.
const maxBulkEINs = 50

const (
	// slowResponse is how long the Slow control EIN holds a response open.
	slowResponse = 5 * time.Second
	// transientFailures is how many times TransientFailure fails before succeeding.
	transientFailures = 2
)

var singlePath = regexp.MustCompile(`^/api/entities/nonprofitcheck/v1/us/ein/(\d{9})$`)

const bulkPath = "/api/entities/nonprofitcheckbulk/v1/us/eins"

// Options configure Start.
type Options struct {
	// Port to listen on, on 127.0.0.1. 0 picks a free one.
	Port int
	// APIKey is the key the server accepts. Defaults to MOCK_API_KEY, then "mock-key".
	APIKey string
}

// Server is a running mock API. It serves the two check endpoints with the
// real service's envelope, auth header, batch limit, bulk matching semantics
// and cumulative check count.
type Server struct {
	// URL is the base URL to point a client at.
	URL string

	apiKey        string
	organizations map[string]Record
	httpServer    *http.Server
	closing       chan struct{}
	closeOnce     sync.Once

	mu sync.Mutex
	// checksUsed mirrors the real service: a running total for the billing
	// cycle, not the size of the current request.
	checksUsed    int64
	transientLeft int
}

// Start starts the mock API. Close it when done; it leaves nothing running.
func Start(opts Options) (*Server, error) {
	key := opts.APIKey
	if key == "" {
		key = os.Getenv("MOCK_API_KEY")
	}

	if key == "" {
		key = "mock-key"
	}

	listener, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(opts.Port)))
	if err != nil {
		return nil, err
	}

	server := &Server{
		URL:           "http://" + listener.Addr().String(),
		apiKey:        key,
		organizations: Organizations(time.Now()),
		closing:       make(chan struct{}),
		transientLeft: transientFailures,
	}

	server.httpServer = &http.Server{Handler: server, ReadHeaderTimeout: 10 * time.Second}

	go func() {
		if err := server.httpServer.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			fmt.Fprintln(os.Stderr, "mock API stopped:", err)
		}
	}()

	return server, nil
}

// Close stops the server and releases any deferred response.
func (s *Server) Close() {
	s.closeOnce.Do(func() {
		close(s.closing)
		_ = s.httpServer.Close()
	})
}

// HasRecord reports whether the server has a record for the EIN.
func (s *Server) HasRecord(ein string) bool {
	_, ok := s.organizations[ein]

	return ok
}

type detail struct {
	Resource string   `json:"resource"`
	Reason   string   `json:"reason"`
	Code     int      `json:"code,omitempty"`
	EINs     []string `json:"eins,omitempty"`
}

type envelope struct {
	Code                int             `json:"code"`
	Message             string          `json:"message"`
	Errors              []detail        `json:"errors"`
	Data                json.RawMessage `json:"data"`
	TimeTaken           int             `json:"timeTaken"`
	NonprofitCheckCount int64           `json:"nonprofit_check_count"`
}

// bare is the body of a response that never reached a check: no timing and
// no count.
type bare struct {
	Code    int             `json:"code"`
	Message string          `json:"message"`
	Errors  []detail        `json:"errors"`
	Data    json.RawMessage `json:"data"`
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Authorization") != "Bearer "+s.apiKey {
		send(w, http.StatusUnauthorized, bare{
			Code:    401,
			Message: "Unauthorized",
			Errors:  []detail{{Resource: "nonprofitcheck", Reason: "Invalid API Key"}},
		}, nil)

		return
	}

	if match := singlePath.FindStringSubmatch(r.URL.Path); r.Method == http.MethodGet && match != nil {
		s.single(w, r, match[1])

		return
	}

	if r.Method == http.MethodPost && r.URL.Path == bulkPath {
		s.bulk(w, r)

		return
	}

	send(w, http.StatusNotFound, bare{Code: 404, Message: "Not Found"}, nil)
}

func (s *Server) single(w http.ResponseWriter, r *http.Request, ein string) {
	switch ein {
	case RateLimited:
		send(w, http.StatusTooManyRequests, s.failure(429, "Too Many Requests",
			detail{Resource: "nonprofitcheck", Reason: "Rate limit exceeded"}), map[string]string{"Retry-After": "1"})

		return

	case TransientFailure:
		s.mu.Lock()
		failing := s.transientLeft > 0

		if failing {
			s.transientLeft--
		} else {
			s.transientLeft = transientFailures
		}
		s.mu.Unlock()

		if failing {
			send(w, http.StatusServiceUnavailable, s.failure(503, "Service Unavailable",
				detail{Resource: "nonprofitcheck", Reason: "Upstream temporarily unavailable"}), nil)

			return
		}

		s.serveRecord(w, PublicCharity)

		return

	case Slow:
		select {
		case <-time.After(slowResponse):
			s.serveRecord(w, PublicCharity)
		case <-r.Context().Done():
		case <-s.closing:
		}

		return
	}

	if !s.HasRecord(ein) {
		send(w, http.StatusNotFound, s.failure(404, "Not Found",
			detail{Resource: "nonprofitcheck", Reason: "A nonprofit with this EIN does not exist in our records"}), nil)

		return
	}

	s.serveRecord(w, ein)
}

func (s *Server) serveRecord(w http.ResponseWriter, ein string) {
	s.mu.Lock()
	s.checksUsed++
	count := s.checksUsed
	s.mu.Unlock()

	data, _ := s.organizations[ein].MarshalJSON()

	send(w, http.StatusOK, success(data, nil, count), nil)
}

func (s *Server) bulk(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)

	var eins []string
	if json.Unmarshal(body, &eins) != nil || eins == nil {
		send(w, http.StatusBadRequest, s.failure(400, "Bad Request", detail{
			Resource: "nonprofitcheckbulk",
			Reason:   "The nonprofit check bulk API expects an array of EINs as part of the HTTP POST request body",
		}), nil)

		return
	}

	if len(eins) > maxBulkEINs {
		send(w, http.StatusBadRequest, s.failure(400, "Bad Request", detail{
			Resource: "nonprofitcheckbulk",
			Reason:   fmt.Sprintf("A maximum of %d EINs can be supplied to the nonprofit check bulk API", maxBulkEINs),
		}), nil)

		return
	}

	// The real service selects with WHERE ein IN (...): duplicates collapse to
	// one row and the order is the database's, not the request's. Sorting keeps
	// that difference visible instead of accidentally matching.
	unique := map[string]bool{}

	var matched, notFound []string

	for _, ein := range eins {
		if !s.HasRecord(ein) {
			notFound = append(notFound, ein)
		} else if !unique[ein] {
			unique[ein] = true
			matched = append(matched, ein)
		}
	}

	sort.Strings(matched)

	// Every submitted EIN is counted, duplicates included; unmatched ones are
	// refunded, so the count reflects records actually served.
	s.mu.Lock()
	s.checksUsed += int64(len(eins) - len(notFound))
	count := s.checksUsed
	s.mu.Unlock()

	const noMatches = "There are no matching nonprofits in our records for this set of EINs"

	if len(matched) == 0 {
		send(w, http.StatusNotFound, s.failureWithCount(404, "Not Found", count,
			detail{Resource: "nonprofitcheckbulk", Reason: noMatches}), nil)

		return
	}

	records := make([]json.RawMessage, len(matched))
	for i, ein := range matched {
		records[i], _ = s.organizations[ein].MarshalJSON()
	}

	data, _ := json.Marshal(records)

	var errs []detail
	if len(notFound) > 0 {
		errs = []detail{{Resource: "nonprofitcheckbulk", Reason: noMatches, Code: 404, EINs: notFound}}
	}

	send(w, http.StatusOK, success(data, errs, count), nil)
}

// success is the envelope of a served check.
func success(data json.RawMessage, errs []detail, count int64) envelope {
	return envelope{
		Code:                200,
		Message:             "OK",
		Errors:              errs,
		Data:                data,
		TimeTaken:           2 + rand.IntN(40),
		NonprofitCheckCount: count,
	}
}

func (s *Server) failure(code int, message string, details ...detail) envelope {
	s.mu.Lock()
	count := s.checksUsed
	s.mu.Unlock()

	return s.failureWithCount(code, message, count, details...)
}

func (s *Server) failureWithCount(code int, message string, count int64, details ...detail) envelope {
	return envelope{Code: code, Message: message, Errors: details, TimeTaken: 1, NonprofitCheckCount: count}
}

func send[T envelope | bare](w http.ResponseWriter, status int, body T, headers map[string]string) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Request-Id", "mock-"+strconv.FormatUint(rand.Uint64()%(1<<40), 36))

	for name, value := range headers {
		w.Header().Set(name, value)
	}

	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
