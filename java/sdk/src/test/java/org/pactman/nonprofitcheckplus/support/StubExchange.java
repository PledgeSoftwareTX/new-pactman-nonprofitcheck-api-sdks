package org.pactman.nonprofitcheckplus.support;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpHeaders;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Flow;
import javax.net.ssl.SSLSession;
import org.pactman.nonprofitcheckplus.http.HttpExchange;

/**
 * Serves canned responses in order and records what was asked of it.
 *
 * <p>The last stub repeats once the queue is exhausted, so a retry test can end
 * on a stable outcome without listing the same response several times.
 */
public final class StubExchange implements HttpExchange {

    private final List<Object> stubs;
    private final List<RecordedRequest> requests =
            Collections.synchronizedList(new ArrayList<RecordedRequest>());

    private int index;

    /**
     * Serves these stubs, in order.
     *
     * @param stubs each a {@link StubResponse} to return, a {@link Throwable} to
     *              fail with, or {@link #NEVER_RESPONDS} to hang.
     */
    public StubExchange(Object... stubs) {
        this.stubs = Arrays.asList(stubs);

        if (this.stubs.isEmpty()) {
            throw new IllegalArgumentException("StubExchange needs at least one stub.");
        }
    }

    /** A stub that never completes, so the caller's timeout is what ends the attempt. */
    public static final Object NEVER_RESPONDS = new Object();

    /**
     * A transport failure, of the kind a dropped connection produces.
     *
     * @return the failure to hand to the constructor.
     */
    public static Throwable networkFailure() {
        return new IOException("connection reset by peer");
    }

    /**
     * Every request this exchange was asked to send, in order.
     *
     * @return the recorded requests.
     */
    public List<RecordedRequest> requests() {
        return requests;
    }

    /**
     * How many requests were sent.
     *
     * @return the count.
     */
    public int callCount() {
        return requests.size();
    }

    /**
     * The request at a position.
     *
     * @param position the zero-based index.
     * @return the recorded request.
     */
    public RecordedRequest request(int position) {
        return requests.get(position);
    }

    @Override
    public CompletableFuture<HttpResponse<String>> sendAsync(HttpRequest request) {
        requests.add(new RecordedRequest(
                request.uri(), request.method(), request.headers(), bodyOf(request)));

        Object stub;

        synchronized (this) {
            stub = stubs.get(Math.min(index, stubs.size() - 1));
            index += 1;
        }

        if (stub == NEVER_RESPONDS) {
            return new CompletableFuture<>();
        }

        if (stub instanceof Throwable) {
            CompletableFuture<HttpResponse<String>> failed = new CompletableFuture<>();
            failed.completeExceptionally((Throwable) stub);

            return failed;
        }

        return CompletableFuture.completedFuture(
                new StubHttpResponse((StubResponse) stub, request));
    }

    /**
     * Reads back the body a request would have sent.
     *
     * <p>A {@link HttpRequest.BodyPublisher} is a {@link Flow.Publisher}, so the
     * only way to see its content is to subscribe to it — which is what the JDK's
     * own body subscribers are for.
     */
    private static String bodyOf(HttpRequest request) {
        Optional<HttpRequest.BodyPublisher> publisher = request.bodyPublisher();

        if (!publisher.isPresent() || publisher.get().contentLength() == 0) {
            return null;
        }

        HttpResponse.BodySubscriber<String> subscriber =
                HttpResponse.BodySubscribers.ofString(StandardCharsets.UTF_8);
        publisher.get().subscribe(new ByteBufferRelay(subscriber));

        return subscriber.getBody().toCompletableFuture().join();
    }

    /** Feeds a publisher's buffers into a body subscriber. */
    private static final class ByteBufferRelay implements Flow.Subscriber<ByteBuffer> {
        private final HttpResponse.BodySubscriber<String> target;

        ByteBufferRelay(HttpResponse.BodySubscriber<String> target) {
            this.target = target;
        }

        @Override
        public void onSubscribe(Flow.Subscription subscription) {
            target.onSubscribe(subscription);
        }

        @Override
        public void onNext(ByteBuffer item) {
            target.onNext(Collections.singletonList(item));
        }

        @Override
        public void onError(Throwable throwable) {
            target.onError(throwable);
        }

        @Override
        public void onComplete() {
            target.onComplete();
        }
    }

    /** A response the SDK cannot tell from one the JDK client produced. */
    private static final class StubHttpResponse implements HttpResponse<String> {
        private final StubResponse stub;
        private final HttpRequest request;
        private final HttpHeaders headers;

        StubHttpResponse(StubResponse stub, HttpRequest request) {
            this.stub = stub;
            this.request = request;
            this.headers = HttpHeaders.of(stub.headerMap(), (name, value) -> true);
        }

        @Override
        public int statusCode() {
            return stub.statusCode();
        }

        @Override
        public HttpRequest request() {
            return request;
        }

        @Override
        public Optional<HttpResponse<String>> previousResponse() {
            return Optional.empty();
        }

        @Override
        public HttpHeaders headers() {
            return headers;
        }

        @Override
        public String body() {
            return stub.bodyText();
        }

        @Override
        public Optional<SSLSession> sslSession() {
            return Optional.empty();
        }

        @Override
        public URI uri() {
            return request.uri();
        }

        @Override
        public java.net.http.HttpClient.Version version() {
            return java.net.http.HttpClient.Version.HTTP_1_1;
        }
    }

    /**
     * Convenience for the common case of one JSON response.
     *
     * @param json the body to serve.
     * @return an exchange serving it for every request.
     */
    public static StubExchange serving(String json) {
        return new StubExchange(StubResponse.json(json));
    }
}
