package org.pactman.nonprofitcheckplus;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executor;
import org.pactman.nonprofitcheckplus.config.BulkRequestOptions;
import org.pactman.nonprofitcheckplus.config.RequestOptions;
import org.pactman.nonprofitcheckplus.exceptions.PactmanValidationException;
import org.pactman.nonprofitcheckplus.http.Transport;
import org.pactman.nonprofitcheckplus.http.TransportResponse;
import org.pactman.nonprofitcheckplus.internal.Async;
import org.pactman.nonprofitcheckplus.models.ApiErrorDetail;
import org.pactman.nonprofitcheckplus.models.BulkCheckResult;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.ResponseBody;
import org.pactman.nonprofitcheckplus.models.SingleCheckResult;

/**
 * Nonprofit lookups. Reached through {@link PactmanClient#nonprofits()}.
 *
 * <p>Each method has a blocking form and an {@code Async} form. The blocking
 * form is cancelled by interrupting the calling thread; the async form by
 * cancelling the {@link CompletableFuture} it returns.
 */
public final class NonprofitsResource {

    private final Transport transport;
    private final Executor executor;

    NonprofitsResource(Transport transport, Executor executor) {
        this.transport = transport;
        this.executor = executor;
    }

    /**
     * Checks a single nonprofit by EIN.
     *
     * <p>The EIN is normalized and validated locally first; a malformed EIN
     * throws {@link PactmanValidationException} without sending a request.
     *
     * <pre>{@code
     * SingleCheckResult result = client.nonprofits().check("41-1787097");
     * System.out.println(result.getNonprofit().getOrganizationName());
     * }</pre>
     *
     * @param ein the EIN, with or without the conventional hyphen.
     * @return the organization and the response metadata.
     */
    public SingleCheckResult check(String ein) {
        return check(ein, null);
    }

    /**
     * Checks a single nonprofit by EIN, with per-request overrides.
     *
     * @param ein     the EIN, with or without the conventional hyphen.
     * @param options per-request overrides, or {@code null}.
     * @return the organization and the response metadata.
     */
    public SingleCheckResult check(String ein, RequestOptions options) {
        String normalized = Ein.normalize(ein);
        // Normalization guarantees nine digits, so there is nothing here that
        // percent-encoding would change.
        String path = Endpoints.SINGLE_CHECK_PATH.replace("{ein}", normalized);

        TransportResponse response = transport.send("GET", path, null, options);
        ResponseBody envelope = response.body();

        return new SingleCheckResult(
                extractNonprofit(envelope.getData()),
                envelope.getNonprofitCheckCount(),
                envelope.getTimeTaken(),
                envelope.getErrors(),
                response.requestId(),
                response.status(),
                envelope);
    }

    /**
     * Checks a single nonprofit by EIN, without blocking.
     *
     * @param ein the EIN, with or without the conventional hyphen.
     * @return a future completing with the result. Cancelling it stops the call.
     */
    public CompletableFuture<SingleCheckResult> checkAsync(String ein) {
        return checkAsync(ein, null);
    }

    /**
     * Checks a single nonprofit by EIN, without blocking, with per-request
     * overrides.
     *
     * @param ein     the EIN, with or without the conventional hyphen.
     * @param options per-request overrides, or {@code null}.
     * @return a future completing with the result. Cancelling it stops the call.
     */
    public CompletableFuture<SingleCheckResult> checkAsync(String ein, RequestOptions options) {
        return Async.supply(executor, () -> check(ein, options));
    }

    /**
     * Checks up to {@link Endpoints#MAX_BULK_EINS} nonprofits in one request.
     *
     * <p>Every EIN is normalized and validated before anything is sent; if any
     * one fails, the whole call throws {@link PactmanValidationException}
     * identifying the offending index, and no request is made. EINs are sent in
     * the order supplied and duplicates are kept unless
     * {@link BulkRequestOptions#dedupe(boolean)} is set — but the API matches by
     * set membership, so the response is not ordered to match and a repeated EIN
     * comes back once. Index {@link BulkCheckResult#getOrganizations()} by
     * {@link Nonprofit#getEin()} rather than pairing positionally.
     *
     * <p>EINs the API has no record for are not an error: they arrive as HTTP 200
     * with the missing values in {@link BulkCheckResult#getNotFoundEins()}.
     *
     * @param eins the EINs to check.
     * @return the organizations and the response metadata.
     */
    public BulkCheckResult checkBulk(List<String> eins) {
        return checkBulk(eins, null);
    }

    /**
     * Checks up to {@link Endpoints#MAX_BULK_EINS} nonprofits in one request,
     * with per-request overrides.
     *
     * @param eins    the EINs to check.
     * @param options per-request overrides, or {@code null}.
     * @return the organizations and the response metadata.
     */
    public BulkCheckResult checkBulk(List<String> eins, BulkRequestOptions options) {
        if (eins == null) {
            throw new PactmanValidationException(
                    "checkBulk expects a list of EINs, received null.");
        }

        // Copied once so validation and serialization see identical input, even
        // if the caller's list is mutated from another thread.
        List<String> supplied = new ArrayList<>(eins);

        if (supplied.isEmpty()) {
            throw new PactmanValidationException("checkBulk requires at least one EIN.");
        }

        List<String> normalized = Ein.normalizeAll(supplied);
        List<String> payload = options != null && options.dedupe()
                ? new ArrayList<>(new LinkedHashSet<>(normalized))
                : normalized;

        if (payload.size() > Endpoints.MAX_BULK_EINS) {
            throw new PactmanValidationException(
                    "checkBulk accepts at most " + Endpoints.MAX_BULK_EINS
                            + " EINs per request, received " + payload.size()
                            + ". Split the input into batches; this SDK does not chunk "
                            + "automatically.");
        }

        TransportResponse response =
                transport.send("POST", Endpoints.BULK_CHECK_PATH, payload, options);
        ResponseBody envelope = response.body();
        List<ApiErrorDetail> errors = envelope.getErrors();

        return new BulkCheckResult(
                extractOrganizations(envelope.getData()),
                extractNotFoundEins(errors),
                envelope.getNonprofitCheckCount(),
                envelope.getTimeTaken(),
                errors,
                response.requestId(),
                response.status(),
                envelope);
    }

    /**
     * Checks a batch of nonprofits without blocking.
     *
     * @param eins the EINs to check.
     * @return a future completing with the result. Cancelling it stops the call.
     */
    public CompletableFuture<BulkCheckResult> checkBulkAsync(List<String> eins) {
        return checkBulkAsync(eins, null);
    }

    /**
     * Checks a batch of nonprofits without blocking, with per-request overrides.
     *
     * @param eins    the EINs to check.
     * @param options per-request overrides, or {@code null}.
     * @return a future completing with the result. Cancelling it stops the call.
     */
    public CompletableFuture<BulkCheckResult> checkBulkAsync(
            List<String> eins, BulkRequestOptions options) {
        return Async.supply(executor, () -> checkBulk(eins, options));
    }

    private static Nonprofit extractNonprofit(Object data) {
        if (data instanceof Map) {
            return new Nonprofit(fields(data));
        }

        if (data instanceof List) {
            for (Object entry : (List<?>) data) {
                if (entry instanceof Map) {
                    return new Nonprofit(fields(entry));
                }
            }
        }

        return null;
    }

    /**
     * The published schema returns {@code data} as an array. Some deployments
     * wrap it as {@code {"organizations": [...]}}, so both are accepted rather
     * than silently yielding an empty list.
     */
    private static List<Nonprofit> extractOrganizations(Object data) {
        List<?> entries = null;

        if (data instanceof List) {
            entries = (List<?>) data;
        } else if (data instanceof Map) {
            Object wrapped = ((Map<?, ?>) data).get("organizations");

            if (wrapped instanceof List) {
                entries = (List<?>) wrapped;
            }
        }

        List<Nonprofit> organizations = new ArrayList<>();

        if (entries != null) {
            for (Object entry : entries) {
                if (entry instanceof Map) {
                    organizations.add(new Nonprofit(fields(entry)));
                }
            }
        }

        return organizations;
    }

    private static List<String> extractNotFoundEins(List<ApiErrorDetail> errors) {
        List<String> found = new ArrayList<>();

        for (ApiErrorDetail detail : errors) {
            found.addAll(detail.getEins());
        }

        return found;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> fields(Object value) {
        return (Map<String, Object>) value;
    }
}
