/**
 * EX-03 — Identity lookup.
 *
 * Reads the identity fields off a record, and shows the difference the SDK keeps
 * and most callers lose: a field the API returned as `null` is not the same as a
 * field the API did not return at all.
 *
 * In Apex this matters more than in the other SDKs. `JSON.deserialize` into a
 * typed class rejects attributes the class does not declare, so the SDK decodes
 * untyped and reads through accessors over the raw map — which is also what
 * makes `has()` possible.
 */
@IsTest
private class Ex03IdentityLookup {
    private static final List<String> IDENTITY_FIELDS = new List<String>{
        'organization_name', 'organization_name_aka', 'address_line1', 'address_line2',
        'city', 'state', 'state_name', 'zip', 'pub78_city', 'pub78_state', 'ofac_status'
    };

    @IsTest
    static void keepsAbsentAndNullApart() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Test.startTest();

        for (
            String ein : new List<String>{
                ExampleFixtures.PUBLIC_CHARITY, ExampleFixtures.SPARSE_IDENTITY
            }
        ) {
            SingleCheckResult result = ExampleApiMock.client().nonprofits.check(ein);
            Nonprofit nonprofit = result.nonprofit;

            ExampleOutput.heading('EIN ' + ein);

            for (String name : IDENTITY_FIELDS) {
                // present() reports <not returned> for a key the API omitted
                // and <null> for one it sent empty. Two different facts.
                ExampleOutput.field(name, ExampleOutput.present(nonprofit, name));
            }

            ExampleOutput.field('HTTP status', result.status);
            ExampleOutput.field('Correlation id', result.requestId);
        }

        // The clean record carries an OFAC opinion. The sparse one carries no
        // ofac_status key at all — the source was not reported, which is not a
        // null status and is certainly not a no-match.
        Nonprofit clean = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.PUBLIC_CHARITY)
            .nonprofit;
        Nonprofit sparse = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.SPARSE_IDENTITY)
            .nonprofit;

        Test.stopTest();

        ExampleOutput.heading('The distinction, stated as assertions');
        ExampleOutput.field('clean.has("ofac_status")', clean.has('ofac_status'));
        ExampleOutput.field('sparse.has("ofac_status")', sparse.has('ofac_status'));
        ExampleOutput.field('sparse.has("state_name")', sparse.has('state_name'));
        ExampleOutput.field('sparse.state_name', sparse.state_name);

        Assert.isTrue(clean.has('ofac_status'), 'The clean record was screened.');
        Assert.isFalse(sparse.has('ofac_status'), 'The sparse record was not.');
        Assert.isTrue(sparse.has('state_name'), 'state_name was returned...');
        Assert.isNull(sparse.state_name, '...with no value in it.');

        ExampleOutput.note(
            'The second record is missing `ofac_status` entirely and returns null for\n' +
            'several identity fields. `has()` is what separates the two, and the\n' +
            'distinction matters: "the source reported nothing" and "the source reported no\n' +
            'value" are different findings, and only one of them is about the organization.\n\n' +
            'The typed accessors read both as null, which is the right default for code\n' +
            'that only wants a value. Reach for has() when the absence itself is the answer.'
        );
    }
}
