/**
 * The Pactman Nonprofit Check Plus client.
 *
 * ```
 * pactman.Client client = new pactman.Client();
 * pactman.SingleCheckResult result = client.nonprofits.check('41-1787097');
 * System.debug(result.nonprofit.organization_name);
 * System.debug(result.checkCount);
 * ```
 *
 * The API key is not passed here and is not reachable from Apex — it lives in
 * the External Credential behind the Named Credential. See {@link Config}.
 *
 * Callouts are illegal from a trigger and after DML in the same transaction,
 * which is where nonprofit verification usually needs to happen. Use
 * {@link CheckQueueable} from those contexts.
 */
global class Client {
    /** Nonprofit lookups. */
    global Nonprofits nonprofits { get; private set; }

    /** The resolved configuration. Contains no credential. */
    global Config configuration { get; private set; }

    /** Builds a client on the packaged Named Credential and default timeout. */
    global Client() {
        this(new Config());
    }

    /** Builds a client on an explicit configuration. */
    global Client(Config configuration) {
        this.configuration = configuration == null ? new Config() : configuration;
        this.nonprofits = new Nonprofits(new Transport(this.configuration));
    }

    global override String toString() {
        return 'Pactman Client(' + configuration.resolvedEndpoint() + ')';
    }
}
