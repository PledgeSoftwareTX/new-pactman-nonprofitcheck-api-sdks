// EX-28 — Enriching CRM records.
//
// Writing API values into your own database is where "null" and "not returned"
// stop being an academic distinction: overwriting a good local value with a null
// the API happened not to return is data loss, and it is silent.
//
//	go run ./examples/ex-28-crm-enrichment
package main

import (
	"context"

	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/examples/internal/support"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/internal/mockapi"
	"github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go/pactman"
)

// row is what the CRM holds for one organization.
type row struct {
	name         string
	street       string
	zip          string
	verifiedFrom string
	verifiedAt   string
}

func main() {
	ctx := context.Background()

	// The second row has a hand-entered address the IRS record does not carry.
	crm := map[string]*row{
		mockapi.PublicCharity:  {name: "Meals Today", street: "50 Lowell Ave", zip: "01085"},
		mockapi.SparseIdentity: {name: "Quiet Harbor Trust", street: "PO Box 118", zip: "04856"},
	}

	// A map has no order; the EIN list is what fixes the order of the output.
	eins := []string{mockapi.PublicCharity, mockapi.SparseIdentity}

	example := support.WithFixtures()

	defer example.Close()

	result, err := example.Nonprofits().CheckBulk(ctx, eins)
	support.Must(err)

	byEIN := map[string]*pactman.Nonprofit{}

	for _, organization := range result.Organizations {
		if organization.EIN != nil {
			byEIN[*organization.EIN] = organization
		}
	}

	for _, ein := range eins {
		record := crm[ein]
		nonprofit, ok := byEIN[ein]

		support.Heading(record.name + " (" + ein + ")")

		if !ok {
			support.Bullet("No record returned. Nothing is written; the row is untouched.")

			continue
		}

		columns := []struct {
			label   string
			field   string
			current *string
		}{
			{"name", "organization_name", &record.name},
			{"street", "address_line1", &record.street},
			{"zip", "zip", &record.zip},
		}

		for _, column := range columns {
			// Three cases, and only one of them is a write.
			if !nonprofit.Fields.Has(column.field) {
				support.Field(column.label,
					"kept \""+*column.current+"\" — API returned no field")

				continue
			}

			if nonprofit.Fields.IsNull(column.field) {
				support.Field(column.label,
					"kept \""+*column.current+"\" — API returned null")

				continue
			}

			value := support.Render(support.Present(nonprofit.Fields, column.field))
			*column.current = value

			support.Field(column.label, "updated to \""+value+"\"")
		}

		// A provenance stamp is what makes the next run able to tell a stale
		// value from a fresh one.
		record.verifiedFrom = "pactman"
		record.verifiedAt = support.Text(nonprofit.ReportDate)

		support.Field("verified_from", record.verifiedFrom)
		support.Field("verified_at", record.verifiedAt)
	}

	support.Heading("The rows after the sync")

	for _, ein := range eins {
		record := crm[ein]
		support.Field(ein, record.name+" | "+record.street+" | "+record.zip)
	}

	if crm[mockapi.SparseIdentity].zip != "04856" {
		support.Fail("A null from the API must not erase a hand-entered ZIP.")
	}

	support.Note("The rule is one line: write when the API returned a value, keep what you have\n" +
		"when it returned null or nothing at all. Fields.Has and Fields.IsNull are what\n" +
		"make that expressible — without them both cases read as nil, and the second row\n" +
		"loses a hand-entered ZIP to a field the IRS extract simply does not carry.\n\n" +
		"Storing these records may bring retention and privacy obligations of your own.\n" +
		"That is your call, not the SDK's.")
}
