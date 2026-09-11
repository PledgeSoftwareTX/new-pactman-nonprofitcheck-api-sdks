package org.pactman.nonprofitcheckplus.examples.cases;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.devtools.Fixtures;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.examples.support.ExampleFailedException;
import org.pactman.nonprofitcheckplus.examples.support.Output;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.OrganizationType;
import org.pactman.nonprofitcheckplus.models.SingleCheckResult;

/**
 * EX-25 — Raw access and forward compatibility.
 *
 * <p>An API that adds a field should not break an SDK that has never heard of
 * it. This example reads two records the typed accessors cannot fully describe:
 * one from a newer API version, and one from a deployment running ahead of
 * production.
 */
public final class Ex25RawAndForwardCompat implements Example {

    @Override
    public String id() {
        return "ex-25";
    }

    @Override
    public String title() {
        return "Reading fields this SDK version has never heard of";
    }

    @Override
    public void run(String[] args) {
        Set<String> known = Fixtures.knownNonprofitFields();

        try (ExampleContext context = ExampleContext.withFixtures()) {
            for (String ein : new String[] {
                FixtureEins.FUTURE_FIELDS, FixtureEins.PENDING_SOURCE_FIELDS
            }) {
                SingleCheckResult result = context.client().nonprofits().check(ein);
                Nonprofit nonprofit = result.getNonprofit();

                Output.heading(nonprofit.getOrganizationName() + " (" + ein + ")");
                Output.field("fields returned", nonprofit.size());
                Output.field("fields this SDK predicts", known.size());

                List<String> unpredicted = new ArrayList<>();

                for (String field : nonprofit.fieldNames()) {
                    if (!known.contains(field)) {
                        unpredicted.add(field);
                    }
                }

                System.out.println();

                if (unpredicted.isEmpty()) {
                    Output.bullet("nothing outside the contract");
                }

                for (String field : unpredicted) {
                    // Deserialization did not fail, and the value did not vanish.
                    Output.bullet(field + " = " + Output.render(nonprofit.get(field)));
                }

                if (unpredicted.isEmpty()) {
                    throw new ExampleFailedException(
                            "This fixture should carry fields outside the contract.");
                }
            }

            Output.heading("An unknown member inside a known object");

            Nonprofit future = context.client()
                    .nonprofits()
                    .check(FixtureEins.FUTURE_FIELDS)
                    .getNonprofit();

            for (OrganizationType type : future.getOrganizationTypes()) {
                Output.field("deductibility_limitation", type.getDeductibilityLimitation());
                Output.field(
                        "deductibility_status_description",
                        type.getDeductibilityStatusDescription());
                Output.field(
                        "future_deductibility_note", type.get("future_deductibility_note"));
            }

            Output.heading("An enum value outside the documented set");
            Output.field("foundation_type_code", future.getFoundationTypeCode());
            Output.field("foundation_type_description", future.getFoundationTypeDescription());

            Output.heading("The whole envelope, unmodified");

            Map<String, Object> envelope = context.client()
                    .nonprofits()
                    .check(FixtureEins.PENDING_SOURCE_FIELDS)
                    .getRaw()
                    .toMap();

            Output.field("envelope keys", new ArrayList<>(envelope.keySet()));
        }

        Output.note("The second record is a deployment ahead of production: it carries the ten\n"
                + "source fields that are built but not yet released there. This SDK does not\n"
                + "declare them, on purpose — declaring a field production does not return\n"
                + "would promise something the API does not keep. They stay readable through\n"
                + "get(...) and the raw envelope until a release declares them.\n\n"
                + "Nothing about an unpredicted field is an error. It is worth logging, because\n"
                + "it is how you find out the API moved before your SDK did.");
    }
}
