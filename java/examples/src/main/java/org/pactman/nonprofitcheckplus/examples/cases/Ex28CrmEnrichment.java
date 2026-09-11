package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.models.BulkCheckResult;
import org.pactman.nonprofitcheckplus.models.Nonprofit;

/**
 * EX-28 — Enriching CRM records.
 *
 * <p>Writing API values into your own database is where "null" and "not
 * returned" stop being an academic distinction: overwriting a good local value
 * with a null the API happened not to return is data loss, and it is silent.
 */
public final class Ex28CrmEnrichment implements Example {

    @Override
    public String id() {
        return "ex-28";
    }

    @Override
    public String title() {
        return "CRM enrichment without overwriting good data with nulls";
    }

    @Override
    public void run(String[] args) {
        // What the CRM holds today. The second row has a hand-entered address
        // that the IRS record does not carry.
        Map<String, Map<String, String>> crm = new LinkedHashMap<>();
        crm.put(FixtureEins.PUBLIC_CHARITY, row("Meals Today", "50 Lowell Ave", "01085"));
        crm.put(FixtureEins.SPARSE_IDENTITY, row("Quiet Harbor Trust", "PO Box 118", "04856"));

        List<String> eins = new ArrayList<>(crm.keySet());

        try (ExampleContext context = ExampleContext.withFixtures()) {
            BulkCheckResult result = context.client().nonprofits().checkBulk(eins);

            Map<String, Nonprofit> byEin = new LinkedHashMap<>();

            for (Nonprofit organization : result.getOrganizations()) {
                byEin.put(organization.getEin(), organization);
            }

            for (String ein : eins) {
                Nonprofit nonprofit = byEin.get(ein);
                Map<String, String> row = crm.get(ein);

                Output.heading(row.get("name") + " (" + ein + ")");

                if (nonprofit == null) {
                    Output.bullet("No record returned. Nothing is written; the row is untouched.");
                    continue;
                }

                for (String[] mapping : new String[][] {
                    {"name", "organization_name"},
                    {"street", "address_line1"},
                    {"zip", "zip"},
                }) {
                    String column = mapping[0];
                    String field = mapping[1];
                    String current = row.get(column);

                    // Three cases, and only one of them is a write.
                    if (!nonprofit.has(field)) {
                        Output.field(column, "kept \"" + current + "\" — API returned no field");
                        continue;
                    }

                    Object value = nonprofit.get(field);

                    if (value == null) {
                        Output.field(column, "kept \"" + current + "\" — API returned null");
                        continue;
                    }

                    row.put(column, String.valueOf(value));
                    Output.field(column, "updated to \"" + value + "\"");
                }

                // A provenance stamp is what makes the next run able to tell a
                // stale value from a fresh one.
                row.put("verified_from", "pactman");
                row.put("verified_at", nonprofit.getReportDate());
                Output.field("verified_at", row.get("verified_at"));
            }
        }

        Output.note("The rule is one line: write when the API returned a value, keep what you\n"
                + "have when it returned null or nothing at all. has(field) is what makes that\n"
                + "expressible — without it, both cases read as null and the second row loses a\n"
                + "hand-entered ZIP to a field the IRS extract simply does not carry.\n\n"
                + "Storing these records may bring retention and privacy obligations of your\n"
                + "own. That is your call, not the SDK's.");
    }

    private static Map<String, String> row(String name, String street, String zip) {
        Map<String, String> row = new LinkedHashMap<>();
        row.put("name", name);
        row.put("street", street);
        row.put("zip", zip);

        return row;
    }
}
