package org.pactman.nonprofitcheckplus.examples.support;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import org.pactman.nonprofitcheckplus.examples.cases.Bulk;
import org.pactman.nonprofitcheckplus.examples.cases.ErrorHandling;
import org.pactman.nonprofitcheckplus.examples.cases.Ex01SecureClientInit;
import org.pactman.nonprofitcheckplus.examples.cases.Ex02EinNormalization;
import org.pactman.nonprofitcheckplus.examples.cases.Ex03IdentityLookup;
import org.pactman.nonprofitcheckplus.examples.cases.Ex04NameComparison;
import org.pactman.nonprofitcheckplus.examples.cases.Ex05AddressValidation;
import org.pactman.nonprofitcheckplus.examples.cases.Ex06BmfStatus;
import org.pactman.nonprofitcheckplus.examples.cases.Ex07Pub78Deductibility;
import org.pactman.nonprofitcheckplus.examples.cases.Ex08AutomaticRevocation;
import org.pactman.nonprofitcheckplus.examples.cases.Ex09RevocationReinstatement;
import org.pactman.nonprofitcheckplus.examples.cases.Ex10OfacScreening;
import org.pactman.nonprofitcheckplus.examples.cases.Ex11SourceConflict;
import org.pactman.nonprofitcheckplus.examples.cases.Ex12FoundationClassification;
import org.pactman.nonprofitcheckplus.examples.cases.Ex13FilingExemptionMetadata;
import org.pactman.nonprofitcheckplus.examples.cases.Ex14DataFreshness;
import org.pactman.nonprofitcheckplus.examples.cases.Ex15MalformedEin;
import org.pactman.nonprofitcheckplus.examples.cases.Ex16NotFound;
import org.pactman.nonprofitcheckplus.examples.cases.Ex17BulkScreening;
import org.pactman.nonprofitcheckplus.examples.cases.Ex18BulkOrderAndDuplicates;
import org.pactman.nonprofitcheckplus.examples.cases.Ex19BulkPartialSuccess;
import org.pactman.nonprofitcheckplus.examples.cases.Ex20BulkBatchLimits;
import org.pactman.nonprofitcheckplus.examples.cases.Ex21UsageTracking;
import org.pactman.nonprofitcheckplus.examples.cases.Ex22RateLimit;
import org.pactman.nonprofitcheckplus.examples.cases.Ex23TransientRetries;
import org.pactman.nonprofitcheckplus.examples.cases.Ex24TimeoutAndCancellation;
import org.pactman.nonprofitcheckplus.examples.cases.Ex25RawAndForwardCompat;
import org.pactman.nonprofitcheckplus.examples.cases.Ex26OnboardingWorkflow;
import org.pactman.nonprofitcheckplus.examples.cases.Ex27DafGrantScreening;
import org.pactman.nonprofitcheckplus.examples.cases.Ex28CrmEnrichment;
import org.pactman.nonprofitcheckplus.examples.cases.Ex29PreDisbursementRecheck;
import org.pactman.nonprofitcheckplus.examples.cases.Ex30PortfolioReverification;
import org.pactman.nonprofitcheckplus.examples.cases.Quickstart;

/**
 * Every runnable example, in the order the README presents them.
 *
 * <p>Listed rather than discovered by reflection: a list is what a reader can
 * check against the README, and it fails to compile when an example is renamed
 * instead of silently going missing from the smoke run.
 */
public final class Catalog {

    private static final List<Example> EXAMPLES = Collections.unmodifiableList(Arrays.asList(
            new Quickstart(),
            new Ex01SecureClientInit(),
            new Ex02EinNormalization(),
            new Ex03IdentityLookup(),
            new Ex04NameComparison(),
            new Ex05AddressValidation(),
            new Ex06BmfStatus(),
            new Ex07Pub78Deductibility(),
            new Ex08AutomaticRevocation(),
            new Ex09RevocationReinstatement(),
            new Ex10OfacScreening(),
            new Ex11SourceConflict(),
            new Ex12FoundationClassification(),
            new Ex13FilingExemptionMetadata(),
            new Ex14DataFreshness(),
            new Ex15MalformedEin(),
            new Ex16NotFound(),
            new Ex17BulkScreening(),
            new Ex18BulkOrderAndDuplicates(),
            new Ex19BulkPartialSuccess(),
            new Ex20BulkBatchLimits(),
            new Ex21UsageTracking(),
            new Ex22RateLimit(),
            new Ex23TransientRetries(),
            new Ex24TimeoutAndCancellation(),
            new Ex25RawAndForwardCompat(),
            new Ex26OnboardingWorkflow(),
            new Ex27DafGrantScreening(),
            new Ex28CrmEnrichment(),
            new Ex29PreDisbursementRecheck(),
            new Ex30PortfolioReverification(),
            new Bulk(),
            new ErrorHandling()));

    private Catalog() {
    }

    /**
     * Every example.
     *
     * @return the catalog.
     */
    public static List<Example> all() {
        return EXAMPLES;
    }

    /**
     * One example by id.
     *
     * @param id the identifier, such as {@code ex-01}.
     * @return the example, or {@code null} when there is none.
     */
    public static Example byId(String id) {
        for (Example example : EXAMPLES) {
            if (example.id().equalsIgnoreCase(id)) {
                return example;
            }
        }

        return null;
    }
}
