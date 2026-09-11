package org.pactman.nonprofitcheckplus.examples.cases;

import org.pactman.nonprofitcheckplus.Sources;
import org.pactman.nonprofitcheckplus.devtools.FixtureEins;
import org.pactman.nonprofitcheckplus.examples.support.Example;
import org.pactman.nonprofitcheckplus.examples.support.ExampleContext;
import org.pactman.nonprofitcheckplus.models.BmfSource;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.OfacSource;
import org.pactman.nonprofitcheckplus.models.Pub78Source;
import org.pactman.nonprofitcheckplus.models.SingleCheckResult;

/**
 * Minimal single nonprofit check.
 *
 * <p>The key is read from the environment. Never hard-code it, and never run
 * this inside an artifact that ships to a user — the key is a private
 * server-side credential.
 */
public final class Quickstart implements Example {

    @Override
    public String id() {
        return "quickstart";
    }

    @Override
    public String title() {
        return "The smallest useful lookup";
    }

    @Override
    public void run(String[] args) {
        String ein = args.length > 0 ? args[0] : FixtureEins.PUBLIC_CHARITY;

        try (ExampleContext context = ExampleContext.withFixtures()) {
            SingleCheckResult result = context.client().nonprofits().check(ein);

            if (result.getNonprofit() == null) {
                System.out.println("No record for EIN " + ein + ".");
                return;
            }

            Nonprofit nonprofit = result.getNonprofit();

            System.out.println("Organization : " + nonprofit.getOrganizationName());
            System.out.println("EIN          : " + nonprofit.getEin());
            System.out.println("Location     : " + nonprofit.getCity() + ", " + nonprofit.getState());
            System.out.println("Profile      : " + nonprofit.getPactmanOrgUrl());
            System.out.println("Checks used  : " + result.getCheckCount());

            // Three source-specific findings, read straight from the response.
            Pub78Source pub78 = Sources.pub78(nonprofit);
            BmfSource bmf = Sources.bmf(nonprofit);
            OfacSource ofac = Sources.ofac(nonprofit);

            System.out.println();
            System.out.println("IRS Publication 78");
            System.out.println(pub78 == null
                    ? "  not returned"
                    : "  listed: " + pub78.getVerified() + ", as of " + pub78.getMostRecent());

            System.out.println();
            System.out.println("IRS Business Master File");
            System.out.println(bmf == null
                    ? "  not returned"
                    : "  status: " + bmf.getStatus()
                            + ", subsection: " + bmf.getSubsectionDescription());

            System.out.println();
            System.out.println("OFAC");
            System.out.println(ofac == null ? "  not returned" : "  " + ofac.getStatus());
        }

        // A syntactically valid EIN and a clean set of findings are not an
        // eligibility decision. Apply your own grantmaking, compliance and risk
        // policy.
    }
}
