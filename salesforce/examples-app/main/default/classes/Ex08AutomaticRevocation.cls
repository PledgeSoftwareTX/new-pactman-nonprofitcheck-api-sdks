/**
 * EX-08 — The Automatic Revocation of Exemption list.
 *
 * An organization that fails to file for three consecutive years loses its
 * exemption automatically. The revocation fields say so, and they say it
 * independently of what the BMF and Publication 78 report.
 */
@IsTest
private class Ex08AutomaticRevocation {
    @IsTest
    static void readsRevocationAcrossEverySource() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Test.startTest();

        for (
            String ein : new List<String>{ ExampleFixtures.PUBLIC_CHARITY, ExampleFixtures.REVOKED }
        ) {
            Nonprofit nonprofit = ExampleApiMock.client().nonprofits.check(ein).nonprofit;
            AroeSource aroe = Sources.getAroe(nonprofit);

            ExampleOutput.heading(nonprofit.organization_name + ' (' + ein + ')');

            if (aroe == null) {
                ExampleOutput.bullet('The API returned no revocation data at all.');
                continue;
            }

            ExampleOutput.field('revocation_code', aroe.revocation_code);
            ExampleOutput.field(
                '  meaning',
                ExampleIrsCodes.describeRevocationCode(aroe.revocation_code)
            );
            ExampleOutput.field('revocation_date', aroe.revocation_date);
            ExampleOutput.field('reinstatement_date', aroe.reinstatement_date);

            // The other sources agree here, and that is worth showing: a
            // revocation is visible in three places, and a workflow that reads
            // only one of them is one API change from missing it.
            ExampleOutput.field('pub78_verified', nonprofit.pub78_verified);
            ExampleOutput.field('bmf_status', nonprofit.bmf_status);
            ExampleOutput.field('exempt_status_code', nonprofit.exempt_status_code);
            ExampleOutput.field(
                '  meaning',
                ExampleIrsCodes.describeExemptStatus(nonprofit.exempt_status_code)
            );
        }

        Nonprofit revoked = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.REVOKED)
            .nonprofit;

        Test.stopTest();

        Assert.isTrue(
            ExampleScreening.revokedAndNotReinstated(revoked),
            'A revocation date with no reinstatement date is the state worth acting on.'
        );
        Assert.areEqual('25', revoked.exempt_status_code);
        Assert.areEqual(
            'Exemption automatically revoked for failure to file',
            ExampleIrsCodes.describeExemptStatus(revoked.exempt_status_code)
        );

        ExampleOutput.note(
            'A revocation date with no reinstatement date is the state worth acting on.\n' +
            'The next example shows why the reinstatement date is not optional reading.'
        );
    }
}
