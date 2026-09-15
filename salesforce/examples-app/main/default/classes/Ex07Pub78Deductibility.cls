/**
 * EX-07 — Publication 78 and deductibility limits.
 *
 * Publication 78 is what says a donation is deductible, and `organization_types`
 * carries the limit that applies. A public charity and a private foundation
 * differ here, and the difference is the donor's tax outcome.
 */
@IsTest
private class Ex07Pub78Deductibility {
    @IsTest
    static void readsDeductibilityLimitsFromTheSource() {
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
            Pub78Source pub78 = Sources.getPub78(nonprofit);

            ExampleOutput.heading(nonprofit.organization_name + ' (' + ein + ')');

            if (pub78 == null) {
                ExampleOutput.bullet('The API returned no Publication 78 data at all.');
                continue;
            }

            ExampleOutput.field('verified', pub78.verified);
            ExampleOutput.field('indicator', pub78.indicator);
            ExampleOutput.field(
                '  meaning',
                ExampleIrsCodes.describePub78Indicator(pub78.indicator)
            );
            ExampleOutput.field('most_recent', pub78.most_recent);
            ExampleOutput.field('organization_types', pub78.organization_types.size() + ' entries');
            ExampleOutput.field(
                '  has(organization_types)',
                nonprofit.has('organization_types')
            );
            ExampleOutput.field(
                '  value',
                ExampleOutput.present(nonprofit, 'organization_types')
            );

            for (OrganizationType entry : pub78.organization_types) {
                System.debug('');
                ExampleOutput.field('  limitation', entry.deductibility_limitation);
                ExampleOutput.field('  status', entry.deductibility_status_description);
                ExampleOutput.field('  text', truncate(entry.organization_type));
            }
        }

        Nonprofit charity = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.PUBLIC_CHARITY)
            .nonprofit;
        Nonprofit foundation = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.PRIVATE_FOUNDATION)
            .nonprofit;
        Nonprofit revoked = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.REVOKED)
            .nonprofit;

        Test.stopTest();

        Assert.areEqual(
            '50%',
            Sources.getPub78(charity).organization_types[0].deductibility_limitation
        );
        Assert.areEqual(
            '30%',
            Sources.getPub78(foundation).organization_types[0].deductibility_limitation,
            'A private foundation carries a different limit, and it is the donor who feels it.'
        );

        // The API sent organization_types as null for the revoked organization.
        // The accessor still returns an empty list, so iterating is always
        // safe; has() is what tells you the field was there at all.
        Assert.areEqual(0, Sources.getPub78(revoked).organization_types.size());
        Assert.isTrue(revoked.has('organization_types'));
        Assert.isNull(revoked.get('organization_types'));

        ExampleOutput.note(
            'organization_types is empty for the revoked organization - the API sent null,\n' +
            'not an empty list. The accessor returns an empty list either way so iterating\n' +
            'is always safe; ask has() when the difference matters.\n\n' +
            'Deductibility is the donor\'s tax question, not the charity\'s status. Read the\n' +
            'limit the API returned; do not infer one from the subsection.'
        );
    }

    /** Keeps the long deductibility sentence to one log line. */
    private static String truncate(String text) {
        if (text == null) {
            return null;
        }

        return text.length() <= 72 ? text : text.substring(0, 69) + '...';
    }
}
