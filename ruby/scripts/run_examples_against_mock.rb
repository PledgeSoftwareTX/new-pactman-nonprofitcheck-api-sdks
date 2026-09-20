# frozen_string_literal: true

# Runs every example against the mock server and fails if any of them errors.
#
# This is what CI uses to keep the documented examples honest. Each example runs
# in its own `ruby` process with `lib/` on the load path, exactly as
# `bundle exec ruby examples/<name>.rb` would run it.
#
# Pass a filter to run a subset:
#
#   ruby scripts/run_examples_against_mock.rb ex_22 ex_23
#   EXAMPLES_VERBOSE=1 ruby scripts/run_examples_against_mock.rb

require "rbconfig"
require_relative "mock_server"

ROOT = File.expand_path("..", __dir__)
EXAMPLES_DIR = File.join(ROOT, "examples")
API_KEY = "mock-key"
PER_EXAMPLE_TIMEOUT = 60
NUMBERED = /\Aex_\d{2}_/

# Numbered examples first, then the originals, so failures read in order.
def discover_examples
  files = Dir.children(EXAMPLES_DIR).select { |name| name.end_with?(".rb") }.sort
  numbered, others = files.partition { |name| NUMBERED.match?(name) }

  (numbered + others).map { |name| "examples/#{name}" }
end

# Runs one example to completion or to its deadline, with stdout and stderr
# interleaved as a reader would see them.
def run(script, env)
  reader, writer = IO.pipe
  pid = Process.spawn(env, RbConfig.ruby, "-I", File.join(ROOT, "lib"), script,
                      chdir: ROOT, out: writer, err: writer, in: File::NULL)
  writer.close

  output = +""
  collector = Thread.new { output << reader.read }

  unless collector.join(PER_EXAMPLE_TIMEOUT)
    Process.kill("KILL", pid)
    Process.wait(pid)
    collector.join
    raise "#{script} did not finish within #{PER_EXAMPLE_TIMEOUT}s\n#{output}"
  end

  _, status = Process.wait2(pid)
  raise "#{script} exited with status #{status.exitstatus}\n#{output}" unless status.success?

  output
ensure
  reader&.close
end

filters = ARGV
examples = discover_examples.select { |name| filters.empty? || filters.any? { |filter| name.include?(filter) } }

fixture = MockServer.start(api_key: API_KEY)
verbose = ENV["EXAMPLES_VERBOSE"] == "1"
failures = []

puts "Running #{examples.size} examples against #{fixture.url}\n\n"

begin
  examples.each do |example|
    output = run(example, "PACTMAN_API_KEY" => API_KEY, "PACTMAN_BASE_URL" => fixture.url)

    # The one assertion this harness makes about content: no example may print
    # the credential it was given.
    raise "#{example} printed the API key." if output.include?(API_KEY)

    puts "✓ #{example}"
    puts output.rstrip.lines.map { |line| "    #{line}" }.join if verbose
  rescue StandardError => e
    failures << example
    warn "✗ #{e.message}"
  end
ensure
  fixture.close
end

puts "\n#{examples.size - failures.size}/#{examples.size} examples passed."

unless failures.empty?
  warn "Failed: #{failures.join(", ")}"
  exit 1
end
