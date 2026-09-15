/**
 * EX-10 — OFAC screening.
 *
 * The API reports OFAC as a sentence, not a flag. This SDK does not invent a
 * boolean from it, because deriving one means pattern-matching English that can
 * be reworded at any time. This example does the pattern matching — in your own
 * code, where you can see it and own it — and shows the states it can end in,
 * one of which is "I do not recognize this wording".
 */
@IsTest
private class Ex10OfacScreening {
    @IsTest
    static void readsEveryOfacState() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Map<String, String> states = new Map<String, String>();

        Test.startTest();

        for (
            String ein : new List<String>{
                ExampleFixtures.PUBLIC_CHARITY,
                ExampleFixtures.OFAC_MATCH,
                ExampleFixtures.OFAC_UNAVAILABLE,
                ExampleFixtures.SPARSE_IDENTITY
            }
        ) {
            Nonprofit nonprofit = ExampleApiMock.client().nonprofits.check(ein).nonprofit;
            OfacSource ofac = Sources.getOfac(nonprofit);
            String state = ExampleScreening.ofacState(nonprofit);
            states.put(ein, state);

            ExampleOutput.heading(nonprofit.organization_name + ' (' + ein + ')');
            ExampleOutput.field(
                'Sources.getOfac(...)',
                ofac == null ? 'null - the source was not returned' : 'returned'
            );
            ExampleOutput.field('has("ofac_status")', nonprofit.has('ofac_status'));
            ExampleOutput.field('state', state);
            System.debug('');
            System.debug(
                '  ' + ExampleOutput.render(ExampleOutput.present(nonprofit, 'ofac_status'))
            );
        }

        Test.stopTest();

        Assert.areEqual(
            ExampleScreening.OFAC_NO_MATCH,
            states.get(ExampleFixtures.PUBLIC_CHARITY)
        );
        Assert.areEqual(ExampleScreening.OFAC_MATCH, states.get(ExampleFixtures.OFAC_MATCH));
        Assert.areEqual(
            ExampleScreening.OFAC_NULL,
            states.get(ExampleFixtures.OFAC_UNAVAILABLE),
            'The field came back with no value in it.'
        );
        Assert.areEqual(
            ExampleScreening.OFAC_UNAVAILABLE,
            states.get(ExampleFixtures.SPARSE_IDENTITY),
            'The API returned no OFAC field at all.'
        );

        ExampleOutput.note(
            'Four states, and only one of them is a pass:\n' +
            '  NO_MATCH     - the API said the organization was not on the SDN list\n' +
            '  MATCH        - the API named a possible match, with a UID\n' +
            '  NULL         - the field came back with no value\n' +
            '  UNAVAILABLE  - the API returned no OFAC data at all\n\n' +
            'UNAVAILABLE and NULL are not clean results. They are the absence of a result,\n' +
            'and a screening workflow that treats them as clean has screened nothing.\n' +
            'UNRECOGNIZED - wording this reader does not know - belongs with them: route it\n' +
            'to a person rather than guessing.'
        );
    }
}
