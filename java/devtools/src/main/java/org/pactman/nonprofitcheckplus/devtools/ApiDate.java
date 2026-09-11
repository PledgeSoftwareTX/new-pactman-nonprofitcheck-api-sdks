package org.pactman.nonprofitcheckplus.devtools;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.Locale;

/**
 * The date format the API uses, and the arithmetic the freshness examples need.
 *
 * <p>The API formats every date as {@code M/dd/yyyy h:mm:ss a}. It is a display
 * format, not ISO 8601, so anything that parses it is guessing at a locale and a
 * time zone — which is exactly why the SDK hands these fields back as strings
 * and leaves the decision here, where an example can be explicit about it.
 */
public final class ApiDate {

    private static final DateTimeFormatter FORMAT =
            DateTimeFormatter.ofPattern("M/dd/yyyy h:mm:ss a", Locale.US);

    private ApiDate() {
    }

    /**
     * A date this many days in the past, formatted the way the API formats one.
     *
     * <p>Fixture dates are generated relative to today so the freshness examples
     * stay meaningful however long after they were written they are run.
     *
     * @param daysAgo how many days back.
     * @return the formatted date.
     */
    public static String daysAgo(long daysAgo) {
        return FORMAT.format(LocalDateTime.now().minusDays(daysAgo));
    }

    /**
     * How many days ago a date the API returned was.
     *
     * @param apiDate the date as the API formatted it, or {@code null}.
     * @return the age in days, or {@code null} when the value is absent or
     *         cannot be read as a date.
     */
    public static Long ageInDays(String apiDate) {
        if (apiDate == null || apiDate.trim().isEmpty()) {
            return null;
        }

        try {
            LocalDateTime when = LocalDateTime.parse(apiDate.trim(), FORMAT);

            return ChronoUnit.DAYS.between(
                    when.atZone(ZoneId.systemDefault()).toInstant(), Instant.now());
        } catch (java.time.format.DateTimeParseException unparseable) {
            // A format the API changed, or a value that was never a date. The
            // caller decides what that means; guessing here would be worse.
            return null;
        }
    }
}
