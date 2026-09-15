/**
 * EX-11 — When the sources disagree.
 *
 * The BMF and Publication 78 are separate IRS extracts, published on different
 * schedules. They can disagree, and the API says so with
 * `irs_bmf_pub78_conflict` rather than picking a winner. Neither should this
 * SDK, and neither should a workflow that silently prefers one.
 */
@IsTest
private class Ex11SourceConflict {
    @IsTest
    static void recordsBothSourcesRatherThanChoosing() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Test.startTest();

        for (
            String ein : new List<String>{
                ExampleFixtures.PUBLIC_CHARITY, ExampleFixtures.CONFLICTED
            }
        ) {
            Nonprofit nonprofit = ExampleApiMock.client().nonprofits.check(ein).nonprofit;
            Pub78Source pub78 = Sources.getPub78(nonprofit);
            BmfSource bmf = Sources.getBmf(nonprofit);

            ExampleOutput.heading(nonprofit.organization_name + ' (' + ein + ')');
            ExampleOutput.field('irs_bmf_pub78_conflict', nonprofit.irs_bmf_pub78_conflict);

            if (bmf == null) {
                ExampleOutput.field('Business Master File', ExampleOutput.ABSENT);
            } else {
                ExampleOutput.field('bmf_status', bmf.status);
                ExampleOutput.field('bmf_organization_name', bmf.organization_name);
                ExampleOutput.field('most_recent_bmf', bmf.most_recent);
            }

            if (pub78 == null) {
                ExampleOutput.field('Publication 78', ExampleOutput.ABSENT);
            } else {
                ExampleOutput.field('pub78_verified', pub78.verified);
                ExampleOutput.field('pub78_organization_name', pub78.organization_name);
                ExampleOutput.field('most_recent_pub78', pub78.most_recent);
            }
        }

        Nonprofit conflicted = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.CONFLICTED)
            .nonprofit;

        Test.stopTest();

        // Both statements came from the IRS. The API reports the disagreement;
        // it does not resolve it, and neither does the SDK.
        Assert.areEqual(true, conflicted.irs_bmf_pub78_conflict);
        Assert.areEqual(true, conflicted.bmf_status, 'The BMF says exempt.');
        Assert.areEqual(false, conflicted.pub78_verified, 'Publication 78 does not list it.');

        ExampleOutput.note(
            'The second organization is exempt according to the BMF and unlisted according\n' +
            'to Publication 78. Both statements came from the IRS. The API flags the\n' +
            'disagreement; what to do about it is your policy:\n\n' +
            '  - a donation platform might accept the BMF and note the conflict\n' +
            '  - a DAF issuing a grant might hold it for review\n' +
            '  - a tax-receipt flow cares specifically about Publication 78\n\n' +
            'All three are right for their own obligations, which is exactly why the SDK\n' +
            'does not choose. Compare ex-26 and ex-27, which read this same record and\n' +
            'reach different conclusions.'
        );
    }
}
