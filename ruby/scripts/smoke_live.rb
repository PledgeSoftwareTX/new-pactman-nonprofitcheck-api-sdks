#!/usr/bin/env ruby
# frozen_string_literal: true

# Contract smoke test against a live Nonprofit Check Plus deployment.
#
# The mock server in `mock_server.rb` proves the SDK behaves against a stub the
# SDK's own authors wrote. This proves it behaves against the real thing.
#
# Coverage tracks the documented examples: every claim `examples/ex_01` through
# `examples/ex_30` makes about the live API has a check here. Most of them cost
# nothing — a claim about the shape of a record is answered by a record already
# fetched, and a claim about local validation is answered without sending
# anything. Only a handful of checks need their own round trip.
#
# The report is grouped the same way: one heading per example file, and under it
# the checks that stand behind what that file claims. Checks run in dependency
# order rather than example order — a record has to be fetched before anything
# can be asserted about it, and the log of what went on the wire is only complete
# at the end — so nothing prints until the run is over. The ticker is what says
# it is alive in the meantime.
#
# IT SPENDS REAL QUOTA. Every billable check is charged against the account
# behind the key. There is nothing to opt into: one command runs the whole plan,
# the disruptive probes included, and what it will cost is printed as it starts.
#
# Usage
#   bundle exec ruby scripts/smoke_live.rb <ein> <bulk-eins> <missing-ein>
#
# The subjects are given on the command line, or in the environment beside the
# key; `--help` prints the whole interface. The key is read from PACTMAN_API_KEY,
# in the environment or in `ruby/.env`; PACTMAN_BASE_URL aims the run at a
# deployment other than production, which is how it is run against the mock.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "pp"
require "stringio"
require "timeout"
require "yaml"

require "pactman/nonprofit_check_plus"
require_relative "contract"
require_relative "env"
require_relative "fixtures"

NCP = Pactman::NonprofitCheckPlus

module SmokeLive
  ROOT = File.expand_path("..", __dir__)
  EXAMPLES_DIR = File.join(ROOT, "examples")
  CONTRACT_PATH = File.join(ROOT, "lib/pactman/nonprofit_check_plus/response_contract.json")
  BASELINE_PATH = File.join(ROOT, "lib/pactman/nonprofit_check_plus/response_baseline.json")

  Subject = Data.define(:name, :variable, :purpose, :list)

  # The organizations this harness checks.
  #
  # A primary subject with a record, a batch to give the bulk, order and
  # duplicate probes something to work with, and a well-formed EIN with no record
  # for the not-found and partial-success paths.
  #
  # None of them are written down here. A key carries its own allowlist, so which
  # organizations are reachable is a property of whoever is running this, and a
  # default would only mean spending their quota on an EIN their key may not even
  # reach — reported as the deployment's failure rather than the wrong subject.
  SUBJECTS = [
    Subject.new("ein", "PACTMAN_SMOKE_EIN", "the single check, and every check that reads the record it returns", nil),
    Subject.new("bulk-eins", "PACTMAN_SMOKE_BULK_EIN",
                "comma-separated, two or more, for the batch, order and duplicate probes",
                # The bulk probes read the first few; the rest would cost quota unspent.
                { min: 2, max: DevEnv::BULK_PROBE_LIMIT }),
    Subject.new("missing-ein", "PACTMAN_SMOKE_MISSING_EIN", "well-formed with no record, for the not-found paths", nil)
  ].freeze

  USAGE = [
    "Usage: bundle exec ruby scripts/smoke_live.rb #{SUBJECTS.map { |subject| "<#{subject.name}>" }.join(" ")}",
    "",
    *SUBJECTS.map do |subject|
      "  #{subject.name.ljust(14)}#{subject.purpose}\n  #{"".ljust(14)}or #{subject.variable}"
    end,
    "",
    "The key is read from PACTMAN_API_KEY, in the environment or in ruby/.env.",
    "PACTMAN_BASE_URL aims the run at a deployment other than production."
  ].join("\n")

  # Sent where a key is meant to be rejected. Synthetic, so it cannot be valid.
  INVALID_API_KEY = "pactman-smoke-test-invalid-key"

  # Ceiling on the burst the rate-limit probe is allowed to send.
  RATE_LIMIT_ATTEMPTS = 10

  # --- secret handling --------------------------------------------------------

  module_function

  # Credentials this run holds, redacted from everything it prints.
  def secrets
    @secrets ||= []
  end

  # Replaces every known credential with a placeholder. Applied to all output.
  def redact(value)
    secrets.select { |secret| secret.to_s.length >= 4 }.reduce(value.to_s) do |text, secret|
      text.gsub(secret, "[redacted]")
    end
  end

  def say(*parts)
    puts parts.map { |part| redact(part) }.join(" ")
  end

  # Where the credential came from, named precisely enough to correct.
  def key_source(env_file)
    env_file&.names&.include?(DevEnv::API_KEY_ENV) ? "#{DevEnv::API_KEY_ENV} in #{File.basename(env_file.path)}" : DevEnv::API_KEY_ENV
  end

  Resolved = Data.define(:value, :ignored, :source)

  # The subjects for this run, normalized, with where each one came from.
  #
  # A missing or malformed EIN stops the run here rather than at the first
  # request. Every problem is reported at once, so a run is not corrected one
  # argument per attempt.
  def resolve_subjects(args, env_file)
    if args.include?("-h") || args.include?("--help")
      puts USAGE
      exit 0
    end

    if args.size > SUBJECTS.size
      warn "This takes #{SUBJECTS.size} arguments; #{args.size} were given.\n\n#{USAGE}"
      exit 2
    end

    problems = []

    resolved = SUBJECTS.each_with_index.filter_map do |subject, index|
      from_args = args[index]
      given = (from_args || ENV.fetch(subject.variable, nil))&.strip

      if given.nil? || given.empty?
        problems << "<#{subject.name}> was not given, and #{subject.variable} is not set"
        next
      end

      parts = (subject.list ? given.split(",") : [given]).map(&:strip)
      malformed = parts.reject { |part| NCP::EIN.valid?(part) }

      unless malformed.empty?
        problems << "#{malformed.map { |part| "\"#{part}\"" }.join(", ")} in <#{subject.name}> " \
                    "#{malformed.size == 1 ? "is not a well-formed EIN" : "are not well-formed EINs"}"
        next
      end

      if subject.list && parts.size < subject.list[:min]
        problems << "<#{subject.name}> holds #{parts.size} EIN; the order and duplicate probes need at least " \
                    "#{subject.list[:min]}"
        next
      end

      # Normalized here so every check downstream compares canonical forms; the
      # ones that prove normalization works build their own hyphenated input.
      eins = parts.map { |part| NCP::EIN.normalize(part) }
      source = if from_args then "the command line"
               elsif env_file&.names&.include?(subject.variable) then File.basename(env_file.path)
               else "the environment"
               end

      Resolved.new(value: subject.list ? eins.first(subject.list[:max]) : eins.first,
                   ignored: subject.list ? eins.drop(subject.list[:max]) : [], source: source)
    end

    unless problems.empty?
      warn "#{problems.join("\n")}\n\n#{USAGE}"
      exit 2
    end

    resolved
  end

  # --- the examples this harness answers for ----------------------------------

  Example = Data.define(:id, :title, :file)

  # The checks that are not answering for an example file. They hold the live
  # shape against `response_contract.json`, what this gem promises, and against
  # `response_baseline.json`, what production returned when it was recorded.
  CONTRACT_GROUP = Example.new(id: "contract", title: "the live response against the contract and the recording",
                               file: nil)

  NUMBERED = /\Aex_\d{2}_/

  # Reading order for the unnumbered originals; anything else follows, by name.
  ORIGINALS = %w[quickstart.rb bulk.rb error_handling.rb].freeze

  # The title a file gives itself: its `EX-NN —` line, or its opening sentence.
  def title_of(path, fallback)
    header = File.read(path, 600).force_encoding(Encoding::UTF_8).scrub.sub(/\A# frozen_string_literal: true\s*/, "")
    titled = header.match(/EX-\d{2}\s+—\s+([^\n]+?)\.?\s*$/) || header.match(/^#\s+(\S[^\n]*?)\.?\s*$/)

    titled ? titled[1] : fallback
  rescue SystemCallError
    fallback
  end

  # Every example in `examples/`, in reading order, with the title it gives itself.
  #
  # Read from disk rather than listed here, so an example added tomorrow appears
  # in the report on its own — with no check under it, which is the state worth
  # seeing. Ids are the ones every SDK's harness uses (`ex-01`, `error-handling`),
  # so a check's `covers` reads the same in all of them.
  def discover_examples
    files = Dir.children(EXAMPLES_DIR).select { |name| name.end_with?(".rb") }.sort
    numbered, originals = files.partition { |name| NUMBERED.match?(name) }

    originals.sort_by! { |name| [ORIGINALS.index(name) || ORIGINALS.size, name] }

    (originals + numbered).map do |file|
      stem = File.basename(file, ".rb")
      id = NUMBERED.match?(file) ? stem[0, 5].tr("_", "-") : stem.tr("_", "-")
      slug = NUMBERED.match?(file) ? stem[6..].tr("_", " ") : stem.tr("_", " ")

      Example.new(id: id, title: title_of(File.join(EXAMPLES_DIR, file), slug), file: file)
    end
  rescue SystemCallError
    []
  end

  Group = Struct.new(:id, :title, :primary, :secondary)

  # The headings, in reading order, with every check filed under the examples it
  # covers.
  #
  # A check is listed in full under the first example it covers and cross-
  # referenced under the rest: it ran once, so it is counted once, but an example
  # whose claim is proven by a check that lives elsewhere still says so under its
  # own heading rather than looking untested.
  def group_by_example(examples, entries)
    groups = (examples + [CONTRACT_GROUP]).to_h { |example| [example.id, Group.new(example.id, example.title, [], [])] }

    entries.each do |entry|
      primary, *rest = entry[:covers]

      # A check naming something the examples directory does not have gets a
      # heading anyway; a result must never fall out of the report.
      (groups[primary] ||= Group.new(primary, "no example file of this name", [], [])).primary << entry

      rest.each do |id|
        (groups[id] ||= Group.new(id, "no example file of this name", [], [])).secondary << [entry, primary]
      end
    end

    groups.values
  end

  # --- the runner -------------------------------------------------------------

  # ANSI colour, when there is someone there to see it.
  #
  # Off when stdout is not a terminal, when NO_COLOR is set (no-color.org) or
  # when TERM says dumb. FORCE_COLOR overrides all of that, for a CI log that is
  # rendered with colour even though nothing it is written to is a terminal.
  COLOR = if ENV["NO_COLOR"] && !ENV["NO_COLOR"].empty? then false
          elsif ENV["FORCE_COLOR"] && !ENV["FORCE_COLOR"].empty? then true
          else $stdout.tty? && ENV["TERM"] != "dumb"
          end

  CODES = { red: 31, green: 32, yellow: 33, dim: 2 }.freeze
  STATUS = { pass: "✓", fail: "✗", warn: "!", skip: "–" }.freeze

  # A pass gets a green mark and plain text — a report that is mostly passes
  # should read as text, not as a wall of green — while a failure is red for its
  # whole line, because the message is the part worth finding.
  STATUS_COLOR = { pass: nil, fail: :red, warn: :yellow, skip: :dim }.freeze

  def paint(colour, text)
    COLOR && colour ? "\e[#{CODES.fetch(colour)}m#{text}\e[0m" : text
  end

  def mark(status)
    paint(status == :pass ? :green : STATUS_COLOR.fetch(status), STATUS.fetch(status))
  end

  def tint(status, text)
    paint(STATUS_COLOR.fetch(status), text)
  end

  Check = Data.define(:covers, :name, :cost, :body)

  # Raised by a check to fail it with a message.
  class AssertionFailed < StandardError; end

  # Marker proving a call reached the transport instead of failing validation.
  class ReachedTransport < StandardError; end

  # A caller's own interrupt, outside StandardError as a real one would be.
  class CallerCancelled < Exception; end # rubocop:disable Lint/InheritException

  class Runner
    attr_accessor :client, :single_result, :bulk_result, :observed_round_trip, :free_tier_key
    attr_reader :results, :findings, :requests, :requests_sent, :checks_spent, :cycle_count_start, :cycle_count_end

    def initialize(api_key)
      # A predicate rather than the key itself, so nothing that walks this object
      # — the client's adapter holds it — can reach the credential.
      @carries_key = ->(text) { text.to_s.include?(api_key) }
      @results = []
      @findings = []
      @checks_spent = 0
      @requests_sent = 0
      @cycle_count_start = nil
      @cycle_count_end = nil
      # True once a bulk request has been refused for containing an EIN outside
      # the key's allowlist. Declared here so a check that finds no bulk
      # response can say why there is none.
      @free_tier_key = false
      # One entry per outbound request, with the credential reduced to a flag.
      @requests = []
    end

    def inspect
      "#<SmokeLive::Runner>"
    end

    # Records an observation that is informative but not a pass/fail.
    def note(check, message)
      @findings << { check: check, message: message }
    end

    # Captures what went on the wire. The Authorization value is reduced to a
    # boolean here rather than stored, so no code path downstream can print it.
    def record_request(request)
      @requests_sent += 1
      authorization = request.headers["authorization"].to_s

      @requests << {
        method: request.http_method.to_s.upcase,
        url: request.url,
        url_carries_key: @carries_key.call(request.url),
        auth_carries_key: @carries_key.call(authorization),
        auth_scheme: authorization.split.first.to_s,
        accept: request.headers["accept"],
        content_type: request.headers["content-type"],
        user_agent: request.headers["user-agent"],
        body: request.body
      }
    end

    def run(check)
      started_at = SmokeLive.monotonic_ms

      begin
        outcome = check.body.call(self) || {}

        @checks_spent += check.cost
        @results << { covers: check.covers, name: check.name, status: outcome.fetch(:status, :pass),
                      detail: outcome.fetch(:detail, ""), data: outcome[:data], cost: check.cost,
                      duration_ms: SmokeLive.monotonic_ms - started_at }
      rescue StandardError, ScriptError => e
        # A failed check may still have been billed, so the cost stands.
        @checks_spent += check.cost
        @results << { covers: check.covers, name: check.name, status: :fail, detail: SmokeLive.redact(e.message),
                      error_class: e.class.name, cost: check.cost, duration_ms: SmokeLive.monotonic_ms - started_at }
      end
    end

    # Keeps the first successful bulk response for the checks that read one.
    #
    # `bulk with a miss` is the better subject — its envelope is the only one
    # carrying the item-level errors a batch with a miss returns — but it is
    # unreachable on a key whose bulk EINs are allowlisted, so the duplicate
    # probe's response stands in when it has to.
    def capture_bulk(result)
      self.bulk_result = result if bulk_result.nil?
    end

    # Tracks the cumulative counter across the whole run.
    def observe_cycle_count(value)
      return unless value.is_a?(Numeric)

      @cycle_count_start ||= value
      @cycle_count_end = value
    end
  end

  # Sends through the default adapter and writes down what it sent.
  class RecordingAdapter
    def initialize(runner)
      @runner = runner
      @inner = NCP::Http::NetHttpAdapter.new
    end

    def call(request)
      @runner.record_request(request)
      @inner.call(request)
    end
  end

  def assert(condition, message)
    raise AssertionFailed, message unless condition
  end

  def monotonic_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
  end

  # True when a 404 came from the free-tier EIN allowlist rather than from an
  # absent record.
  #
  # A free key carries a fixed set of accessible EINs. The server requires every
  # EIN in a bulk body to be on that list and answers 404 for the whole batch
  # otherwise, before any lookup runs — so partial success cannot be reached with
  # such a key. That is a property of the key, not of the deployment.
  def free_tier_restriction?(error)
    error.is_a?(NCP::NotFoundError) && error.api_errors.any? { |detail| detail.reason.to_s.match?(/accessible nonprofits/i) }
  end

  # --- small helpers ----------------------------------------------------------

  # `present` | `null` | `absent` — the three outcomes ex-05 turns on.
  def presence(nonprofit, field)
    return "absent" unless nonprofit.key?(field)

    nonprofit[field].nil? ? "null" : "present"
  end

  def parse_api_date(value)
    return nil unless value.is_a?(String) && !value.strip.empty?

    text = value.tr("  ", "  ").delete(",")

    begin
      Time.strptime(text, "%m/%d/%Y %I:%M:%S %p")
    rescue ArgumentError
      begin
        Time.iso8601(text)
      rescue ArgumentError
        nil
      end
    end
  end

  def age_in_days(time, now = Time.now)
    ((now - time) / 86_400).round
  end

  def truncate(value, length = 60)
    text = value.to_s
    text.length <= length ? text : "#{text[0, length - 1]}…"
  end

  def json_type(value)
    Contract.token_for(value).then { |token| Contract.string_token?(token) ? "string" : token }
  end

  def reached_transport?(error)
    error.is_a?(NCP::NetworkError) && error.cause.is_a?(ReachedTransport)
  end

  # --- check builders ---------------------------------------------------------

  # A zero-cost check over the record the single check already fetched.
  #
  # This is what keeps coverage affordable: most of what the examples claim is a
  # claim about a response, and one response answers all of them.
  def from_record(covers, name, &body)
    Check.new(covers: covers, name: name, cost: 0, body: lambda do |runner|
      nonprofit = runner.single_result&.nonprofit
      next { status: :fail, detail: "the single check returned no record" } if nonprofit.nil?

      body.call(nonprofit, runner)
    end)
  end

  # Checks that a grouped source view is a projection and nothing more: every
  # attribute copied 1:1 from the field the API returned, nothing invented, and
  # `nil` returned only when the source is genuinely absent.
  def source_projection(covers:, name:, get:, mapping:, describe:, absent_status: :warn)
    from_record(covers, name) do |nonprofit, runner|
      projected = get.call(nonprofit)
      wire_fields = mapping.values.select { |field| nonprofit.key?(field) }

      if projected.nil?
        assert(wire_fields.empty?, "the projection was nil while the API returned #{wire_fields.size} of its fields")
        runner.note(name, "the API returned nothing for this source — an absence, not a negative")

        next { status: absent_status, detail: "not returned for this record" }
      end

      mapping.each do |target, wire_field|
        on_wire = nonprofit.key?(wire_field)

        assert(on_wire == projected.key?(target),
               "\"#{target}\" and the wire field \"#{wire_field}\" disagree about presence")
        if on_wire
          assert(projected[target].equal?(nonprofit[wire_field]),
                 "\"#{target}\" is not the value the API returned in \"#{wire_field}\"")
        end
      end

      invented = projected.keys - mapping.keys
      assert(invented.empty?, "the projection added fields the API did not send: #{invented.join(", ")}")

      { detail: "#{wire_fields.size}/#{mapping.size} fields returned · #{describe.call(projected)}",
        data: projected.to_h }
    end
  end

  # Every public method name reachable from the gem's namespace: module
  # functions, class methods, and instance methods, walked constant by constant.
  def public_method_names(namespace = NCP, seen = [])
    return [] if seen.include?(namespace)

    seen << namespace
    names = namespace.singleton_methods

    names.concat(namespace.public_instance_methods(false)) if namespace.is_a?(Class)

    namespace.constants.each do |constant|
      value = namespace.const_get(constant)
      names.concat(public_method_names(value, seen)) if value.is_a?(Module) && value.name.to_s.start_with?(NCP.name)
    end

    names
  end

  # --- checks: the client itself (ex-01) --------------------------------------

  def client_checks(api_key)
    [
      Check.new(covers: ["ex-01"], name: "configuration and redaction", cost: 0, body: lambda do |runner|
        client = runner.client

        assert(client.base_url.is_a?(String), "client.base_url is not a String")
        assert(client.timeout.positive? && client.timeout.finite?, "the timeout is not finite")

        printed = StringIO.new
        PP.pp(client, printed)

        # The credential must not be reachable from any diagnostic surface.
        [client.inspect, printed.string, client.to_json, client.to_s, client.to_yaml].each do |surface|
          assert(!surface.include?(api_key), "the API key appeared in a diagnostic surface")
        end

        assert(JSON.parse(client.to_json)["api_key"] == "[redacted]", "to_json did not replace the key with a placeholder")

        { detail: "#{client.base_url} · timeout #{client.timeout}s · SDK #{NCP::VERSION}" }
      end),

      Check.new(covers: ["ex-01"], name: "configuration is validated", cost: 0, body: lambda do |_runner|
        rejected = {
          "no options" => -> { NCP::Client.new },
          "a missing key" => -> { NCP::Client.new(api_key: nil) },
          "a blank key" => -> { NCP::Client.new(api_key: "   ") },
          "a non-String key" => -> { NCP::Client.new(api_key: 1234) },
          "a malformed base URL" => -> { NCP::Client.new(api_key: api_key, base_url: "not a url") },
          "a non-HTTP base URL" => -> { NCP::Client.new(api_key: api_key, base_url: "ftp://example.org") },
          "a zero timeout" => -> { NCP::Client.new(api_key: api_key, timeout: 0) },
          "an infinite timeout" => -> { NCP::Client.new(api_key: api_key, timeout: Float::INFINITY) },
          "a negative retry count" => -> { NCP::Client.new(api_key: api_key, retry: { max_retries: -1 }) },
          "an unknown environment" => -> { NCP::Client.new(api_key: api_key, environment: :staging) }
        }

        rejected.each do |description, construct|
          begin
            construct.call
          rescue NCP::ConfigurationError
            next
          rescue StandardError => e
            raise AssertionFailed, "#{description}: expected ConfigurationError, got #{e.class}"
          end

          raise AssertionFailed, "#{description} was accepted"
        end

        # An option the client does not have is a call-shape mistake, and raises
        # the error Ruby itself raises for one.
        begin
          NCP::Client.new(api_key: api_key, timeout_ms: 5_000)
          raise AssertionFailed, "an unknown option was accepted"
        rescue ArgumentError
          nil
        end

        # Defaults, which no example spells out because every example relies on them.
        defaults = NCP::Client.new(api_key: api_key)

        assert(defaults.timeout == NCP::DEFAULT_TIMEOUT, "the default timeout is not DEFAULT_TIMEOUT")
        assert(defaults.base_url == NCP.base_url_for_environment(NCP::DEFAULT_ENVIRONMENT),
               "the default base URL is not the default environment")
        assert(defaults.environment == NCP::DEFAULT_ENVIRONMENT, "the default environment was not reported")
        assert(NCP::Client.new(api_key: api_key, base_url: "https://example.org").environment.nil?,
               "an explicit base_url should report no named environment")

        { detail: "#{rejected.size} unusable configurations rejected locally · unknown options raise ArgumentError · " \
                  "defaults: #{NCP::DEFAULT_TIMEOUT}s, #{NCP.supported_environments.join(", ")}" }
      end),

      # The batch limit and the endpoint paths are constants ex-20 tells callers
      # to reference rather than copy, so its heading names this check too.
      Check.new(covers: %w[ex-01 ex-20], name: "exported surface", cost: 0, body: lambda do |_runner|
        expected = {
          Class => %w[Client NonprofitsResource Error ApiError AuthenticationError AuthorizationError BadRequestError
                      ConfigurationError NetworkError NotFoundError RateLimitError ServerError TimeoutError
                      ValidationError ValidationIssue Nonprofit OrganizationType ApiErrorDetail Pub78Source BmfSource
                      AroeSource OfacSource RetryPolicy SingleCheckResult BulkCheckResult Http::NetHttpAdapter],
          Module => %w[EIN Sources Environment ErrorCategory ErrorOrigin Http],
          String => %w[VERSION GEM_NAME SINGLE_CHECK_PATH BULK_CHECK_PATH],
          Integer => %w[DEFAULT_TIMEOUT MAX_BULK_EINS EIN::LENGTH],
          Symbol => %w[DEFAULT_ENVIRONMENT]
        }

        wrong = expected.flat_map do |kind, names|
          names.filter_map do |name|
            value = NCP.const_defined?(name) ? NCP.const_get(name) : nil
            "#{name} (expected #{kind}, got #{value.nil? ? "nothing" : value.class})" unless value.is_a?(kind)
          end
        end

        functions = { NCP => %i[base_url_for_environment supported_environments],
                      NCP::EIN => %i[normalize normalize_all valid?],
                      NCP::Sources => %i[pub78 bmf aroe ofac] }

        functions.each do |owner, names|
          names.each { |name| wrong << "#{owner}.#{name}" unless owner.respond_to?(name) }
        end

        assert(wrong.empty?, "missing or mistyped exports: #{wrong.join(", ")}")

        # The server's limits belong to the server; ex-20 asks callers to reference
        # them rather than copy the numbers into their own constants.
        assert(NCP::MAX_BULK_EINS.positive?, "MAX_BULK_EINS is not a positive integer")
        assert(NCP::EIN::LENGTH == 9, "EIN::LENGTH is #{NCP::EIN::LENGTH}")
        assert(NCP::VERSION.match?(/\A\d+\.\d+\.\d+/), "VERSION \"#{NCP::VERSION}\" is not semver-shaped")
        assert(NCP::SINGLE_CHECK_PATH.include?("{ein}"), "SINGLE_CHECK_PATH has no {ein} placeholder")

        count = expected.values.sum(&:size) + functions.values.sum(&:size)

        { detail: "#{count} documented constants and functions present · MAX_BULK_EINS #{NCP::MAX_BULK_EINS}" }
      end),

      # ex-22 and ex-24 name the classes their probes raise; this is the part of
      # what they claim that costs nothing and runs on every key.
      Check.new(covers: %w[ex-16 error-handling ex-22 ex-24], name: "error taxonomy", cost: 0, body: lambda do |_runner|
        cases = [
          [NCP::BadRequestError.new("x", status: 0), NCP::ErrorCategory::BAD_REQUEST, :api],
          [NCP::AuthenticationError.new("x", status: 0), NCP::ErrorCategory::AUTHENTICATION, :api],
          [NCP::AuthorizationError.new("x", status: 0), NCP::ErrorCategory::AUTHORIZATION, :api],
          [NCP::NotFoundError.new("x", status: 0), NCP::ErrorCategory::NOT_FOUND, :api],
          [NCP::RateLimitError.new("x", status: 0), NCP::ErrorCategory::RATE_LIMIT, :api],
          [NCP::ServerError.new("x", status: 0), NCP::ErrorCategory::SERVER, :api],
          [NCP::ValidationError.new("x"), NCP::ErrorCategory::VALIDATION, :local],
          [NCP::ConfigurationError.new("x"), NCP::ErrorCategory::CONFIGURATION, :local],
          [NCP::TimeoutError.new("x", timeout: 1), NCP::ErrorCategory::TIMEOUT, :local],
          [NCP::NetworkError.new("x"), NCP::ErrorCategory::NETWORK, :local]
        ]

        cases.each do |error, category, origin|
          assert(error.is_a?(NCP::Error), "#{error.class} is not an NCP::Error")
          assert(error.is_a?(StandardError), "#{error.class} is not a StandardError")
          assert(error.category == category, "#{error.class} has category #{error.category.inspect}")
          assert(error.origin == origin, "#{error.class} has origin #{error.origin.inspect}")
          assert(error.to_h[:name] == error.class.name, "#{error.class} reports name #{error.to_h[:name].inspect}")
        end

        # Every API error is rescuable as one class; the specific ones stay specific.
        cases.first(6).each { |error,| assert(error.is_a?(NCP::ApiError), "#{error.class} is not an ApiError") }

        assert(!RuntimeError.new("x").is_a?(NCP::Error), "a plain RuntimeError is an NCP::Error")
        assert(NCP::ErrorOrigin::LOCAL == :local && NCP::ErrorOrigin::API == :api,
               "the origin constants are not the documented symbols")

        { detail: "#{cases.size} error classes · category and origin as documented" }
      end),

      # Every one of these examples says in prose that the helper it would have
      # been convenient to call does not exist.
      Check.new(covers: %w[ex-04 ex-06 ex-10 ex-14], name: "no derived verdicts", cost: 0, body: lambda do |_runner|
        # The SDK reports what the sources said and stops. Every example says so
        # in prose; this is the executable version.
        forbidden = %i[
          names_match names_match? addresses_match addresses_match? exempt? eligible? grant_eligible? deductible?
          revoked? reinstated? sanctioned? stale? ofac_match? match? conflict? score verdict decide approve approved?
          safe?
        ]

        found = public_method_names.uniq & forbidden

        assert(found.empty?, "the SDK exposes derived verdicts: #{found.join(", ")}")

        { detail: "none of #{forbidden.size} verdict helpers exist — policy stays in caller code" }
      end)
    ]
  end

  # --- checks: local validation (ex-02, ex-15, ex-20) -------------------------

  def local_validation_checks(ein, bulk_eins, api_key)
    [
      Check.new(covers: %w[ex-15 error-handling], name: "malformed input sends nothing", cost: 0, body: lambda do |runner|
        before = runner.requests_sent
        normalized = NCP::EIN.normalize(ein)

        # Each one is the subject with a single thing wrong with it, so what is
        # being rejected is that flaw and not some other property of the input.
        malformed = [normalized[0, NCP::EIN::LENGTH - 1], "not-an-ein", "", nil, "#{normalized[0, 2]}.#{normalized[2..]}",
                     Integer(normalized, 10)]
        batches = { "an empty batch" => [], "a non-Array batch" => "not-an-array", "a batch with one bad entry" => [ein, "nope"] }

        malformed.each do |bad|
          begin
            runner.client.nonprofits.check(bad)
          rescue NCP::ValidationError => e
            assert(e.origin == :local, "a local rejection reported origin #{e.origin.inspect}")
            next
          rescue StandardError => e
            raise AssertionFailed, "expected ValidationError for #{bad.inspect}, got #{e.class}"
          end

          raise AssertionFailed, "#{bad.inspect} was accepted by local validation"
        end

        batches.each do |description, input|
          begin
            runner.client.nonprofits.check_bulk(input)
          rescue NCP::ValidationError
            next
          end

          raise AssertionFailed, "#{description} was accepted"
        end

        sent = runner.requests_sent - before
        assert(sent.zero?, "#{sent} HTTP requests were sent for input that should never leave the process")

        { detail: "#{malformed.size + batches.size} malformed inputs rejected in-process with 0 requests" }
      end),

      Check.new(covers: %w[ex-02 ex-15 ex-18], name: "EIN helpers", cost: 0, body: lambda do |_runner|
        normalized = NCP::EIN.normalize(ein)
        hyphenated = "#{normalized[0, 2]}-#{normalized[2..]}"

        assert(normalized.match?(/\A\d{9}\z/), "EIN.normalize produced #{normalized.inspect}")
        assert(NCP::EIN.normalize("  #{hyphenated}  ") == normalized,
               "the hyphenated and padded form did not normalize to the plain one")
        assert(NCP::EIN.valid?(normalized) && NCP::EIN.valid?(hyphenated), "EIN.valid? rejected a well-formed EIN")
        assert(!NCP::EIN.valid?(normalized[0, NCP::EIN::LENGTH - 1]) && !NCP::EIN.valid?(nil) &&
               !NCP::EIN.valid?(Integer(normalized, 10)), "EIN.valid? accepted a malformed value")

        # Order and duplicates survive normalization; ex-18 depends on it. The
        # second subject is here only as an EIN that is not the first one.
        other = bulk_eins[1]

        assert(NCP::EIN.normalize_all([hyphenated, other, hyphenated]) == [normalized, other, normalized],
               "EIN.normalize_all reordered or deduplicated its input")

        # Every failure is reported at once, by index, rather than the first one.
        begin
          NCP::EIN.normalize_all([hyphenated, "nope", "", other])
          raise AssertionFailed, "EIN.normalize_all accepted two malformed entries"
        rescue NCP::ValidationError => e
          assert(e.issues.size == 2, "expected 2 issues, got #{e.issues.size}")
          assert(e.issues.map(&:index) == [1, 2], "the issues did not identify the failing positions")
        end

        { detail: "#{NCP::EIN::LENGTH}-digit normalization · order and duplicates preserved · issues by index" }
      end),

      Check.new(covers: %w[ex-20 bulk], name: "bulk batch limit is local", cost: 0, body: lambda do |runner|
        # An adapter that refuses to send. Reaching it proves local validation
        # passed; never reaching it proves the batch was rejected in-process.
        probe = NCP::Client.new(api_key: api_key, base_url: runner.client.base_url, retry: false,
                                http_adapter: lambda { |_request|
                                  raise ReachedTransport, "the request reached the transport"
                                })

        # Filler, counted rather than looked up: this probe never sends, so these
        # only have to be well-formed, and no organization needs to exist.
        filler = ->(index) { ((10**(NCP::EIN::LENGTH - 1)) + index).to_s }
        at_limit = Array.new(NCP::MAX_BULK_EINS) { |index| filler.call(index) }
        over_limit = at_limit + [filler.call(NCP::MAX_BULK_EINS)]

        reached = begin
          probe.nonprofits.check_bulk(at_limit)
          false
        rescue NCP::Error => e
          reached_transport?(e)
        end

        assert(reached, "a batch of exactly #{NCP::MAX_BULK_EINS} was rejected locally")

        before = runner.requests_sent

        begin
          probe.nonprofits.check_bulk(over_limit)
          raise AssertionFailed, "a batch of #{over_limit.size} was accepted"
        rescue NCP::ValidationError => e
          assert(e.message.include?(NCP::MAX_BULK_EINS.to_s), "the rejection did not name the limit that was exceeded")
        rescue NCP::Error => e
          raise AssertionFailed, "an over-limit batch raised #{e.class}"
        end

        # `dedupe:` collapses before the limit applies, so a duplicate-heavy list
        # that exceeds the limit as supplied still goes out.
        duplicate_heavy = Array.new(NCP::MAX_BULK_EINS + 10) { |index| filler.call(index % 10) }

        deduped_reached = begin
          probe.nonprofits.check_bulk(duplicate_heavy, dedupe: true)
          false
        rescue NCP::Error => e
          reached_transport?(e)
        end

        assert(deduped_reached, "dedupe did not collapse duplicates before the limit was applied")
        assert(runner.requests_sent == before, "the over-limit batch was sent through the real transport")

        { detail: "#{NCP::MAX_BULK_EINS} accepted · #{over_limit.size} rejected in-process · dedupe collapses first" }
      end)
    ]
  end

  # --- checks: authentication (ex-01, ex-23) ----------------------------------

  # Counts what it sends, so a retry is visible at the socket.
  class CountingAdapter
    attr_reader :sent

    def initialize
      @inner = NCP::Http::NetHttpAdapter.new
      @sent = 0
    end

    def call(request)
      @sent += 1
      @inner.call(request)
    end
  end

  def authentication_checks(ein, base_url)
    rejected_client = lambda do |retry_option|
      counter = CountingAdapter.new
      [NCP::Client.new(api_key: INVALID_API_KEY, base_url: base_url, retry: retry_option, timeout: 15,
                       http_adapter: counter), counter]
    end

    [
      Check.new(covers: %w[ex-01 error-handling], name: "authentication is enforced", cost: 0, body: lambda do |runner|
        client, = rejected_client.call(false)

        begin
          client.nonprofits.check(ein)
          next { status: :fail, detail: "an invalid key was accepted — check what INVALID_API_KEY was set to" }
        rescue NCP::AuthenticationError => e
          assert(e.origin == :api, "expected origin :api, got #{e.origin.inspect}")
          assert(!(e.to_json + e.full_message).include?(INVALID_API_KEY), "the rejected key appeared in error diagnostics")

          next { detail: "HTTP #{e.status} → AuthenticationError" }
        rescue NCP::ApiError => e
          runner.note("authentication is enforced", "an invalid key produced HTTP #{e.status} (#{e.class}), not 401")

          next { status: :warn, detail: "rejected, but as HTTP #{e.status} rather than 401" }
        end
      end),

      Check.new(covers: ["ex-23"], name: "rejected keys are not retried", cost: 0, body: lambda do |runner|
        # Retrying a rejected key just burns the same key three times. The policy
        # says 401/403/404 are never retried whatever `retryable_statuses` holds;
        # this is the live proof, counted at the socket.
        client, counter = rejected_client.call({ max_retries: 2, initial_delay: 0.01,
                                                 retryable_statuses: [401, 403, 404, 429, 500] })
        status = nil

        begin
          client.nonprofits.check(ein)
        rescue NCP::ApiError => e
          status = e.status
          assert(e.attempts == 1, "the error reports #{e.attempts} attempts")
        rescue NCP::Error
          nil
        end

        if status && ![401, 403, 404].include?(status)
          runner.note("rejected keys are not retried",
                      "the invalid key produced HTTP #{status}, which is retryable — the no-retry rule was not exercised")

          next { status: :warn, detail: "HTTP #{status} after #{counter.sent} request(s)" }
        end

        assert(counter.sent == 1,
               "a rejected key was sent #{counter.sent} times with retries on and 401 in retryable_statuses")

        { detail: "HTTP #{status || "none"} · 1 request, no retry, even when listed as retryable" }
      end)
    ]
  end

  # --- checks: the single check and its record (ex-02..ex-05, ex-16) ----------

  def single_check_checks(ein, missing_ein, api_key)
    [
      # The one fetch every record-derived check below reads.
      Check.new(covers: %w[ex-03 quickstart ex-26 ex-27], name: "single check", cost: 1, body: lambda do |runner|
        sent_at = monotonic_ms
        result = runner.client.nonprofits.check(ein)

        # Recorded so the timeout probe can pick a deadline that is shorter than a
        # real round trip but longer than connection setup.
        runner.observed_round_trip = (monotonic_ms - sent_at) / 1000.0
        runner.observe_cycle_count(result.check_count)

        assert(result.status == 200, "expected HTTP 200, got #{result.status}")
        assert(!result.nonprofit.nil?, "no record returned for #{ein} — the subject needs one that exists")
        assert(result.nonprofit.ein == NCP::EIN.normalize(ein),
               "response EIN #{result.nonprofit.ein} does not match the normalized request #{NCP::EIN.normalize(ein)}")

        runner.single_result = result

        { detail: "#{result.nonprofit.organization_name} · request #{result.request_id || "no id"}",
          data: { check_count: result.check_count, time_taken_ms: result.time_taken_ms } }
      end),

      Check.new(covers: ["ex-03"], name: "envelope shape", cost: 0, body: lambda do |runner|
        result = runner.single_result
        next { status: :fail, detail: "the single check did not return a record" } if result.nil?

        raw = result.raw
        assert(raw.is_a?(Hash), "the response body was not a JSON object")

        %w[code message data].each { |key| assert(raw.key?(key), "the envelope is missing \"#{key}\"") }

        assert(raw["code"].is_a?(Numeric), "envelope \"code\" is #{json_type(raw["code"])}")
        assert(result.errors.is_a?(Array), "result.errors was not normalized to an Array")
        assert(result.check_count.nil? || result.check_count.is_a?(Numeric), "check_count is neither Numeric nor nil")
        assert(result.time_taken_ms.nil? || result.time_taken_ms.is_a?(Numeric), "time_taken_ms is neither Numeric nor nil")
        assert(result.request_id.nil? || result.request_id.is_a?(String), "request_id is neither a String nor nil")

        missing = %w[timeTaken nonprofit_check_count].reject { |key| raw.key?(key) }
        runner.note("envelope shape", "envelope did not include: #{missing.join(", ")}") unless missing.empty?

        # A numeric field that arrives as something else reads as nil, which looks
        # exactly like "not reported" downstream. Say so rather than let the usage
        # checks skip themselves for a reason nobody sees.
        mistyped = [["nonprofit_check_count", raw["nonprofit_check_count"], result.check_count],
                    ["timeTaken", raw["timeTaken"],
                     result.time_taken_ms]].select { |_key, wire, parsed| !wire.nil? && parsed.nil? }

        mistyped.each do |key, wire|
          runner.note("envelope shape",
                      "\"#{key}\" arrived as #{json_type(wire)} (#{JSON.generate(wire)}), not a number — it is reported as nil")
        end

        runner.note("envelope shape", "no correlation header was returned — audit trails lose the request id") if result.request_id.nil?

        { status: missing.empty? && mistyped.empty? ? :pass : :warn,
          detail: "#{raw.size} envelope keys · code #{raw["code"]} · #{result.time_taken_ms || "?"}ms server-side" +
            (mistyped.empty? ? "" : " · #{mistyped.size} numeric field(s) mistyped"),
          data: { envelope_keys: raw.keys } }
      end),

      # The only check ex-21 claims: the counter arrives as a JSON number.
      Check.new(covers: ["ex-21"], name: "check count is a number", cost: 0, body: lambda do |runner|
        result = runner.single_result
        next { status: :fail, detail: "the single check did not return a record" } if result.nil?

        assert(result.raw.key?("nonprofit_check_count"), "the response did not carry nonprofit_check_count")

        wire = result.raw["nonprofit_check_count"]

        # `check_count` is nil both for a counter the API sent as null and for one
        # it sent as "42", so the type is only readable off the envelope.
        assert(wire.is_a?(Numeric),
               "nonprofit_check_count arrived as #{json_type(wire)} (#{JSON.generate(wire)}), not a number — it reads as nil")

        { detail: "#{wire} · a JSON number, so check_count reports it", data: { check_count: wire } }
      end),

      from_record(%w[ex-25 ex-03], "model field coverage") do |nonprofit, runner|
        # Drift detection. New fields are expected over time and are not failures;
        # they are the reason `raw` and `[]` exist.
        known = Fixtures.known_nonprofit_fields
        unknown = nonprofit.keys - known
        absent = known - nonprofit.keys

        unless unknown.empty?
          runner.note("model field coverage",
                      "fields newer than this SDK: #{unknown.join(", ")} — readable via raw and []")
        end

        runner.note("model field coverage", "documented fields not returned for this record: #{absent.join(", ")}") unless absent.empty?

        { detail: "#{nonprofit.keys.size} fields · #{unknown.size} newer than the SDK · #{absent.size} not returned",
          data: { unknown: unknown, absent: absent } }
      end,

      from_record(["ex-03"], "identity fields") do |nonprofit, runner|
        assert(nonprofit.ein.to_s.match?(/\A\d{9}\z/), "ein came back as #{nonprofit.ein.inspect}")
        assert(nonprofit.organization_name.is_a?(String) && !nonprofit.organization_name.strip.empty?,
               "organization_name is missing or empty")

        if nonprofit.pactman_org_url.is_a?(String)
          uri = begin
            URI.parse(nonprofit.pactman_org_url)
          rescue URI::InvalidURIError
            nil
          end

          runner.note("identity fields", "pactman_org_url is not a URL: #{nonprofit.pactman_org_url}") if uri.nil? || uri.host.nil?
        end

        modified = parse_api_date(nonprofit.organization_info_last_modified)

        { detail: "#{nonprofit.ein} · #{truncate(nonprofit.organization_name, 40)}" +
          (modified.nil? ? "" : " · modified #{age_in_days(modified)}d ago") }
      end,

      from_record(["ex-04"], "name fields") do |nonprofit, runner|
        names = %w[organization_name organization_name_aka pub78_organization_name bmf_organization_name]
                .to_h { |field| [field, nonprofit[field]] }

        names.each do |field, value|
          assert(value.nil? || value.is_a?(String), "#{field} came back as #{json_type(value)}")
        end

        # Each source keeps its own spelling. Differences between them are normal,
        # and reconciling them is the caller's policy (ex-04).
        spellings = names.values.select { |value| value.is_a?(String) && !value.strip.empty? }.uniq

        if spellings.size > 1
          runner.note("name fields", "the sources spell the name differently: #{spellings.map do |name|
            "\"#{name}\""
          end.join(" vs ")}")
        end

        { detail: "#{spellings.size} distinct spelling(s) preserved across #{names.size} name fields", data: names }
      end,

      from_record(["ex-05"], "address fields") do |nonprofit, runner|
        fields = %w[address_line1 address_line2 city state state_name zip]
        states = fields.to_h { |field| [field, presence(nonprofit, field)] }

        # "Returned as null" and "not returned" are different answers (ex-05). The
        # model reads the parsed body in place, so `key?` keeps them apart.
        unconfirmed = fields.reject { |field| states[field] == "present" }

        unless unconfirmed.empty?
          runner.note("address fields",
                      "no value returned for #{unconfirmed.join(", ")} — these components are unconfirmed, not mismatched")
        end

        { detail: "#{fields.size - unconfirmed.size}/#{fields.size} components returned with a value", data: states }
      end,

      Check.new(covers: ["ex-02"], name: "EIN normalization end to end", cost: 1, body: lambda do |runner|
        normalized = NCP::EIN.normalize(ein)
        hyphenated = "  #{normalized[0, 2]}-#{normalized[2..]}  "
        before = runner.requests.size
        result = runner.client.nonprofits.check(hyphenated)

        runner.observe_cycle_count(result.check_count)

        assert(!result.nonprofit.nil?, "the hyphenated form returned no record")
        assert(result.nonprofit.ein == normalized, "hyphenated input resolved to #{result.nonprofit.ein}, expected #{normalized}")

        # The hyphen and the whitespace are normalized before the URL is built.
        url = runner.requests.drop(before).last&.fetch(:url).to_s

        assert(url.end_with?("/#{normalized}"), "the request URL did not carry the normalized EIN: #{url}")
        assert(!url.include?(hyphenated.strip), "the hyphenated form reached the URL")

        { detail: "\"#{hyphenated.strip}\" and \"#{normalized}\" address the same record" }
      end),

      Check.new(covers: ["ex-16"], name: "not found", cost: 1, body: lambda do |runner|
        before = runner.requests_sent

        begin
          result = runner.client.nonprofits.check(missing_ein)
          runner.observe_cycle_count(result.check_count)

          if result.nonprofit
            next { status: :warn, detail: "#{missing_ein} unexpectedly has a record — the missing EIN needs an unused one" }
          end

          runner.note("not found", "a missing EIN returned HTTP 200 with a null record, not 404")

          next { status: :warn, detail: "HTTP #{result.status} with data: null, not a 404" }
        rescue NCP::NotFoundError => e
          assert(e.status == 404, "expected status 404, got #{e.status}")
          assert(e.origin == :api, "expected origin :api, got #{e.origin.inspect}")
          assert(e.is_a?(NCP::ApiError), "NotFoundError is not rescuable as ApiError")

          # A 404 cannot become a record by asking again (ex-23).
          assert(runner.requests_sent - before == 1, "a 404 was retried: #{runner.requests_sent - before} requests")

          # Diagnostics must be safe to log verbatim.
          assert(!(e.to_json + e.full_message + e.inspect).include?(api_key), "the API key appeared in error diagnostics")

          next { detail: "HTTP 404 → NotFoundError · api_code #{e.api_code} · #{e.api_errors.size} detail(s) · not retried" }
        rescue NCP::ApiError => e
          runner.note("not found", "a missing EIN produced HTTP #{e.status}, not 404")

          next { status: :warn, detail: "HTTP #{e.status} (#{e.class})" }
        end
      end)
    ]
  end

  # --- checks: the sources (ex-06..ex-14) -------------------------------------

  def source_checks
    [
      source_projection(
        covers: ["ex-07"], name: "Publication 78 projection", get: NCP::Sources.method(:pub78),
        mapping: { "verified" => "pub78_verified", "organization_name" => "pub78_organization_name",
                   "ein" => "pub78_ein", "city" => "pub78_city", "state" => "pub78_state",
                   "indicator" => "pub78_indicator", "church_message" => "pub78_church_message",
                   "organization_types" => "organization_types", "most_recent" => "most_recent_pub78" },
        describe: lambda do |pub78|
          types = pub78["organization_types"].is_a?(Array) ? pub78["organization_types"] : []
          limitation = types.first.is_a?(Hash) ? types.first["deductibility_limitation"] : nil

          "verified: #{pub78.key?(:verified) ? pub78.verified.inspect : "not reported"} · " \
          "#{types.size} deductibility entr#{types.size == 1 ? "y" : "ies"}" +
            (limitation ? " · #{truncate(limitation, 24)}" : "")
        end
      ),

      source_projection(
        covers: ["ex-06"], name: "BMF projection", get: NCP::Sources.method(:bmf),
        mapping: { "status" => "bmf_status", "organization_name" => "bmf_organization_name", "ein" => "bmf_ein",
                   "church_message" => "bmf_church_message", "subsection" => "bmf_subsection",
                   "subsection_description" => "subsection_description", "foundation_code" => "foundation_code",
                   "foundation_code_description" => "foundation_code_description",
                   "foundation_type_code" => "foundation_type_code",
                   "foundation_type_description" => "foundation_type_description",
                   "foundation_509a_status" => "foundation_509a_status", "ruling_month" => "ruling_month",
                   "ruling_year" => "ruling_year", "group_exemption" => "group_exemption",
                   "exempt_status_code" => "exempt_status_code", "filing_req_code" => "filing_req_code",
                   "most_recent" => "most_recent_bmf" },
        describe: lambda do |bmf|
          "status: #{bmf.key?(:status) ? bmf.status.inspect : "not reported"} · subsection #{bmf.subsection || "—"} · " \
            "#{truncate(bmf.subsection_description || "no description", 30)}"
        end
      ),

      source_projection(
        covers: %w[ex-08 ex-09], name: "revocation (AROE) projection", get: NCP::Sources.method(:aroe),
        # Most organizations were never revoked, so an absent source is the
        # ordinary case here rather than something to flag.
        absent_status: :pass,
        mapping: { "revocation_code" => "revocation_code", "revocation_date" => "revocation_date",
                   "reinstatement_date" => "reinstatement_date" },
        describe: lambda do |aroe|
          next "no revocation on this record" if aroe.revocation_date.to_s.empty? && aroe.revocation_code.to_s.empty?

          revoked = parse_api_date(aroe.revocation_date)
          reinstated = parse_api_date(aroe.reinstatement_date)
          gap = revoked && reinstated ? " · #{age_in_days(revoked, reinstated)}d gap" : ""

          "revoked #{aroe.revocation_date || "?"} (#{aroe.revocation_code || "no code"})#{gap}"
        end
      ),

      source_projection(
        covers: ["ex-10"], name: "OFAC projection", get: NCP::Sources.method(:ofac),
        mapping: { "status" => "ofac_status" },
        # The API reports a sentence. If it ever becomes a boolean, a caller who
        # was told to read prose needs to hear about it.
        describe: ->(ofac) { "\"#{truncate(ofac.status || "null", 44)}\" (#{json_type(ofac.status)})" }
      ),

      from_record(["ex-10"], "OFAC stays four-valued") do |nonprofit, runner|
        ofac = NCP::Sources.ofac(nonprofit)
        state = if ofac.nil? then "unavailable"
                elsif ofac.status.nil? then "null"
                else json_type(ofac.status)
                end

        assert(state != "boolean",
               "ofac_status came back as a boolean — screening logic that reads prose will silently break")

        runner.note("OFAC stays four-valued", "nothing was screened against the SDN list for this record") if state == "unavailable"

        { status: state == "unavailable" ? :warn : :pass,
          detail: "screened → #{state == "string" ? "a sentence" : state} · no boolean derived from it" }
      end,

      from_record(["ex-11"], "cross-source conflict") do |nonprofit, runner|
        conflict = nonprofit.irs_bmf_pub78_conflict

        assert([nil, true, false].include?(conflict), "irs_bmf_pub78_conflict came back as #{json_type(conflict)}")

        if conflict == true
          runner.note("cross-source conflict",
                      "BMF and Publication 78 disagree: bmf_status #{nonprofit.bmf_status.inspect}, " \
                      "pub78_verified #{nonprofit.pub78_verified.inspect} — both preserved, neither resolved")

          next { detail: "conflict reported and both sources preserved" }
        end

        { detail: if conflict == false
                    "no conflict between BMF and Publication 78"
                  else
                    "the API did not report a conflict flag for this record"
                  end }
      end,

      from_record(["ex-12"], "foundation classification") do |nonprofit, runner|
        pairs = [%w[bmf_subsection subsection_description], %w[foundation_code foundation_code_description],
                 %w[foundation_type_code foundation_type_description]]

        # A description is the source's own label. One arriving without its code
        # would mean the label came from somewhere else (ex-12).
        pairs.each do |code, description|
          next if nonprofit[description].nil?

          assert(nonprofit.key?(code),
                 "#{description} was returned without #{code} — the label has no source value behind it")
        end

        described = pairs.count { |_code, description| !nonprofit[description].to_s.empty? }

        if described < pairs.size
          runner.note("foundation classification",
                      "#{pairs.size - described} classification code(s) arrived without a description")
        end

        { detail: "509(a): #{nonprofit.foundation_509a_status || "—"} · " \
                  "#{truncate(nonprofit.foundation_code_description || "no foundation description", 34)}",
          data: { described: described, of: pairs.size } }
      end,

      from_record(["ex-13"], "filing and exemption metadata") do |nonprofit, runner|
        codes = %w[filing_req_code exempt_status_code group_exemption ruling_month ruling_year]

        # Codes are preserved exactly as sent — never coerced, never re-labelled.
        codes.each do |code|
          value = nonprofit[code]
          assert(value.nil? || value.is_a?(String) || value.is_a?(Numeric), "#{code} came back as #{json_type(value)}")
        end

        year = Integer(nonprofit.ruling_year.to_s, 10, exception: false)
        month = Integer(nonprofit.ruling_month.to_s, 10, exception: false)

        if !nonprofit.ruling_year.nil? && !(year && year >= 1900 && year <= Time.now.year)
          runner.note("filing and exemption metadata", "ruling_year is \"#{nonprofit.ruling_year}\"")
        end

        if !nonprofit.ruling_month.nil? && !(month && month >= 1 && month <= 12)
          runner.note("filing and exemption metadata", "ruling_month is \"#{nonprofit.ruling_month}\"")
        end

        returned_codes = codes.reject { |code| nonprofit[code].to_s.empty? }

        { detail: "#{returned_codes.size}/#{codes.size} codes returned verbatim · " \
                  "ruling #{nonprofit.ruling_month || "?"}/#{nonprofit.ruling_year || "?"}",
          data: codes.to_h { |code| [code, nonprofit[code]] } }
      end,

      from_record(["ex-14"], "data freshness") do |nonprofit, runner|
        date_fields = %w[report_date organization_info_last_modified most_recent_bmf most_recent_pub78 revocation_date
                         reinstatement_date]
        now = Time.now
        ages = []
        unparsable = []
        future = []

        date_fields.each do |field|
          value = nonprofit[field]
          next if value.nil? || value == ""

          time = parse_api_date(value)

          if time.nil?
            unparsable << "#{field}=\"#{value}\""
            next
          end

          future << "#{field}=#{value}" if time > now + 86_400
          ages << { field: field, days: age_in_days(time, now) }
        end

        unless unparsable.empty?
          runner.note("data freshness",
                      "dates that do not parse as dates: #{unparsable.join(", ")}")
        end
        runner.note("data freshness", "dates in the future: #{future.join(", ")}") unless future.empty?

        if ages.empty?
          runner.note("data freshness", "no source date was returned — the record carries no freshness signal")
          next { status: :warn, detail: "no dates on this record" }
        end

        oldest = ages.max_by { |entry| entry[:days] }

        { status: unparsable.empty? && future.empty? ? :pass : :warn,
          detail: "#{ages.size}/#{date_fields.size} dates · oldest #{oldest[:field]} at #{oldest[:days]}d",
          data: { ages: ages } }
      end
    ]
  end

  # --- checks: forward compatibility (ex-25) ----------------------------------

  def forward_compatibility_checks
    [
      Check.new(covers: ["ex-25"], name: "raw envelope is unmodified", cost: 0, body: lambda do |runner|
        result = runner.single_result
        next { status: :fail, detail: "the single check did not return a record" } if result.nil?

        data = result.raw["data"]
        expected = data.is_a?(Array) ? data.first : data
        numeric = ->(value) { value.is_a?(Numeric) ? value : nil }

        assert(result.nonprofit.to_h.equal?(expected), "result.nonprofit reads a copy of the body, not the body itself")
        assert(result.check_count == numeric.call(result.raw["nonprofit_check_count"]),
               "check_count does not match the envelope it was read from")
        assert(result.time_taken_ms == numeric.call(result.raw["timeTaken"]),
               "time_taken_ms does not match the envelope it was read from")

        { detail: "raw carries #{result.raw.size} envelope keys, none rewritten" }
      end),

      from_record(["ex-25"], "no wire field is dropped") do |nonprofit, runner|
        raw_data = runner.single_result.raw["data"]
        data = raw_data.is_a?(Array) ? raw_data.first : raw_data

        # Whatever the API adds, the installed gem still hands it over.
        data.each_key do |field|
          assert(nonprofit.key?(field), "the wire field \"#{field}\" is not readable on the model")
          assert(nonprofit[field].equal?(data[field]),
                 "the value of \"#{field}\" was altered between the wire and the model")
        end

        unknown = data.keys - Fixtures.known_nonprofit_fields

        assert(nonprofit["a_field_this_api_has_never_sent"].nil? && !nonprofit.key?("a_field_this_api_has_never_sent"),
               "[] invented a value for a field that was never returned")

        { detail: "#{data.size} wire fields readable · " +
          (unknown.empty? ? "none newer than this SDK on this record" : "#{unknown.size} newer than this SDK and still reachable"),
          data: { unknown: unknown } }
      end
    ]
  end

  # --- checks: bulk (ex-17..ex-20) --------------------------------------------

  def bulk_checks(eins, missing_ein)
    bulk_eins = eins.first(DevEnv::BULK_PROBE_LIMIT)
    duplicate_probe = eins.size >= 2 ? [eins[1], eins[0], eins[1]] : nil
    checks = []

    checks << Check.new(covers: %w[ex-19 bulk], name: "bulk with a miss", cost: bulk_eins.size + 1, body: lambda do |runner|
      submitted = bulk_eins + [missing_ein]

      begin
        result = runner.client.nonprofits.check_bulk(submitted)
      rescue NCP::NotFoundError => e
        raise unless free_tier_restriction?(e)

        # A key whose bulk EINs are allowlisted answers this batch by refusing it
        # whole, before any lookup runs. That refusal is a contract in its own
        # right and it is the one this request actually exercised, so hold it to
        # that contract rather than reporting no result at all. What goes
        # unverified is ex-19's own claim, which needs a body carrying hits and
        # misses together — the detail says so.
        runner.free_tier_key = true
        reasons = e.api_errors.map { |detail| detail.reason.to_s }

        assert(e.status == 404, "the allowlist refusal returned HTTP #{e.status}, expected 404")
        assert(reasons.any? { |reason| reason.match?(/accessible nonprofits/i) },
               "no reason named the accessible-nonprofits restriction: #{JSON.generate(reasons)}")

        next { detail: "a #{submitted.size}-EIN batch reaching outside the allowlist was refused whole · 404 · " \
                       "request #{e.request_id || "no id"} · partial success needs a key with open bulk access",
               data: { contract: "allowlist-refusal", reasons: reasons, outside_allowlist: missing_ein } }
      end

      runner.observe_cycle_count(result.check_count)
      runner.capture_bulk(result)

      assert(result.status == 200, "a batch with matches and misses returned HTTP #{result.status}, expected 200")
      assert(!result.organizations.empty?, "no organizations were returned")

      unless result.not_found_eins.include?(missing_ein)
        runner.note("bulk with a miss",
                    "the missing EIN was not reported in errors[].eins; not_found_eins = #{JSON.generate(result.not_found_eins)}")
      end

      # Every input must map to a matched record or a reported failure.
      matched = result.organizations.map(&:ein)
      unaccounted = submitted.reject { |value| matched.include?(value) || result.not_found_eins.include?(value) }

      runner.note("bulk with a miss", "inputs with neither a record nor an error: #{unaccounted.join(", ")}") unless unaccounted.empty?

      { status: unaccounted.empty? ? :pass : :warn,
        detail: "#{result.organizations.size} matched · #{result.not_found_eins.size} missing · " \
                "#{result.errors.size} error entries",
        data: { not_found_eins: result.not_found_eins } }
    end)

    if duplicate_probe
      checks << Check.new(covers: ["ex-18"], name: "bulk order and duplicates", cost: duplicate_probe.size, body: lambda do |runner|
        before = runner.requests.size
        result = runner.client.nonprofits.check_bulk(duplicate_probe)

        runner.observe_cycle_count(result.check_count)
        runner.capture_bulk(result)

        returned_eins = result.organizations.map(&:ein)

        # The SDK sends what it was given, duplicates and order included.
        sent_body = runner.requests.drop(before).last&.fetch(:body)

        if sent_body.is_a?(String)
          assert(JSON.generate(duplicate_probe) == sent_body, "the request body was #{sent_body}, not the EINs as supplied")
        end

        positional = returned_eins == duplicate_probe
        deduped_order = returned_eins == duplicate_probe.uniq
        collapsed = returned_eins.size == returned_eins.uniq.size

        # Observations about the deployment, recorded either way — the README's
        # claims are what they check.
        runner.note("bulk order and duplicates", "sent [#{duplicate_probe.join(", ")}] → received [#{returned_eins.join(", ")}]")
        runner.note("bulk order and duplicates",
                    if positional
                      "response order matched request order on this call — the API does not guarantee it, so keep indexing by EIN"
                    else
                      "response order did not match request order, as documented — index by EIN"
                    end)

        assert(collapsed, "a duplicated EIN was returned more than once, which contradicts set matching")

        { detail: "duplicate collapsed to one record · request-order match: #{positional} · " \
                  "deduped-order match: #{deduped_order}",
          data: { requested: duplicate_probe, returned: returned_eins, positional: positional } }
      end)
    end

    checks << Check.new(covers: ["ex-17"], name: "bulk and single agree", cost: 0, body: lambda do |runner|
      single = runner.single_result&.nonprofit
      bulk = runner.bulk_result

      next { status: :fail, detail: "both a single and a bulk result are needed" } if single.nil? || bulk.nil?

      twin = bulk.organizations.find { |org| org.ein == single.ein }

      next { status: :fail, detail: "#{single.ein} was not among the bulk results" } if twin.nil?

      assert(twin.organization_name == single.organization_name,
             "the two endpoints disagree about the name: \"#{single.organization_name}\" vs \"#{twin.organization_name}\"")

      # A record that is thinner in bulk is a real trap for anyone who screens in
      # bulk and reads fields the single endpoint taught them to expect.
      only_single = single.keys - twin.keys
      only_bulk = twin.keys - single.keys

      unless only_single.empty?
        runner.note("bulk and single agree", "the bulk record omits: #{only_single.join(", ")} — do not assume bulk records are complete")
      end

      runner.note("bulk and single agree", "only the bulk record carries: #{only_bulk.join(", ")}") unless only_bulk.empty?

      { status: only_single.empty? && only_bulk.empty? ? :pass : :warn,
        detail: if only_single.empty? && only_bulk.empty?
                  "identical field sets for #{single.ein} on both endpoints"
                else
                  "#{only_single.size} field(s) only in single · #{only_bulk.size} only in bulk"
                end,
        data: { only_single: only_single, only_bulk: only_bulk } }
    end)

    checks
  end

  # --- checks: the response against what this gem predicts --------------------

  # Six checks that hold the raw JSON this run received against the two documents
  # that describe what it is supposed to look like.
  #
  # Everything else in this file asserts what the SDK does with a response. These
  # assert that the response is the one the SDK was written for: a field that
  # changed from a boolean to a string, a timestamp that turned ISO, a field the
  # API started sending that the gem has never heard of, a field it stopped
  # sending.
  #
  # `response_contract.json` is what this gem *promises*. A failure there means
  # the API no longer matches what the SDK tells its users to expect.
  #
  # `response_baseline.json` is what production *returned*, recorded once by
  # `rake baseline:record` and committed. A failure there means production moved.
  # The recording is never written by a run: a baseline that rewrites itself
  # agrees with the API by construction and can never fail.
  #
  # Free. Both responses were already fetched and paid for by the checks above.
  def contract_checks
    contract = nil
    baseline = nil
    observed = {}

    load_contract = lambda do
      contract ||= JSON.parse(File.read(CONTRACT_PATH))
    rescue JSON::ParserError, SystemCallError => e
      raise AssertionFailed, "#{File.basename(CONTRACT_PATH)} is not readable JSON: #{e.message}"
    end

    # The committed recording. An unreadable or absent one is a failure, not a
    # shrug: the whole point of the file is that every run is held against it.
    load_baseline = lambda do
      unless File.exist?(BASELINE_PATH)
        raise AssertionFailed, "#{File.basename(BASELINE_PATH)} is missing — record it against production with " \
                               "`bundle exec rake baseline:record` and commit it"
      end

      baseline ||= JSON.parse(File.read(BASELINE_PATH))
    rescue JSON::ParserError => e
      raise AssertionFailed, "#{File.basename(BASELINE_PATH)} is not readable JSON: #{e.message}"
    end

    observe = lambda do |runner, kind|
      observed[kind] ||= begin
        raw = kind == :single ? runner.single_result&.raw : runner.bulk_result&.raw

        if raw.nil?
          missing = if kind == :single then "the single check did not return a response"
                    elsif runner.free_tier_key then "this key restricts bulk EINs to an allowlist, so no bulk response was returned"
                    else "the bulk check did not return a response"
                    end

          { missing: missing }
        else
          { signature: Contract.signature_of(raw) }
        end
      end
    end

    against = lambda do |kind:, name:, diff:, fail_message:, describe:|
      Check.new(covers: ["contract"], name: name, cost: 0, body: lambda do |runner|
        current = observe.call(runner, kind)
        next { status: :fail, detail: current[:missing] } if current[:missing]

        expected = Contract.compose_expected(load_contract.call, kind)
        result = diff.call(expected, current[:signature], Contract.required_paths_of(load_contract.call, kind))
        paths = current[:signature].size

        assert(result[:total].zero?,
               "#{fail_message} — #{Contract.summarize_changes(result[:changes])}\n" \
               "#{Contract.format_changes(result[:changes])}\n      " \
               "reconcile models.rb and #{File.basename(CONTRACT_PATH)} with the API, once the change is understood and intended")

        { detail: describe.call(paths, result), data: { paths: paths, predicted: expected.size } }
      end)
    end

    # The same response, held against the committed recording of production.
    #
    # Strict in both directions on the shape. What it does not fail on is the part
    # a recording has no standing to judge — whether a nullable field happened to
    # carry a value, and the paths under a parent that arrived null. The counts it
    # passed over are printed either way, so nothing is hidden.
    against_baseline = lambda do |kind|
      Check.new(covers: ["contract"], name: "#{kind} response vs recording", cost: 0, body: lambda do |runner|
        current = observe.call(runner, kind)
        next { status: :fail, detail: current[:missing] } if current[:missing]

        recording = load_baseline.call
        before = recording.dig(kind.to_s, "signature")

        assert(before, "no #{kind} shape is recorded in #{File.basename(BASELINE_PATH)} — record it against production " \
                       "with `bundle exec rake baseline:record` and commit it")

        result = Contract.baseline_diff(before, current[:signature])

        assert(result[:total].zero?,
               "the live #{kind} response no longer matches the recording made from " \
               "#{recording["base_url"] || "production"} on #{recording["recorded_at"] || "an earlier date"} — " \
               "#{Contract.summarize_changes(result[:changes])}\n#{Contract.format_changes(result[:changes])}\n      " \
               "if production moved and the move is intended, re-record with `bundle exec rake baseline:record` " \
               "and commit the diff")

        paths = current[:signature].size

        { detail: "#{paths} paths, matching the recording · #{result[:nullable]} differ only in whether a value arrived · " \
                  "#{result[:unreachable]} under a null or empty parent",
          data: { paths: paths, nullable: result[:nullable], unreachable: result[:unreachable] } }
      end)
    end

    types_described = ->(paths, _result) { "#{paths} paths carry the predicted types and value formats" }
    fields_described = lambda do |paths, result|
      "#{paths} paths, all predicted · #{result[:unreachable]} under a null or empty parent · " \
        "#{result[:optional_absent]} optional and not sent"
    end

    [
      against.call(kind: :single, name: "single response types", diff: Contract.method(:contract_diff),
                   fail_message: "the live single response carries values this gem does not predict",
                   describe: types_described),
      against.call(kind: :single, name: "single response fields", diff: Contract.method(:coverage_diff),
                   fail_message: "the live single response and this gem disagree on which fields exist",
                   describe: fields_described),
      against.call(kind: :bulk, name: "bulk response types", diff: Contract.method(:contract_diff),
                   fail_message: "the live bulk response carries values this gem does not predict",
                   describe: types_described),
      against.call(kind: :bulk, name: "bulk response fields", diff: Contract.method(:coverage_diff),
                   fail_message: "the live bulk response and this gem disagree on which fields exist",
                   describe: fields_described),
      against_baseline.call(:single),
      against_baseline.call(:bulk)
    ]
  end

  # --- checks: rechecking the same record (ex-28..ex-30) ----------------------

  def recheck_checks(ein)
    [
      Check.new(covers: %w[ex-29 ex-28 ex-30], name: "a repeat check is stable", cost: 1, body: lambda do |runner|
        first = runner.single_result
        next { status: :fail, detail: "the single check did not return a record" } if first.nil? || first.nonprofit.nil?

        second = runner.client.nonprofits.check(ein)
        runner.observe_cycle_count(second.check_count)

        assert(!second.nonprofit.nil?, "the same EIN returned no record on the second call")
        assert(second.nonprofit.ein == first.nonprofit.ein, "the two calls returned different EINs for the same request")

        # A scheduled re-verification compares fields between runs. Fields that
        # appear and disappear between two calls seconds apart would make every
        # diff meaningless (ex-29, ex-30).
        appeared = second.nonprofit.keys - first.nonprofit.keys
        vanished = first.nonprofit.keys - second.nonprofit.keys
        changed = (first.nonprofit.keys & second.nonprofit.keys).reject do |field|
          first.nonprofit[field] == second.nonprofit[field]
        end

        { "appeared" => appeared, "vanished" => vanished, "changed" => changed }.each do |label, fields|
          runner.note("a repeat check is stable", "fields that #{label} between two calls: #{fields.join(", ")}") unless fields.empty?
        end

        distinct_ids = !first.request_id.nil? && !second.request_id.nil? && first.request_id != second.request_id

        if !first.request_id.nil? && !distinct_ids
          runner.note("a repeat check is stable", "both calls reported the same request id — an audit trail cannot tell them apart")
        end

        drifted = appeared.size + vanished.size + changed.size

        { status: drifted.zero? ? :pass : :warn,
          detail: (if drifted.zero?
                     "#{second.nonprofit.keys.size} fields identical across two calls"
                   else
                     "#{drifted} field(s) differed between two calls seconds apart"
                   end) +
            " · request ids #{distinct_ids ? "distinct" : "not distinguishable"}",
          data: { appeared: appeared, vanished: vanished, changed: changed } }
      end)
    ]
  end

  # --- checks: what actually went on the wire (ex-01, ex-17, ex-20) -----------

  def wire_checks(api_key)
    single_pattern = /#{Regexp.escape(NCP::SINGLE_CHECK_PATH).sub(Regexp.escape("{ein}")) { '\d{9}' }}\z/

    [
      Check.new(covers: %w[ex-17 ex-03], name: "documented endpoints and methods", cost: 0, body: lambda do |runner|
        next { status: :fail, detail: "no requests were sent" } if runner.requests.empty?

        singles = 0
        bulks = 0

        runner.requests.each do |request|
          uri = URI.parse(request[:url])

          assert(uri.query.nil?, "a request carried a query string: #{uri.query}")
          assert(request[:url].start_with?(runner.client.base_url),
                 "a request went somewhere other than the configured host: #{request[:url]}")

          if request[:method] == "POST"
            assert(uri.path.end_with?(NCP::BULK_CHECK_PATH), "POST went to #{uri.path}, not BULK_CHECK_PATH")
            assert(request[:content_type] == "application/json", "the bulk request was not JSON")

            body = JSON.parse(request[:body].to_s)

            assert(body.is_a?(Array), "the bulk body was not a JSON array of EINs")
            assert(body.all? do |value|
              value.to_s.match?(/\A\d{9}\z/)
            end, "the bulk body carried EINs that were not normalized")

            bulks += 1
          else
            assert(request[:method] == "GET", "unexpected method #{request[:method]}")
            assert(single_pattern.match?(uri.path), "GET went to #{uri.path}, not SINGLE_CHECK_PATH")
            assert(request[:body].nil?, "a GET carried a body")

            singles += 1
          end
        end

        { detail: "#{singles} GET on SINGLE_CHECK_PATH · #{bulks} POST on BULK_CHECK_PATH · no query strings",
          data: { singles: singles, bulks: bulks } }
      end),

      Check.new(covers: ["ex-01"], name: "credentials stay off the wire", cost: 0, body: lambda do |runner|
        next { status: :fail, detail: "no requests were sent" } if runner.requests.empty?

        user_agent_prefix = "#{NCP::GEM_NAME}/"

        runner.requests.each do |request|
          assert(!request[:url_carries_key], "the API key appeared in a request URL: #{request[:url]}")
          assert(request[:auth_carries_key], "a request went out without the key in its Authorization header")
          assert(request[:auth_scheme] == "Bearer", "the Authorization header used the \"#{request[:auth_scheme]}\" scheme")
          assert(request[:accept] == "application/json", "Accept was #{request[:accept].inspect}")
          assert(request[:user_agent].to_s.start_with?(user_agent_prefix) && request[:user_agent].include?(NCP::VERSION),
                 "the User-Agent does not identify this SDK version: #{request[:user_agent]}")
        end

        # Belt and braces: the recorded log itself must be safe to print.
        assert(!JSON.generate(runner.requests).include?(api_key), "the recorded request log contains the API key")

        { detail: "#{runner.requests.size} requests · key in Authorization only · UA #{user_agent_prefix}#{NCP::VERSION}" }
      end)
    ]
  end

  # --- checks: the disruptive probes (ex-22, ex-24) ---------------------------

  # The two probes that misbehave on purpose: one starves a request of time, the
  # other bursts until the server pushes back. The burst is bounded and stops the
  # moment a 429 arrives.
  def probe_checks(ein, api_key)
    [
      Check.new(covers: ["ex-24"], name: "timeout and cancellation", cost: 1, body: lambda do |runner|
        # Short enough that the response cannot arrive, long enough that the
        # connection has been established — otherwise the socket fails first and
        # the SDK correctly reports a network error rather than a timeout.
        deadline = [0.002, ((runner.observed_round_trip || 0.1) * 0.3).round(3)].max

        starved = begin
          runner.client.nonprofits.check(ein, timeout: deadline, retry: false)
          "the request completing inside it"
        rescue NCP::TimeoutError => e
          assert(e.timeout == deadline, "error.timeout was #{e.timeout}, expected #{deadline}")
          assert(e.origin == :local, "a timeout reported origin #{e.origin.inspect}")
          "TimeoutError"
        rescue NCP::NetworkError
          "a network error"
        end

        timed_out = starved == "TimeoutError"

        # Cancellation is Ruby's own, so what is checked is that the SDK stays out
        # of its way: an interrupt that lands mid-request comes out as itself, is
        # not converted, and is not retried. The request is held at a gate rather
        # than sent, so the interrupt lands inside the SDK every time instead of
        # racing a fast response — the SDK's handling is the same either way.
        attempts = 0
        started = Queue.new
        gate = lambda do |_request|
          attempts += 1
          started << true
          sleep
        end

        probe = NCP::Client.new(api_key: api_key, base_url: runner.client.base_url, http_adapter: gate,
                                retry: { max_retries: 3, initial_delay: 0.001 })
        worker = Thread.new { probe.nonprofits.check(ein) }
        worker.report_on_exception = false

        started.pop
        worker.raise(CallerCancelled)

        outcome = begin
          worker.value
          "it completed"
        rescue CallerCancelled
          :propagated
        rescue Exception => e # rubocop:disable Lint/RescueException -- reporting whatever came out instead
          e.class.name
        end

        assert(outcome == :propagated, "an interrupt during the request came out as #{outcome}, not as itself")
        assert(attempts == 1, "the SDK retried through a cancellation: #{attempts} attempts")

        # And a caller-side deadline around the whole call is Ruby's Timeout::Error.
        begin
          Timeout.timeout(0.05) { probe.nonprofits.check(ein) }
          raise AssertionFailed, "Timeout.timeout around a held request did not fire"
        rescue Timeout::Error => e
          assert(!e.is_a?(NCP::Error), "Timeout.timeout surfaced as an SDK error")
        end

        unless timed_out
          runner.note("timeout and cancellation",
                      "a #{deadline}s deadline produced #{starved} rather than a timeout — " \
                      "expected when the round trip is very short, as on a local host")
        end

        { status: timed_out ? :pass : :warn,
          detail: "#{deadline}s deadline → #{starved} · " \
                  "interrupt → propagated untouched, 1 attempt · Timeout.timeout → Timeout::Error" }
      end),

      Check.new(covers: %w[ex-22 error-handling], name: "rate limit", cost: RATE_LIMIT_ATTEMPTS, body: lambda do |runner|
        (1..RATE_LIMIT_ATTEMPTS).each do |attempt|
          result = runner.client.nonprofits.check(ein, retry: false)
          runner.observe_cycle_count(result.check_count)
        rescue NCP::RateLimitError => e
          assert(e.status == 429, "expected status 429, got #{e.status}")

          return { detail: "429 after #{attempt} request(s) → RateLimitError · Retry-After #{e.retry_after_seconds || "not sent"}",
                   data: { attempt: attempt, retry_after_seconds: e.retry_after_seconds } }
        end

        { status: :warn, detail: "no 429 within #{RATE_LIMIT_ATTEMPTS} sequential requests — the limit was not reached" }
      end)
    ]
  end

  # The plan: every check in this file, in the order their results depend on.
  #
  # The record-derived checks read what the single check fetched, the contract
  # checks read both responses, and the wire checks read the log every earlier
  # check wrote — so this order is not the order the report is read in, and the
  # report regroups it. Nothing here is conditional. Each entry declares its
  # billable cost so the total can be printed before the first request goes out.
  def build_plan(api_key, base_url, ein, bulk_eins, missing_ein)
    [
      *client_checks(api_key),
      *local_validation_checks(ein, bulk_eins, api_key),
      *authentication_checks(ein, base_url),
      *single_check_checks(ein, missing_ein, api_key),
      *source_checks,
      *forward_compatibility_checks,
      *bulk_checks(bulk_eins, missing_ein),
      *contract_checks,
      *recheck_checks(ein),
      *wire_checks(api_key),
      *probe_checks(ein, api_key)
    ]
  end

  # --- the report -------------------------------------------------------------

  # Column the detail text starts in, so the results read as two columns.
  NAME_WIDTH = 34

  def column(name, width = NAME_WIDTH)
    name.length < width ? name.ljust(width) : "#{name} "
  end

  # One heading per example file, and under it what this run has to say about
  # what that file claims.
  def print_report(groups, findings)
    observations = findings.group_by { |finding| finding[:check] }

    groups.each do |group|
      say "\n#{group.id}  #{group.title}"

      group.primary.each do |result|
        # Padded before it is coloured: the escape sequences carry no width.
        line = "#{column(result[:name])}#{result[:detail]}#{"  [#{result[:cost]} check(s)]" if result[:cost].positive?}"

        say "  #{mark(result[:status])} #{tint(result[:status], line)}"

        (observations[result[:name]] || []).each { |finding| say paint(:dim, "      · #{finding[:message]}") }
      end

      group.secondary.each do |entry, under|
        say "  ↳ #{mark(entry[:status])} #{tint(entry[:status],
                                                "#{column(entry[:name], NAME_WIDTH - 2)}checked under #{under}")}"
      end

      say "  – no check of its own — it composes examples checked above" if group.primary.empty? && group.secondary.empty?
    end
  end

  def finish(runner, examples, started_at, exit_code)
    counts = %i[pass fail warn skip].to_h do |status|
      [status, runner.results.count do |result|
        result[:status] == status
      end]
    end
    groups = group_by_example(examples, runner.results)
    files = groups.reject { |group| group.id == CONTRACT_GROUP.id }
    own = files.count { |group| group.primary.any? }
    borrowed = files.count { |group| group.primary.empty? && group.secondary.any? }
    delta = runner.cycle_count_start && runner.cycle_count_end ? runner.cycle_count_end - runner.cycle_count_start : nil

    # Closes the ticker line.
    say ""

    print_report(groups, runner.findings)

    say "\nSummary"
    say "  #{runner.results.size} checks: #{paint(:green, "#{counts[:pass]} passed")}, " \
        "#{paint(counts[:fail].positive? ? :red : nil, "#{counts[:fail]} failed")}, " \
        "#{paint(counts[:warn].positive? ? :yellow : nil, "#{counts[:warn]} warned")}, #{counts[:skip]} skipped"
    say "  #{files.size} example files: #{own} checked here, #{borrowed} checked under another, " \
        "#{files.size - own - borrowed} with no check"
    say "  #{runner.requests_sent} HTTP requests · #{runner.checks_spent} checks budgeted"
    say "  billing-cycle counter: #{runner.cycle_count_start || "n/a"} → #{runner.cycle_count_end || "n/a"}" +
        (delta.nil? ? "" : "  (+#{delta} actually billed)")
    say "  #{monotonic_ms - started_at}ms · SDK #{NCP::VERSION}"

    exit exit_code
  end

  def main(argv)
    env_file = DevEnv.load_env_file

    # Before the key check, so `--help` and a bad EIN are answered without one.
    subjects = resolve_subjects(argv, env_file)
    ein, bulk_eins, missing_ein = subjects.map(&:value)

    api_key = ENV.fetch(DevEnv::API_KEY_ENV, "")

    if api_key.empty?
      warn "No API key. Put #{DevEnv::API_KEY_ENV} in ruby/.env, or export it, and run this again."
      exit 2
    end

    secrets.push(api_key, INVALID_API_KEY)

    base_url = ENV.fetch("PACTMAN_BASE_URL", nil) || NCP.base_url_for_environment(NCP::DEFAULT_ENVIRONMENT)
    examples = discover_examples
    plan = build_plan(api_key, base_url, ein, bulk_eins, missing_ein)
    planned_cost = plan.sum(&:cost)
    ignored = subjects.flat_map(&:ignored)

    say "Target        #{base_url}"
    say "Key           from #{key_source(env_file)} (#{api_key.length} characters, never printed)"
    say "Subjects      #{ein} · bulk #{bulk_eins.join(", ")} · no record #{missing_ein} " \
        "(from #{subjects.map(&:source).uniq.join(", ")})"
    say "              #{ignored.join(", ")} not used — the bulk probes read the first #{bulk_eins.size}" unless ignored.empty?
    say "Plan          #{plan.size} checks across #{examples.size} example files, #{plan.count do |check|
      check.cost.zero?
    end} of them free"
    say "Cost          #{planned_cost} billable API checks, charged to this key"
    say ""

    runner = Runner.new(api_key)

    # Records every outbound request, so "nothing was sent" and "the key never
    # left the Authorization header" can be asserted rather than assumed.
    runner.client = NCP::Client.new(api_key: api_key, base_url: base_url, timeout: 20, retry: { max_retries: 2 },
                                    http_adapter: RecordingAdapter.new(runner))

    started_at = monotonic_ms

    # The report cannot start until the last check is done, so the ticker is what
    # says the run is alive: one mark per check, in the order they run.
    $stdout.write "Running       "
    $stdout.flush

    begin
      plan.each do |check|
        runner.run(check)
        $stdout.write mark(runner.results.last[:status])
        $stdout.flush
      end
    rescue Interrupt
      # A run stopped halfway still paid for everything it sent, so it still reports.
      finish(runner, examples, started_at, 130)
    end

    finish(runner, examples, started_at, runner.results.any? { |result| result[:status] == :fail } ? 1 : 0)
  end
end

SmokeLive.main(ARGV) if $PROGRAM_NAME == __FILE__
