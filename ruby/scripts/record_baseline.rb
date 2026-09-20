#!/usr/bin/env ruby
# frozen_string_literal: true

# Records the shape of the production API into `response_baseline.json`.
#
# `response_contract.json` says what this gem *promises* a response looks like.
# This file says what production *actually returned*, once, on a day someone
# looked. They answer different questions and both are needed: the contract
# catches the API drifting away from the declared models, the baseline catches
# the API drifting at all — including in the fields the contract leaves as a bare
# `string`, where a promise is too loose to notice anything.
#
# The recording is committed, so it is the same for everyone and a change to it
# shows up in review as what it is: production moved, and someone accepted it.
# That is also why writing it is a deliberate command rather than something a
# smoke run does on the side. A baseline that rewrites itself on every run agrees
# with the API by construction and can never fail.
#
# Usage
#   bundle exec ruby scripts/record_baseline.rb [--allow-any-target] [--dry-run]
#
# The key, the subjects and the target come from the environment or `.env`,
# exactly as `smoke_live.rb` reads them. Recording spends billable checks: one
# single lookup and up to two bulk lookups against the key you point it at.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "time"

require "pactman/nonprofit_check_plus"
require_relative "contract"
require_relative "env"

NCP = Pactman::NonprofitCheckPlus

BASELINE_PATH = File.expand_path("../lib/pactman/nonprofit_check_plus/response_baseline.json", __dir__)

NOTE = "The shape production returned when this was recorded: path, JSON type and value format, never a value. " \
       "Committed, so every run of scripts/smoke_live.rb is held against the same recording — any path added or " \
       "removed, and any token that changed, fails there. Rewrite it with `bundle exec rake baseline:record` only " \
       "when production has moved and the move is intended."

env_file = DevEnv.load_env_file
allow_any_target = ARGV.include?("--allow-any-target")
dry_run = ARGV.include?("--dry-run")

api_key = ENV.fetch(DevEnv::API_KEY_ENV, "")

if api_key.empty?
  warn "No API key. Put #{DevEnv::API_KEY_ENV} in ruby/.env, or export it, and run this again."
  exit 2
end

# Replaces the credential wherever it surfaces. Applied to everything printed.
say = ->(text) { puts text.to_s.gsub(api_key, "[redacted]") }

production_url = NCP.base_url_for_environment(NCP::DEFAULT_ENVIRONMENT)
base_url = ENV.fetch("PACTMAN_BASE_URL", nil) || production_url
normalize_url = ->(value) { value.sub(%r{/+\z}, "").downcase }

# The baseline every run is held against has to come from the deployment those
# runs are about. A recording made against a sandbox would quietly turn the
# sandbox into the standard, and nothing downstream could tell.
if normalize_url.call(base_url) != normalize_url.call(production_url) && !allow_any_target
  warn "Refusing to record from #{base_url}.\n" \
       "The committed baseline describes production (#{production_url}); recording it from anywhere else makes " \
       "that deployment the standard for everyone.\n" \
       "Unset PACTMAN_BASE_URL, or pass --allow-any-target if you mean it."
  exit 2
end

if ENV.fetch("PACTMAN_SMOKE_EIN", "").empty?
  warn "No subject. Set PACTMAN_SMOKE_EIN to the EIN this recording should be made from."
  exit 2
end

begin
  ein = NCP::EIN.normalize(ENV.fetch("PACTMAN_SMOKE_EIN"))
  missing = ENV.fetch("PACTMAN_SMOKE_MISSING_EIN", "")
  missing_ein = missing.empty? ? nil : NCP::EIN.normalize(missing)
  # The same batch `smoke_live.rb` sends, so the two signatures describe the same
  # set of organizations rather than differing by batch size.
  bulk_eins = NCP::EIN.normalize_all(
    ENV.fetch("PACTMAN_SMOKE_BULK_EIN", "").split(",").map(&:strip).reject(&:empty?).first(DevEnv::BULK_PROBE_LIMIT)
  )
rescue NCP::ValidationError => e
  warn e.message
  exit 2
end

client = NCP::Client.new(api_key: api_key, base_url: base_url, timeout: 20, retry: { max_retries: 2 })

# The batches to try, in the order `smoke_live.rb` would arrive at them.
#
# That run keeps the first bulk response any of its probes returns, and the
# probes go in a fixed order: the partial-success batch first, because its
# envelope is the only one carrying the item-level `errors` a batch with a miss
# comes back with, then the duplicate probe, which is what a key whose bulk EINs
# are allowlisted falls back to.
bulk_attempts = []
bulk_attempts << (bulk_eins + [missing_ein]) if !bulk_eins.empty? && missing_ein
bulk_attempts << [bulk_eins[1], bulk_eins[0], bulk_eins[1]] if bulk_eins.size >= 2

say.call "Target        #{base_url}"
say.call "Subjects      #{ein}#{bulk_eins.empty? ? " · no bulk subjects" : " · bulk #{bulk_eins.join(", ")}"}"
say.call "Cost          up to #{1 + bulk_attempts.size} billable request(s)"
say.call "Key           from #{env_file&.names&.include?(DevEnv::API_KEY_ENV) ? ".env" : "the environment"}"
say.call ""

# Runs one lookup and reduces it to a signature, or reports why it could not.
record = lambda do |label, &lookup|
  result = lookup.call
  signature = Contract.signature_of(result.raw)

  say.call "  #{label.ljust(8)} #{signature.size} paths"
  signature
rescue NCP::Error => e
  say.call "  #{label.ljust(8)} failed — #{e.message}"
  nil
end

single = record.call("single") { client.nonprofits.check(ein) }
bulk = nil

bulk_attempts.each do |attempt|
  bulk = record.call("bulk") { client.nonprofits.check_bulk(attempt) }
  break if bulk
end

if single.nil? && bulk.nil?
  warn "\nNothing was recorded. The baseline on disk is unchanged."
  exit 1
end

# A half that could not be recorded keeps whatever is already on disk.
#
# A key whose allowlist refuses the batch, or a lookup that timed out, is a
# reason to record nothing new — not a reason to throw away a good recording made
# on a day the call worked.
existing = File.exist?(BASELINE_PATH) ? JSON.parse(File.read(BASELINE_PATH)) : {}
kept = []

half = lambda do |kind, recorded|
  next { "signature" => recorded } if recorded

  kept << kind if existing.dig(kind, "signature")
  existing[kind]
end

baseline = {
  "note" => NOTE,
  "recorded_at" => Time.now.utc.iso8601(3),
  "base_url" => base_url,
  "sdk_version" => NCP::VERSION,
  "single" => half.call("single", single),
  "bulk" => half.call("bulk", bulk)
}

if dry_run
  say.call "\n--dry-run: nothing written."
  exit 0
end

File.write(BASELINE_PATH, "#{JSON.pretty_generate(baseline)}\n")

say.call "\nWrote response_baseline.json — recorded from #{base_url} on SDK #{NCP::VERSION}."
say.call "The #{kept.join(" and ")} half was left as it was — this run could not record it." unless kept.empty?
say.call "Commit it. Every smoke run from now on is held against it."
