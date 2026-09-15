package pactman

import "fmt"

// Environment names a Pactman deployment.
//
// Endpoint hosts are declared in this file and nowhere else. Nothing else in
// this package contains a literal Pactman host.
type Environment string

// EnvironmentProduction is the Pactman production API, and the default.
const EnvironmentProduction Environment = "production"

// DefaultEnvironment is the environment used when none is configured.
const DefaultEnvironment = EnvironmentProduction

// Pactman's QA, SIT and sandbox hosts are internal and are deliberately not
// exposed here. Point at one with WithBaseURL if you have been given access.
var baseURLs = map[Environment]string{
	EnvironmentProduction: "https://entities.pactman.org",
}

// SingleCheckPath is the path of the single-check endpoint. {ein} is replaced
// with a normalized EIN.
const SingleCheckPath = "/api/entities/nonprofitcheck/v1/us/ein/{ein}"

// BulkCheckPath is the path of the bulk-check endpoint.
const BulkCheckPath = "/api/entities/nonprofitcheckbulk/v1/us/eins"

// MaxBulkEINs is the most EINs the API accepts in one bulk request. It mirrors
// the server-side limit and is declared once, here.
const MaxBulkEINs = 50

// SupportedEnvironments returns every environment name the SDK understands.
func SupportedEnvironments() []Environment {
	return []Environment{EnvironmentProduction}
}

// BaseURLForEnvironment returns the base URL for a named environment.
func BaseURLForEnvironment(environment Environment) (string, error) {
	baseURL, ok := baseURLs[environment]
	if !ok {
		return "", &ConfigurationError{msg: fmt.Sprintf(
			"unknown environment %q; supported: %s; use WithBaseURL to target a host that is not a named environment",
			string(environment), joinEnvironments(SupportedEnvironments()))}
	}

	return baseURL, nil
}

func joinEnvironments(environments []Environment) string {
	joined := ""

	for i, environment := range environments {
		if i > 0 {
			joined += ", "
		}

		joined += string(environment)
	}

	return joined
}
