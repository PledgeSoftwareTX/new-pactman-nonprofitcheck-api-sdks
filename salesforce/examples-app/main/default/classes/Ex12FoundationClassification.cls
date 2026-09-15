/**
 * EX-12 — Foundation classification.
 *
 * Public charity or private foundation is the distinction that drives
 * deductibility limits, excise taxes and expenditure responsibility. The API
 * returns both the code and its description; prefer the description, because it
 * comes from the source and changes with it.
 */
@IsTest
private class Ex12FoundationClassification {
    @IsTest
    static void prefersTheDescriptionsTheApiReturns() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Test.startTest();

        for (
            String ein : new List<String>{
                ExampleFixtures.PUBLIC_CHARITY, ExampleFixtures.PRIVATE_FOUNDATION
            }
        ) {
            Nonprofit nonprofit = ExampleApiMock.client().nonprofits.check(ein).nonprofit;
            BmfSource bmf = Sources.getBmf(nonprofit);

            ExampleOutput.heading(nonprofit.organization_name + ' (' + ein + ')');

            if (bmf == null) {
                ExampleOutput.bullet('The API returned no Business Master File data at all.');
                continue;
            }

            ExampleOutput.field('subsection', bmf.subsection);
            ExampleOutput.field('subsection_description', bmf.subsection_description);
            ExampleOutput.field('foundation_code', bmf.foundation_code);
            ExampleOutput.field('foundation_code_description', bmf.foundation_code_description);
            ExampleOutput.field('foundation_type_code', bmf.foundation_type_code);
            ExampleOutput.field('foundation_type_description', bmf.foundation_type_description);
            ExampleOutput.field('foundation_509a_status', bmf.foundation_509a_status);
        }

        Nonprofit charity = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.PUBLIC_CHARITY)
            .nonprofit;
        Nonprofit foundation = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.PRIVATE_FOUNDATION)
            .nonprofit;

        Test.stopTest();

        Assert.areEqual('501(c)(3) Public Charity', charity.subsection_description);
        Assert.areEqual('501(c)(3) Private Foundation', foundation.subsection_description);
        Assert.areEqual('pc', charity.foundation_type_code);
        Assert.areEqual('pf', foundation.foundation_type_code);

        ExampleOutput.note(
            'Read the *_description fields rather than mapping the codes yourself. They\n' +
            'arrive from the IRS extract, so a classification the IRS adds is described\n' +
            'correctly the day it appears - a local table would need a package upgrade, and\n' +
            'a managed package cannot be hot-patched.\n\n' +
            'Both codes and descriptions can be null. A missing classification is not a\n' +
            'public charity by default.'
        );
    }
}
