@IsTest
private class ConfigTest {
    @IsTest
    static void defaultsToThePackagedNamedCredential() {
        Config config = new Config();

        Assert.areEqual(Constants.DEFAULT_NAMED_CREDENTIAL, config.namedCredential);
        Assert.areEqual(Constants.DEFAULT_TIMEOUT_MS, config.timeoutMs);
        Assert.areEqual('callout:' + Constants.DEFAULT_NAMED_CREDENTIAL, config.resolvedEndpoint());
    }

    @IsTest
    static void anExplicitEndpointWinsOverTheNamedCredential() {
        Config config = new Config().withEndpoint('https://pactman.example/');

        Assert.areEqual('https://pactman.example', config.resolvedEndpoint(), 'Trailing slash trimmed.');
    }

    @IsTest
    static void refusesARelativeEndpoint() {
        try {
            new Config().withEndpoint('pactman.example');
            Assert.fail('Expected a ConfigurationException.');
        } catch (ConfigurationException e) {
            Assert.areEqual(ErrorCategory.CONFIGURATION, e.category);
            Assert.areEqual(ErrorOrigin.LOCAL, e.origin);
        }
    }

    @IsTest
    static void refusesABlankNamedCredential() {
        try {
            new Config().withNamedCredential('  ');
            Assert.fail('Expected a ConfigurationException.');
        } catch (ConfigurationException e) {
            Assert.areEqual('namedCredential cannot be blank.', e.getMessage());
        }
    }

    @IsTest
    static void refusesATimeoutThePlatformWouldReject() {
        try {
            new Config().withTimeoutMs(Constants.MAX_TIMEOUT_MS + 1);
            Assert.fail('Expected a ConfigurationException.');
        } catch (ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('cannot exceed'), e.getMessage());
        }

        try {
            new Config().withTimeoutMs(0);
            Assert.fail('Expected a ConfigurationException.');
        } catch (ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('positive'), e.getMessage());
        }
    }

    @IsTest
    static void authorizationCannotBeSetFromApex() {
        try {
            new Config().withHeader('authorization', 'Bearer sk-test');
            Assert.fail('Expected a ConfigurationException.');
        } catch (ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('External Credential'), e.getMessage());
        }

        try {
            new RequestOptions().withHeader('Authorization', 'Bearer sk-test');
            Assert.fail('Expected a ConfigurationException.');
        } catch (ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('External Credential'), e.getMessage());
        }
    }

    @IsTest
    static void toMapCarriesNoCredential() {
        String logged = JSON.serialize(new Config().withHeader('X-Team', 'grants').toMap());

        Assert.isFalse(logged.containsIgnoreCase('bearer'), logged);
        Assert.isTrue(logged.contains(Constants.DEFAULT_NAMED_CREDENTIAL), logged);
    }

    @IsTest
    static void optionsCarryTimeoutAndDedupe() {
        RequestOptions options = new RequestOptions().withTimeoutMs(5000).withDedupe(true);

        Assert.areEqual(5000, options.timeoutMs);
        Assert.isTrue(options.dedupe);
        Assert.isFalse(new RequestOptions().dedupe, 'Dedupe is off by default.');
    }
}
