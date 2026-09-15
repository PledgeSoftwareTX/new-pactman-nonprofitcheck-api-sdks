/**
 * EX-17 — Screening a batch in one request.
 *
 * One bulk call instead of a loop of single checks. In Apex the saving is not
 * just latency: a loop of fifty single checks spends fifty of the transaction's
 * 100 callouts, and one bulk call spends one.
 */
@IsTest
private class Ex17BulkScreening {
    @IsTest
    static void screensAGranteeListInOneRequest() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        List<String> eins = new List<String>{
            ExampleFixtures.PUBLIC_CHARITY,
            ExampleFixtures.PUBLIC_CHARITY_SECOND,
            ExampleFixtures.REVOKED,
            ExampleFixtures.OFAC_MATCH,
            ExampleFixtures.CONFLICTED
        };

        Test.startTest();
        BulkCheckResult result = ExampleApiMock.client().nonprofits.checkBulk(eins);
        // Read inside the block: Test.stopTest() restores the limits the
        // enclosing context had, so a count taken after it measures nothing.
        Integer calloutsUsed = Limits.getCallouts();
        Test.stopTest();

        ExampleOutput.heading('What came back');
        ExampleOutput.field('requested', eins.size());
        ExampleOutput.field('organizations', result.organizations.size());
        ExampleOutput.field('notFoundEins', result.notFoundEins);
        ExampleOutput.field('checkCount', result.checkCount);
        ExampleOutput.field('callouts used', calloutsUsed);

        // The response is not ordered to match the request, so pair by EIN.
        // Never by position.
        Map<String, Nonprofit> byEin = result.byEin();

        for (String ein : eins) {
            Nonprofit organization = byEin.get(ein);

            if (organization == null) {
                ExampleOutput.heading(ein + ' - no record');
                continue;
            }

            ExampleOutput.heading(ein + ' - ' + organization.organization_name);

            List<String> findings = ExampleScreening.findings(organization);

            if (findings.isEmpty()) {
                ExampleOutput.bullet('nothing to report');
            }

            for (String finding : findings) {
                ExampleOutput.bullet(finding);
            }
        }

        Assert.areEqual(5, result.organizations.size(), 'Every EIN here has a record.');
        Assert.areEqual(0, result.notFoundEins.size());
        Assert.areEqual(1, calloutsUsed, 'Five organizations, one callout.');

        // Two of the five are clean and three carry findings. None of that is a
        // decision.
        Assert.areEqual(
            0,
            ExampleScreening.findings(byEin.get(ExampleFixtures.PUBLIC_CHARITY)).size()
        );
        Assert.isFalse(
            ExampleScreening.findings(byEin.get(ExampleFixtures.REVOKED)).isEmpty()
        );

        ExampleOutput.note(
            'The findings above are what the API said. Not one of them is a decision: no\n' +
            'approved, no eligible, no safe. Which of them stops a payment is your policy,\n' +
            'and ex-26 to ex-30 show four workflows reading the same evidence and reaching\n' +
            'different, defensible conclusions.'
        );
    }
}
