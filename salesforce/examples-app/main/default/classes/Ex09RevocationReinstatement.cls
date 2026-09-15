/**
 * EX-09 — Revocation followed by reinstatement.
 *
 * A revoked organization can get its exemption back, and the record then carries
 * both dates. Reading only `revocation_date` turns a currently-exempt charity
 * into a rejection.
 */
@IsTest
private class Ex09RevocationReinstatement {
    @IsTest
    static void readsBothDatesTogether() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Test.startTest();

        for (
            String ein : new List<String>{ ExampleFixtures.REVOKED, ExampleFixtures.REINSTATED }
        ) {
            Nonprofit nonprofit = ExampleApiMock.client().nonprofits.check(ein).nonprofit;
            AroeSource aroe = Sources.getAroe(nonprofit);

            ExampleOutput.heading(nonprofit.organization_name + ' (' + ein + ')');
            ExampleOutput.field('revocation_date', aroe.revocation_date);
            ExampleOutput.field('reinstatement_date', aroe.reinstatement_date);
            ExampleOutput.field(
                'revoked and not reinstated',
                ExampleScreening.revokedAndNotReinstated(nonprofit)
            );
            ExampleOutput.field('revoked', daysAgo(aroe.revocation_date));
            ExampleOutput.field('reinstated', daysAgo(aroe.reinstatement_date));

            // Both records carry a revocation date. Only one of them is still
            // revoked, and the fields that say so are the current status
            // fields, not the historical one.
            ExampleOutput.field('pub78_verified', nonprofit.pub78_verified);
            ExampleOutput.field('bmf_status', nonprofit.bmf_status);
        }

        Nonprofit stillRevoked = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.REVOKED)
            .nonprofit;
        Nonprofit reinstated = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.REINSTATED)
            .nonprofit;

        Test.stopTest();

        // The historical field is identical in shape on both records.
        Assert.isNotNull(Sources.getAroe(stillRevoked).revocation_date);
        Assert.isNotNull(Sources.getAroe(reinstated).revocation_date);

        // The current status is not.
        Assert.isTrue(ExampleScreening.revokedAndNotReinstated(stillRevoked));
        Assert.isFalse(
            ExampleScreening.revokedAndNotReinstated(reinstated),
            'A rule that reads revocation_date alone would reject a currently-exempt charity.'
        );
        Assert.areEqual(true, reinstated.bmf_status);
        Assert.areEqual(true, reinstated.pub78_verified);

        ExampleOutput.note(
            'Both organizations were revoked. One of them is exempt today. A rule that\n' +
            'reads revocation_date alone rejects both - and the reinstated one has been back\n' +
            'in good standing for years. Read the pair, and prefer the current status fields\n' +
            'for the current question.'
        );
    }

    private static String daysAgo(String value) {
        Integer age = ExampleDates.ageInDays(value);

        return age == null ? null : age + ' days ago';
    }
}
