/**
 * Quickstart — the smallest useful lookup.
 *
 * In a subscriber org the key lives in the External Credential behind the
 * Named Credential, so `new Client()` is the whole setup and Apex never sees
 * the key. Here the client points at the bundled mock instead.
 */
@IsTest
private class Quickstart {
    @IsTest
    static void checksOneNonprofit() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        String ein = '41-1787097';

        Test.startTest();
        SingleCheckResult result = ExampleApiMock.client().nonprofits.check(ein);
        Test.stopTest();

        if (result.nonprofit == null) {
            ExampleOutput.note('No record for EIN ' + ein + '.');
            Assert.fail('The fixture API holds a record for ' + ein + '.');
        }

        Nonprofit nonprofit = result.nonprofit;

        ExampleOutput.field('Organization', nonprofit.organization_name);
        ExampleOutput.field('EIN', nonprofit.ein);
        ExampleOutput.field('Location', nonprofit.city + ', ' + nonprofit.state);
        ExampleOutput.field('Profile', nonprofit.pactman_org_url);
        ExampleOutput.field('Checks used', result.checkCount);

        // Source-specific findings, read straight from the API response.
        Pub78Source pub78 = Sources.getPub78(nonprofit);
        BmfSource bmf = Sources.getBmf(nonprofit);
        OfacSource ofac = Sources.getOfac(nonprofit);

        ExampleOutput.heading('IRS Publication 78');
        ExampleOutput.bullet(
            pub78 == null ? 'not returned' : 'listed: ' + pub78.verified + ', as of ' + pub78.most_recent
        );

        ExampleOutput.heading('IRS Business Master File');
        ExampleOutput.bullet(
            bmf == null
                ? 'not returned'
                : 'status: ' + bmf.status + ', subsection: ' + bmf.subsection_description
        );

        ExampleOutput.heading('OFAC');
        ExampleOutput.bullet(ofac == null ? 'not returned' : ofac.status);

        Assert.areEqual(Ein.normalize(ein), nonprofit.ein);
        Assert.isNotNull(pub78, 'The fixture record carries Publication 78 findings.');

        // A syntactically valid EIN and a clean set of findings are not an
        // eligibility decision. Apply your own grantmaking, compliance and risk
        // policy.
    }
}
