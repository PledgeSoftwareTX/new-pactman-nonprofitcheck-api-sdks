# frozen_string_literal: true

# The `.env` beside the gem, read by every script that needs a live key.
#
# Kept here rather than in one script so `smoke_live.rb` and `record_baseline.rb`
# read the same file the same way — the two have to agree on which deployment
# and which subjects they are talking about, and a second copy of this parser is
# how they would stop agreeing.
module DevEnv
  # The variable the credential is read from, in the environment or in `.env`.
  API_KEY_ENV = "PACTMAN_API_KEY"

  # How many of the bulk subjects a run actually sends.
  #
  # The bulk probes read the first few and the rest would cost quota unspent —
  # but the recorder has to send the same batch the smoke run does. A signature
  # collapses every element of `data[]` onto one path, so a five-EIN recording
  # and a three-EIN run disagree wherever the two extra organizations carry a
  # value the first three do not.
  BULK_PROBE_LIMIT = 3

  EnvFile = Data.define(:path, :names)

  module_function

  # Loads `ruby/.env`, so the key and any standing overrides live in a file
  # rather than in the shell for every run. The file is gitignored.
  #
  # A variable already in the environment wins: exporting one for a single run
  # must not be silently overridden by a file someone set up months ago.
  #
  # @return [EnvFile, nil]
  def load_env_file(path = File.expand_path("../.env", __dir__))
    return nil unless File.exist?(path)

    names = []

    # Both line endings: a .env saved on Windows ends its lines with CRLF.
    File.read(path, encoding: "UTF-8").split(/\r?\n/).each do |line|
      match = line.match(/\A\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\z/)
      next unless match

      name, raw = match.captures
      next if ENV.key?(name)

      ENV[name] = raw.strip.sub(/\A(['"])(.*)\1\z/m, '\2')
      names << name
    end

    EnvFile.new(path: path, names: names.freeze)
  end
end
