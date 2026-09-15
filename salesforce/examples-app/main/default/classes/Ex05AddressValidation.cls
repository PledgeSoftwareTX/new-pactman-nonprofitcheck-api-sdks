/**
 * EX-05 — Address validation.
 *
 * A non-null address field is not a usable address. This example runs three
 * records through the same checks: one clean, one with several fields returned as
 * null, and one where every component is present and they contradict each other.
 */
@IsTest
private class Ex05AddressValidation {
    private static final List<String> ADDRESS_FIELDS = new List<String>{
        'address_line1', 'address_line2', 'city', 'state', 'state_name', 'zip'
    };

    @IsTest
    static void readsTheValuesNotJustTheirPresence() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Map<String, List<String>> byEin = new Map<String, List<String>>();

        Test.startTest();

        for (
            String ein : new List<String>{
                ExampleFixtures.PUBLIC_CHARITY,
                ExampleFixtures.SPARSE_IDENTITY,
                ExampleFixtures.INCONSISTENT_ADDRESS
            }
        ) {
            Nonprofit nonprofit = ExampleApiMock.client().nonprofits.check(ein).nonprofit;

            ExampleOutput.heading(nonprofit.organization_name + ' (' + ein + ')');

            for (String name : ADDRESS_FIELDS) {
                ExampleOutput.field(name, ExampleOutput.present(nonprofit, name));
            }

            List<String> findings = ExampleAddresses.findings(nonprofit);
            byEin.put(ein, findings);

            System.debug('');

            if (findings.isEmpty()) {
                ExampleOutput.bullet('nothing to report');
            }

            for (String finding : findings) {
                ExampleOutput.bullet(finding);
            }
        }

        Test.stopTest();

        Assert.areEqual(
            0,
            byEin.get(ExampleFixtures.PUBLIC_CHARITY).size(),
            'The clean record should produce no findings.'
        );

        Assert.isFalse(
            byEin.get(ExampleFixtures.SPARSE_IDENTITY).isEmpty(),
            'A null ZIP is worth reporting.'
        );

        // The third record has every component populated and still describes
        // three different places.
        Assert.isTrue(
            byEin.get(ExampleFixtures.INCONSISTENT_ADDRESS).size() >= 2,
            'A complete but self-contradicting address should produce several findings.'
        );

        ExampleOutput.note(
            'The third record would pass any check that only asks whether the fields came\n' +
            'back non-null: every component is there. The state code, the spelled-out state\n' +
            'and the ZIP describe three different places, and address_line2 holds a\n' +
            'placeholder. Read the values, not just their presence.'
        );
    }
}
