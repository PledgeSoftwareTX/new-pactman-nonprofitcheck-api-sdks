/**
 * EX-13 — Filing and exemption metadata.
 *
 * The codes the API returns bare — filing requirement, exempt status — are the
 * ones that need a local table. This example shows the table, and the two rules
 * that keep one safe to own.
 */
@IsTest
private class Ex13FilingExemptionMetadata {
    @IsTest
    static void describesBareCodesWithAFallback() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Test.startTest();

        for (
            String ein : new List<String>{
                ExampleFixtures.PUBLIC_CHARITY,
                ExampleFixtures.PRIVATE_FOUNDATION,
                ExampleFixtures.REVOKED
            }
        ) {
            Nonprofit nonprofit = ExampleApiMock.client().nonprofits.check(ein).nonprofit;
            BmfSource bmf = Sources.getBmf(nonprofit);

            ExampleOutput.heading(nonprofit.organization_name + ' (' + ein + ')');

            if (bmf == null) {
                ExampleOutput.bullet('The API returned no Business Master File data at all.');
                continue;
            }

            ExampleOutput.field('filing_req_code', bmf.filing_req_code);
            ExampleOutput.field(
                '  meaning',
                ExampleIrsCodes.describeFilingRequirement(bmf.filing_req_code)
            );
            ExampleOutput.field('exempt_status_code', bmf.exempt_status_code);
            ExampleOutput.field(
                '  meaning',
                ExampleIrsCodes.describeExemptStatus(bmf.exempt_status_code)
            );
            ExampleOutput.field('group_exemption', bmf.group_exemption);
            ExampleOutput.field('ruling_month', bmf.ruling_month);
            ExampleOutput.field('ruling_year', bmf.ruling_year);
        }

        Test.stopTest();

        ExampleOutput.heading('What an unknown code does');
        ExampleOutput.field('code "99"', ExampleIrsCodes.describeFilingRequirement('99'));
        ExampleOutput.field('code null', ExampleIrsCodes.describeFilingRequirement(null));

        // Rule 1: an unknown code keeps the code visible.
        String unknown = ExampleIrsCodes.describeFilingRequirement('99');
        Assert.isNotNull(unknown);
        Assert.isTrue(
            unknown.contains('99'),
            'An unknown code must stay legible to whoever reads the output.'
        );

        // Rule 2: null stays null.
        Assert.isNull(
            ExampleIrsCodes.describeFilingRequirement(null),
            'Reporting "unknown code" for a field the API never sent invents a code.'
        );

        ExampleOutput.note(
            'Two rules make a local code table safe:\n\n' +
            '  1. An unknown code degrades to a sentence that keeps the code visible,\n' +
            '     never to null and never to a wrong label. A value the IRS adds is then\n' +
            '     legible to whoever reads the output, without a package upgrade.\n' +
            '  2. null stays null. Reporting "unknown code" for a field the API never sent\n' +
            '     invents a code, and someone downstream will investigate it.'
        );
    }
}
