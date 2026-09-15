/**
 * EX-01 — Secure client initialization.
 *
 * In the other Pactman SDKs this example loads an API key from the environment
 * and then proves the key does not reach a log, an exception or a debug line.
 * **Apex cannot do either half of that, and that is the point.** The key lives
 * in the External Credential behind the Named Credential, the platform injects
 * the `Authorization` header at callout time, and Apex never sees the value —
 * so there is no diagnostic surface to audit, because there is nothing to leak.
 *
 * What is left to configure is the endpoint, the timeout and any default
 * headers. This example shows each, and shows the two things the SDK refuses.
 */
@IsTest
private class Ex01SecureClientInit {
    @IsTest
    static void buildsAClientWithNoReachableCredential() {
        Test.startTest();

        // 1. The packaged default: callouts go through the Named Credential,
        //    and the key is whatever an admin stored in the External
        //    Credential behind it.
        Config packaged = new Config();

        ExampleOutput.heading('The packaged default');
        ExampleOutput.field('namedCredential', packaged.namedCredential);
        ExampleOutput.field('endpointOverride', packaged.endpointOverride);
        ExampleOutput.field('timeoutMs', packaged.timeoutMs);
        ExampleOutput.field('Constants.DEFAULT_TIMEOUT_MS', Constants.DEFAULT_TIMEOUT_MS);
        ExampleOutput.field('Constants.MAX_TIMEOUT_MS', Constants.MAX_TIMEOUT_MS);

        Assert.areEqual(
            Constants.DEFAULT_NAMED_CREDENTIAL,
            packaged.namedCredential,
            'A client built with no options should use the packaged Named Credential.'
        );

        // 2. One client, built once and reused. Nothing here takes a key,
        //    because there is nowhere in Apex to put one.
        Config configured = new Config()
            .withNamedCredential('Pactman_Nonprofit_Check')
            .withTimeoutMs(10000)
            .withHeader('X-Correlation-Id', 'onboarding-42');

        Client client = new Client(configured);

        ExampleOutput.heading('A configured client');
        ExampleOutput.field('toString()', client.toString());
        ExampleOutput.field('configuration.timeoutMs', client.configuration.timeoutMs);
        ExampleOutput.field('default headers', client.configuration.headers().keySet().size());

        // 3. The only serializable view of the configuration. There is no key
        //    in it because the key is not a property of anything in Apex.
        Map<String, Object> logged = client.configuration.toMap();

        ExampleOutput.heading('The configuration as logged');

        for (String key : logged.keySet()) {
            ExampleOutput.field(key, logged.get(key));
        }

        Assert.isFalse(
            logged.containsKey('apiKey'),
            'The configuration must not carry an apiKey; the platform holds the credential.'
        );

        // 4. Two things the SDK refuses up front rather than at callout time.
        ExampleOutput.heading('What the SDK refuses');

        try {
            new Config().withTimeoutMs(Constants.MAX_TIMEOUT_MS + 1);
            Assert.fail('A timeout above the platform ceiling should have been refused.');
        } catch (ConfigurationException e) {
            ExampleOutput.field('timeoutMs too high', e.getMessage());
            Assert.areEqual(ErrorCategory.CONFIGURATION, e.category);
            Assert.areEqual(ErrorOrigin.LOCAL, e.origin);
        }

        try {
            new Config().withHeader('Authorization', 'Bearer something');
            Assert.fail('Setting Authorization from Apex should have been refused.');
        } catch (ConfigurationException e) {
            ExampleOutput.field('Authorization header', e.getMessage());
        }

        Test.stopTest();

        ExampleOutput.note(
            'Salesforce already has an encrypted, admin-managed credential store, so this\n' +
            'SDK has no apiKey option at all. That removes a whole class of mistake the\n' +
            'other SDKs have to defend against: the key cannot be committed to source,\n' +
            'printed to a debug log, or serialized into an exception, because Apex has no\n' +
            'way to read it.\n\n' +
            'It also means rotating the key is a Setup change, not a deployment. Assign\n' +
            'the "Pactman Nonprofit Check User" permission set, or callouts fail with a 401\n' +
            'even when the stored key is correct.'
        );
    }
}
