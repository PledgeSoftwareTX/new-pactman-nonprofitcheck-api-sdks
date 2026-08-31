/** Nonprofit lookups. Reached through {@link Client.nonprofits}. */
global class Nonprofits {
    private final Transport transport;

    /** Package-internal: built by {@link Client}. */
    public Nonprofits(Transport transport) {
        this.transport = transport;
    }

    /**
     * Checks a single nonprofit by EIN.
     *
     * The EIN is normalized and validated locally first; a malformed EIN throws
     * {@link ValidationException} without making a callout.
     *
     * ```
     * pactman.SingleCheckResult result = client.nonprofits.check('41-1787097');
     * System.debug(result.nonprofit.organization_name);
     * ```
     *
     * @throws ValidationException if the EIN is malformed. Nothing is sent.
     * @throws PactmanException for any other failure.
     */
    global SingleCheckResult check(String ein) {
        return check(ein, null);
    }

    /** Checks a single nonprofit by EIN, with per-request overrides. */
    global SingleCheckResult check(String ein, RequestOptions options) {
        String path = Constants.SINGLE_CHECK_PATH.replace(
            '{ein}',
            EncodingUtil.urlEncode(Ein.normalize(ein), 'UTF-8')
        );

        TransportResponse response = transport.send('GET', path, null, options);
        Map<String, Object> envelope = response.envelopeOrEmpty();

        return new SingleCheckResult(
            checkCount(envelope),
            timeTakenMs(envelope),
            Transport.normalizeApiErrors(envelope.get('errors')),
            response.requestId,
            response.status,
            response.raw,
            extractNonprofit(envelope.get('data'))
        );
    }

    /**
     * Checks up to {@link Constants.MAX_BULK_EINS} nonprofits in one request.
     *
     * Every EIN is normalized and validated before anything is sent; if any one
     * fails, the whole call throws {@link ValidationException} identifying the
     * offending index, and no callout is made. EINs are sent in the order
     * supplied and duplicates are kept unless `dedupe` is set — but the API
     * matches by set membership, so the response is not ordered to match and a
     * repeated EIN comes back once. Index `organizations` by EIN with
     * {@link BulkCheckResult.byEin} rather than pairing positionally.
     *
     * EINs the API has no record for are not an error: they arrive as HTTP 200
     * with the missing values in `notFoundEins`.
     *
     * This does not chunk automatically — see {@link Ein.chunk}, and remember
     * that a transaction is capped at 100 callouts and 120 seconds of
     * cumulative callout time.
     *
     * @throws ValidationException if the batch is empty, over the limit, or
     *     contains a malformed EIN. Nothing is sent.
     * @throws PactmanException for any other failure.
     */
    global BulkCheckResult checkBulk(List<String> eins) {
        return checkBulk(eins, null);
    }

    /** Checks a batch of nonprofits, with per-request overrides. */
    global BulkCheckResult checkBulk(List<String> eins, RequestOptions options) {
        List<String> payload = buildPayload(eins, options != null && options.dedupe == true);

        TransportResponse response = transport.send('POST', Constants.BULK_CHECK_PATH, payload, options);
        Map<String, Object> envelope = response.envelopeOrEmpty();
        List<ApiErrorDetail> errors = Transport.normalizeApiErrors(envelope.get('errors'));

        return new BulkCheckResult(
            checkCount(envelope),
            timeTakenMs(envelope),
            errors,
            response.requestId,
            response.status,
            response.raw,
            extractOrganizations(envelope.get('data')),
            extractNotFoundEins(errors)
        );
    }

    private List<String> buildPayload(List<String> eins, Boolean dedupe) {
        if (eins == null || eins.isEmpty()) {
            throw Errors.validation('checkBulk requires at least one EIN.', null);
        }

        List<String> normalized = Ein.normalizeMany(eins);
        List<String> payload = normalized;

        if (dedupe) {
            payload = new List<String>();
            Set<String> seen = new Set<String>();

            for (String ein : normalized) {
                if (seen.add(ein)) {
                    payload.add(ein);
                }
            }
        }

        if (payload.size() > Constants.MAX_BULK_EINS) {
            throw Errors.validation(
                'checkBulk accepts at most ' + Constants.MAX_BULK_EINS +
                    ' EINs per request, received ' + payload.size() +
                    '. Split the input into batches with Ein.chunk; this SDK does not chunk automatically.',
                null
            );
        }

        return payload;
    }

    private Integer checkCount(Map<String, Object> envelope) {
        return DataObject.asInteger(envelope.get('nonprofit_check_count'));
    }

    private Decimal timeTakenMs(Map<String, Object> envelope) {
        return DataObject.asDecimal(envelope.get('timeTaken'));
    }

    private Nonprofit extractNonprofit(Object data) {
        if (data instanceof Map<String, Object>) {
            Map<String, Object> fields = (Map<String, Object>) data;
            return fields.isEmpty() ? null : new Nonprofit(fields);
        }

        if (data instanceof List<Object>) {
            List<Object> entries = (List<Object>) data;

            if (!entries.isEmpty() && entries[0] instanceof Map<String, Object>) {
                return new Nonprofit((Map<String, Object>) entries[0]);
            }
        }

        return null;
    }

    /**
     * The published schema returns `data` as an array. Some deployments wrap it
     * as `{"organizations": [...]}`, so both are accepted rather than silently
     * yielding an empty list.
     */
    private List<Nonprofit> extractOrganizations(Object data) {
        List<Nonprofit> organizations = new List<Nonprofit>();
        Object entries = data;

        if (data instanceof Map<String, Object>) {
            entries = ((Map<String, Object>) data).get('organizations');
        }

        if (entries instanceof List<Object>) {
            for (Object entry : (List<Object>) entries) {
                if (entry instanceof Map<String, Object>) {
                    organizations.add(new Nonprofit((Map<String, Object>) entry));
                }
            }
        }

        return organizations;
    }

    private List<String> extractNotFoundEins(List<ApiErrorDetail> errors) {
        List<String> found = new List<String>();

        for (ApiErrorDetail detail : errors) {
            found.addAll(detail.eins);
        }

        return found;
    }
}
