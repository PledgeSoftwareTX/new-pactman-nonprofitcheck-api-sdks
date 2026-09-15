/**
 * EX-25 — Raw access and forward compatibility.
 *
 * An API that adds a field should not break an SDK that has never heard of it.
 * That is a harder promise to keep in Apex than anywhere else: `JSON.deserialize`
 * into a typed class **throws** on an attribute the class does not declare, and
 * a managed package cannot be hot-patched when the API grows a field. So
 * responses are decoded untyped and read through accessors over the raw map.
 *
 * This example reads two records the accessors cannot fully describe: one from a
 * newer API version, and one from a deployment running ahead of production.
 */
@IsTest
private class Ex25RawAndForwardCompat {
    @IsTest
    static void readsFieldsThisVersionHasNeverHeardOf() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Set<String> predicted = predictedFields();

        Test.startTest();
        Nonprofit future = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.FUTURE_FIELDS)
            .nonprofit;
        SingleCheckResult pendingResult = ExampleApiMock.client()
            .nonprofits.check(ExampleFixtures.PENDING_SOURCE_FIELDS);
        Test.stopTest();

        Nonprofit pending = pendingResult.nonprofit;

        ExampleOutput.heading('Fields this SDK predicts');

        String contractSize = predicted.isEmpty()
            ? 'the contract static resource is not deployed in this org'
            : String.valueOf(predicted.size()) + ' fields';

        ExampleOutput.field('from the packaged contract', contractSize);

        for (Nonprofit nonprofit : new List<Nonprofit>{ future, pending }) {
            ExampleOutput.heading(nonprofit.organization_name);
            ExampleOutput.field('fields returned', nonprofit.keys().size());

            List<String> unpredicted = new List<String>();

            for (String name : nonprofit.keys()) {
                if (!predicted.contains(name)) {
                    unpredicted.add(name);
                }
            }

            unpredicted.sort();
            System.debug('');

            for (String name : unpredicted) {
                // Decoding did not fail, and the value did not vanish.
                ExampleOutput.bullet(
                    name + ' = ' + ExampleOutput.render(nonprofit.get(name))
                );
            }

            if (!predicted.isEmpty()) {
                Assert.isFalse(
                    unpredicted.isEmpty(),
                    'This fixture should carry fields outside the contract.'
                );
            }
        }

        // The ten source fields a newer deployment serves are readable now,
        // without a package upgrade.
        ExampleOutput.heading('A deployment ahead of production');
        ExampleOutput.field('bmf_city', ExampleOutput.present(pending, 'bmf_city'));
        ExampleOutput.field('bmf_state', ExampleOutput.present(pending, 'bmf_state'));
        ExampleOutput.field(
            'ofac_list_published_date',
            ExampleOutput.present(pending, 'ofac_list_published_date')
        );
        ExampleOutput.field(
            'pub78_source_org_type_2',
            ExampleOutput.present(pending, 'pub78_source_org_type_2')
        );

        Assert.areEqual('WESTFIELD', pending.get('bmf_city'));
        Assert.isTrue(
            pending.has('pub78_source_org_type_2'),
            'The field was returned...'
        );
        Assert.isNull(pending.get('pub78_source_org_type_2'), '...with no value in it.');

        ExampleOutput.heading('An unknown member inside a known object');

        for (OrganizationType entry : Sources.getPub78(future).organization_types) {
            ExampleOutput.field('deductibility_limitation', entry.deductibility_limitation);
            ExampleOutput.field(
                'deductibility_status_description',
                entry.deductibility_status_description
            );
            ExampleOutput.field(
                'future_deductibility_note',
                ExampleOutput.present(entry, 'future_deductibility_note')
            );

            Assert.areEqual(
                'An unknown member of a known object',
                entry.get('future_deductibility_note')
            );
        }

        ExampleOutput.heading('An enum value outside the documented set');
        ExampleOutput.field('foundation_type_code', future.foundation_type_code);
        ExampleOutput.field('foundation_type_description', future.foundation_type_description);

        // 'zz' is not in the documented set. It is returned, not rejected.
        Assert.areEqual('zz', future.foundation_type_code);

        ExampleOutput.heading('A nested object this SDK does not declare');

        Map<String, Object> watchlist = future.getMap('watchlist_screening');

        for (String key : watchlist.keySet()) {
            ExampleOutput.field('  ' + key, watchlist.get(key));
        }

        Assert.areEqual('example', watchlist.get('provider'));

        ExampleOutput.heading('The whole envelope, unmodified');
        ExampleOutput.field('raw is a Map', pendingResult.raw instanceof Map<String, Object>);
        ExampleOutput.field(
            'envelope keys',
            new List<String>(((Map<String, Object>) pendingResult.raw).keySet())
        );

        ExampleOutput.note(
            'The second record is a deployment ahead of production: it carries the ten\n' +
            'source fields that are built but not yet released there. This SDK does not\n' +
            'declare them, on purpose - declaring a field production does not return would\n' +
            'promise something the API does not keep. They stay readable through get() and\n' +
            'the raw envelope until a release declares them.\n\n' +
            'Nothing about an unpredicted field is an error. It is worth logging, because\n' +
            'it is how you find out the API moved before your package did.'
        );
    }

    /**
     * The fields the packaged contract predicts, read from the static resource.
     *
     * The other SDKs load this at runtime from a file beside the code. Apex has
     * no filesystem, so the contract ships as a static resource — and if it is
     * not deployed, this returns an empty set and the example reports what it
     * found instead of asserting against nothing.
     */
    private static Set<String> predictedFields() {
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'pactman_response_contract'
            LIMIT 1
        ];

        if (resources.isEmpty()) {
            return new Set<String>();
        }

        Map<String, Object> contract = (Map<String, Object>) JSON.deserializeUntyped(
            resources[0].Body.toString()
        );

        Object nonprofit = contract.get('nonprofit');

        if (!(nonprofit instanceof Map<String, Object>)) {
            return new Set<String>();
        }

        return ((Map<String, Object>) nonprofit).keySet();
    }
}
