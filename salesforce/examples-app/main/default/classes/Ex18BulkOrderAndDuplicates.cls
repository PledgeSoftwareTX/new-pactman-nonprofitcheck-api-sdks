/**
 * EX-18 — Ordering and duplicates in a bulk request.
 *
 * The one pairing rule that always holds: index the response by EIN. The API
 * matches by set membership, so it neither preserves your order nor returns a
 * repeated EIN twice. `byEin()` exists so that you never have to remember this
 * at the call site.
 */
@IsTest
private class Ex18BulkOrderAndDuplicates {
    @IsTest
    static void pairsByEinRatherThanByPosition() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        List<String> requested = new List<String>{
            ExampleFixtures.PUBLIC_CHARITY_SECOND,
            ExampleFixtures.PUBLIC_CHARITY,
            ExampleFixtures.PUBLIC_CHARITY_SECOND
        };

        Test.startTest();
        BulkCheckResult asSupplied = ExampleApiMock.client().nonprofits.checkBulk(requested);

        BulkCheckResult deduped = ExampleApiMock.client()
            .nonprofits.checkBulk(requested, new RequestOptions().withDedupe(true));
        Test.stopTest();

        ExampleOutput.heading('Duplicates are sent as supplied');
        ExampleOutput.field('requested', requested);
        ExampleOutput.field('organizations returned', asSupplied.organizations.size());

        List<String> returned = new List<String>();

        for (Nonprofit organization : asSupplied.organizations) {
            returned.add(organization.ein);
        }

        ExampleOutput.field('EINs returned', returned);

        ExampleOutput.heading('Deduplicating before sending');
        ExampleOutput.field('organizations returned', deduped.organizations.size());

        Assert.areEqual(3, requested.size());
        Assert.areEqual(
            2,
            asSupplied.organizations.size(),
            'The API collapses the repeated EIN into one record.'
        );

        // Pairing positionally would have attributed the second
        // organization's findings to the third row. byEin() cannot make that
        // mistake.
        Map<String, Nonprofit> byEin = asSupplied.byEin();

        Assert.areEqual(2, byEin.size());
        Assert.areEqual(
            ExampleFixtures.PUBLIC_CHARITY,
            byEin.get(ExampleFixtures.PUBLIC_CHARITY).ein
        );
        Assert.areEqual(
            ExampleFixtures.PUBLIC_CHARITY_SECOND,
            byEin.get(ExampleFixtures.PUBLIC_CHARITY_SECOND).ein
        );

        Assert.areEqual(
            2,
            deduped.organizations.size(),
            'Deduplicating changes what is sent and billed, not what comes back.'
        );

        ExampleOutput.note(
            'Three EINs went out and two records came back, because the API matches by set\n' +
            'membership. Pairing the response with the request by position would have\n' +
            'attributed the second organization\'s findings to the third row.\n\n' +
            'Duplicates are sent as supplied by default, because each one is billable and\n' +
            'silently dropping them would misreport what was checked.\n' +
            'new RequestOptions().withDedupe(true) is the opt-in, and it is the right call\n' +
            'when your input is a report nobody cleaned.'
        );
    }
}
