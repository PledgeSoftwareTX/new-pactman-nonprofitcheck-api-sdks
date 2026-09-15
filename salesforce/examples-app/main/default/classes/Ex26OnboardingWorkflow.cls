/**
 * EX-26 — Onboarding a nonprofit to a giving platform.
 *
 * An applicant types a name and an EIN. This workflow decides one thing: whether
 * a human needs to look at the application. It never decides whether the
 * organization is legitimate.
 */
@IsTest
private class Ex26OnboardingWorkflow {
    @IsTest
    static void routesApplicationsToProceedOrToAReviewer() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        // One applicant, as they typed it.
        Map<String, String> applicants = new Map<String, String>{
            ExampleFixtures.PUBLIC_CHARITY => 'Meals Today Example Nonprofit Inc.',
            ExampleFixtures.REVOKED => 'Lapsed Filings Example Society',
            ExampleFixtures.INCONSISTENT_ADDRESS => 'Harbour Light Example Alliance',
            ExampleFixtures.NO_RECORD => 'Brand New Example Charity'
        };

        Map<String, String> routing = new Map<String, String>();

        Test.startTest();

        for (String ein : applicants.keySet()) {
            String typedName = applicants.get(ein);

            ExampleOutput.heading(typedName + ' (' + ein + ')');

            Nonprofit nonprofit;

            try {
                nonprofit = ExampleApiMock.client().nonprofits.check(ein).nonprofit;
            } catch (NotFoundException noRecord) {
                ExampleOutput.bullet('No IRS record for this EIN.');
                routing.put(ein, 'MANUAL REVIEW');
                ExampleOutput.field(
                    'routing',
                    'MANUAL REVIEW - cannot verify without a record'
                );
                continue;
            }

            String nameCheck = ExampleMatching.compareNames(typedName, nonprofit.organization_name);
            List<String> screening = ExampleScreening.findings(nonprofit);
            List<String> address = ExampleAddresses.findings(nonprofit);

            ExampleOutput.field('IRS name', nonprofit.organization_name);
            ExampleOutput.field('name comparison', nameCheck);

            for (String finding : screening) {
                ExampleOutput.bullet(finding);
            }

            for (String finding : address) {
                ExampleOutput.bullet(finding);
            }

            // The policy, stated in one place so that it can be argued with.
            Boolean needsReview =
                nameCheck != ExampleMatching.AGREE ||
                !screening.isEmpty() ||
                !address.isEmpty();

            routing.put(ein, needsReview ? 'MANUAL REVIEW' : 'PROCEED');
            ExampleOutput.field(
                'routing',
                needsReview ? 'MANUAL REVIEW' : 'PROCEED under this platform\'s policy'
            );
        }

        Test.stopTest();

        Assert.areEqual(
            'PROCEED',
            routing.get(ExampleFixtures.PUBLIC_CHARITY),
            'A clean record with a matching name needs no human.'
        );
        Assert.areEqual('MANUAL REVIEW', routing.get(ExampleFixtures.REVOKED));
        Assert.areEqual(
            'MANUAL REVIEW',
            routing.get(ExampleFixtures.INCONSISTENT_ADDRESS),
            'The name matches; the address contradicts itself.'
        );
        Assert.areEqual(
            'MANUAL REVIEW',
            routing.get(ExampleFixtures.NO_RECORD),
            'A missing record asks for a human, not a rejection.'
        );

        ExampleOutput.note(
            'Every branch above is this platform\'s policy, not the SDK\'s and not the\n' +
            'API\'s. A different platform reading identical responses would route them\n' +
            'differently and would also be right.\n\n' +
            'Note what the workflow does with a missing record: it asks for a human, not a\n' +
            'rejection. Absence of a record is not evidence of anything.\n\n' +
            'In a real org this runs from a Queueable, not a trigger: callouts are illegal\n' +
            'from a trigger and after DML in the same transaction. See CheckQueueable.'
        );
    }
}
