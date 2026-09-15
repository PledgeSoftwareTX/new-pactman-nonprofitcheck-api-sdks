/**
 * EX-06 — Reading the IRS Business Master File finding.
 *
 * `bmf_status` is the closest thing the API has to "the IRS lists this
 * organization as exempt". It is still one source among four, and it has three
 * states, not two — which is why the accessor returns a `Boolean` that can be
 * null rather than a primitive `boolean`.
 */
@IsTest
private class Ex06BmfStatus {
    @IsTest
    static void readsAllThreeStatesOfBmfStatus() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Test.startTest();

        for (
            String ein : new List<String>{ ExampleFixtures.PUBLIC_CHARITY, ExampleFixtures.REVOKED }
        ) {
            Nonprofit nonprofit = ExampleApiMock.client().nonprofits.check(ein).nonprofit;
            BmfSource bmf = Sources.getBmf(nonprofit);

            ExampleOutput.heading(nonprofit.organization_name + ' (' + ein + ')');

            if (bmf == null) {
                ExampleOutput.bullet('The API returned no Business Master File data at all.');
                continue;
            }

            ExampleOutput.field('status', bmf.status);
            ExampleOutput.field('subsection', bmf.subsection);
            ExampleOutput.field('subsection_description', bmf.subsection_description);
            ExampleOutput.field('exempt_status_code', bmf.exempt_status_code);
            ExampleOutput.field(
                '  meaning',
                ExampleIrsCodes.describeExemptStatus(bmf.exempt_status_code)
            );
            ExampleOutput.field('ruling', bmf.ruling_month + '/' + bmf.ruling_year);
            ExampleOutput.field('most_recent_bmf', bmf.most_recent);
        }

        Nonprofit exemptOrg = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.PUBLIC_CHARITY)
            .nonprofit;
        Nonprofit revokedOrg = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.REVOKED)
            .nonprofit;

        Test.stopTest();

        Assert.areEqual(true, Sources.getBmf(exemptOrg).status, 'The BMF lists this one as exempt.');
        Assert.areEqual(
            false,
            Sources.getBmf(revokedOrg).status,
            'The BMF has a record for this one and it is not exempt.'
        );

        ExampleOutput.note(
            'bmf_status has three states, and a boolean cast collapses one of them:\n' +
            '  true  - the BMF lists the organization as exempt\n' +
            '  false - the BMF has a record and it is not exempt\n' +
            '  null  - the BMF said nothing either way\n\n' +
            'Only the first is a positive finding. Treating null as false invents a\n' +
            'negative the IRS never gave you, which is why `bmf.status != true` is the\n' +
            'safe test and `!bmf.status` is not — the latter throws on null in Apex.'
        );
    }
}
