/**
 * EX-04 — Comparing an applicant's name against the record.
 *
 * The API returns three names for one organization: the BMF name, the
 * Publication 78 name, and an "also known as". They disagree routinely, and none
 * of them is wrong. Comparing an applicant's typed name against them is a
 * customer policy question, which is why the comparison lives in
 * {@link ExampleMatching} and not in the SDK.
 */
@IsTest
private class Ex04NameComparison {
    private static final String APPLICANT = 'Meals Today Example Nonprofit, Inc.';

    @IsTest
    static void comparesAnApplicantNameAgainstEverySource() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Test.startTest();
        Nonprofit nonprofit = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.PUBLIC_CHARITY)
            .nonprofit;
        Test.stopTest();

        Pub78Source pub78 = Sources.getPub78(nonprofit);
        String pub78Name = pub78 == null ? null : pub78.organization_name;

        ExampleOutput.heading('The names the API returned');
        ExampleOutput.field('applicant typed', APPLICANT);
        ExampleOutput.field('organization_name', nonprofit.organization_name);
        ExampleOutput.field('bmf_organization_name', nonprofit.bmf_organization_name);
        ExampleOutput.field('pub78_organization_name', pub78Name);
        ExampleOutput.field('organization_name_aka', nonprofit.organization_name_aka);

        ExampleOutput.heading('Normalized for comparison');
        ExampleOutput.field('applicant', ExampleMatching.normalizeName(APPLICANT));
        ExampleOutput.field(
            'organization_name',
            ExampleMatching.normalizeName(nonprofit.organization_name)
        );

        ExampleOutput.heading('How each one compares');

        Map<String, String> candidates = new Map<String, String>{
            'organization_name' => nonprofit.organization_name,
            'bmf_organization_name' => nonprofit.bmf_organization_name,
            'pub78_organization_name' => pub78Name,
            'organization_name_aka' => nonprofit.organization_name_aka
        };

        for (String label : candidates.keySet()) {
            String candidate = candidates.get(label);
            String comparison = ExampleMatching.compareNames(APPLICANT, candidate);
            Decimal overlap = ExampleMatching.wordOverlap(APPLICANT, candidate);

            ExampleOutput.field(
                label,
                comparison + (overlap == null ? '' : ' (word overlap ' + overlap + ')')
            );
        }

        // "Meals Today Example Nonprofit, Inc." and "MEALS TODAY EXAMPLE
        // NONPROFIT" agree: the casing, the comma and the legal suffix are not
        // differences between organizations.
        Assert.areEqual(
            ExampleMatching.AGREE,
            ExampleMatching.compareNames(APPLICANT, nonprofit.organization_name),
            'Punctuation and a legal suffix are not a mismatch.'
        );

        // The "also known as" is an abbreviation, not the same name.
        Assert.areEqual(
            ExampleMatching.DIFFER,
            ExampleMatching.compareNames(APPLICANT, nonprofit.organization_name_aka)
        );

        // A missing name is never agreement.
        Assert.areEqual(
            ExampleMatching.UNCOMPARABLE,
            ExampleMatching.compareNames(APPLICANT, null),
            'Scoring an absent value as a match is how a blank record passes a name check.'
        );

        ExampleOutput.note(
            'A missing name is UNCOMPARABLE, never agreement. And a name that differs is\n' +
            'not fraud: organizations rename, and IRS records lag. Route the disagreement\n' +
            'to a reviewer; do not fail the applicant on it.'
        );
    }
}
