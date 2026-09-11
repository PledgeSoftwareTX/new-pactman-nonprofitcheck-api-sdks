package org.pactman.nonprofitcheckplus;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Arrays;
import java.util.Collections;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.pactman.nonprofitcheckplus.exceptions.PactmanValidationException;

class EinTest {

    @ParameterizedTest
    @ValueSource(strings = {"411787097", "41-1787097", "  41-1787097  "})
    @DisplayName("normalizes every accepted spelling to nine digits")
    void normalizesAcceptedSpellings(String input) {
        assertEquals("411787097", Ein.normalize(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "41178709", "4117870977", "41-178709", "abcdefghi", "41 1787097", "41--1787097", ""
    })
    @DisplayName("rejects anything not shaped like an EIN")
    void rejectsMalformedEins(String input) {
        assertFalse(Ein.isValid(input));
        assertThrows(PactmanValidationException.class, () -> Ein.normalize(input));
    }

    @Test
    @DisplayName("rejects null without a NullPointerException")
    void rejectsNull() {
        assertFalse(Ein.isValid(null));

        PactmanValidationException failure =
                assertThrows(PactmanValidationException.class, () -> Ein.normalize(null));

        assertTrue(failure.getMessage().contains("required"));
    }

    @Test
    @DisplayName("keeps order and duplicates when normalizing a list")
    void keepsOrderAndDuplicates() {
        assertEquals(
                Arrays.asList("411787097", "996589560", "411787097"),
                Ein.normalizeAll(Arrays.asList("41-1787097", "996589560", "411787097")));
    }

    @Test
    @DisplayName("reports every invalid EIN in one exception, by index")
    void reportsEveryInvalidEin() {
        PactmanValidationException failure = assertThrows(
                PactmanValidationException.class,
                () -> Ein.normalizeAll(Arrays.asList("411787097", "nope", "996589560", "")));

        assertEquals(2, failure.issues().size());
        assertEquals(Integer.valueOf(1), failure.issues().get(0).index());
        assertEquals(Integer.valueOf(3), failure.issues().get(1).index());
        assertEquals("nope", failure.issues().get(0).value());
        assertTrue(failure.getMessage().contains("2 of 4"));
        assertTrue(failure.getMessage().contains("No request was sent"));
    }

    @Test
    @DisplayName("accepts an empty list, leaving the batch rules to the caller")
    void acceptsEmptyList() {
        assertEquals(Collections.emptyList(), Ein.normalizeAll(Collections.<String>emptyList()));
    }

    @Test
    @DisplayName("validates formatting only, and says nothing about exempt status")
    void validatesFormattingOnly() {
        // 00-0000000 is not an issued EIN; the SDK deliberately does not know that.
        assertTrue(Ein.isValid("00-0000000"));
        assertEquals("000000000", Ein.normalize("00-0000000"));
    }
}
