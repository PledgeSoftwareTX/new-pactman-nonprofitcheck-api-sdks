package org.pactman.nonprofitcheckplus.devtools;

/** One difference between two response signatures. */
public final class Change {

    /** What kind of difference this is. */
    public enum Kind {
        /** A path the earlier signature had and the later one does not. */
        REMOVED,
        /** A path both have, carrying a different token. */
        CHANGED,
        /** A path only the later signature has. */
        ADDED
    }

    private final Kind kind;
    private final String path;
    private final String token;
    private final String from;
    private final String to;

    private Change(Kind kind, String path, String token, String from, String to) {
        this.kind = kind;
        this.path = path;
        this.token = token;
        this.from = from;
        this.to = to;
    }

    /**
     * A path that disappeared.
     *
     * @param path  the signature path.
     * @param token the token it used to carry.
     * @return the change.
     */
    public static Change removed(String path, String token) {
        return new Change(Kind.REMOVED, path, token, null, null);
    }

    /**
     * A path that appeared.
     *
     * @param path  the signature path.
     * @param token the token it carries.
     * @return the change.
     */
    public static Change added(String path, String token) {
        return new Change(Kind.ADDED, path, token, null, null);
    }

    /**
     * A path whose token moved.
     *
     * @param path the signature path.
     * @param from the token before.
     * @param to   the token after.
     * @return the change.
     */
    public static Change changed(String path, String from, String to) {
        return new Change(Kind.CHANGED, path, null, from, to);
    }

    /**
     * What kind of difference this is.
     *
     * @return the kind.
     */
    public Kind kind() {
        return kind;
    }

    /**
     * The signature path.
     *
     * @return the path.
     */
    public String path() {
        return path;
    }

    /**
     * The token, for an addition or a removal.
     *
     * @return the token, or {@code null} for a change.
     */
    public String token() {
        return token;
    }

    /**
     * The token before, for a change.
     *
     * @return the earlier token, or {@code null}.
     */
    public String from() {
        return from;
    }

    /**
     * The token after, for a change.
     *
     * @return the later token, or {@code null}.
     */
    public String to() {
        return to;
    }

    @Override
    public String toString() {
        return kind == Kind.CHANGED
                ? "~ " + path + ": " + from + " → " + to
                : (kind == Kind.REMOVED ? "- " : "+ ") + path + " (" + token + ")";
    }
}
