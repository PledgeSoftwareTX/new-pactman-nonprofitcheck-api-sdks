package org.pactman.nonprofitcheckplus.models;

import java.util.Map;

/**
 * A grouped view over one source's findings on a {@link Nonprofit}.
 *
 * <p>A projection, not a derivation: every key is copied 1:1 from a field the
 * API returned. Nothing here computes an "approved", "eligible" or "safe"
 * verdict, and nothing infers a value from another field.
 *
 * <p>Only the keys the API actually returned are present, so
 * {@link DataObject#has(String)} still answers "did the API send this?" exactly
 * as it does on the organization itself.
 */
public abstract class SourceView extends DataObject {

    /**
     * Initializes the view over the projected fields.
     *
     * @param fields the fields copied from the organization, in source order.
     */
    protected SourceView(Map<String, Object> fields) {
        super(fields);
    }
}
