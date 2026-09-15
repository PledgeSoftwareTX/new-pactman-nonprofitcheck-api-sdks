/**
 * Reads the timestamps the API returns.
 *
 * The API formats dates for display, not for machines: `M/DD/YYYY h:mm:ss AM`.
 * Parsing them means assuming a format and a time zone, which is why the SDK
 * hands them back as `String` and leaves the assumption to code like this,
 * where it is visible and can be argued with.
 *
 * `Datetime.parse` is deliberately not used: it follows the running user's
 * locale, so the same record would parse in one org and fail in another. This
 * splits the string instead.
 */
@IsTest
public class ExampleDates {
    /**
     * How many days ago a timestamp was, or `null` when the API returned no
     * value or one this reader cannot parse.
     *
     * An unparseable date returns `null` rather than zero: "today" is a much
     * worse answer than "I do not know".
     */
    public static Integer ageInDays(String value) {
        Datetime parsed = parse(value);

        if (parsed == null) {
            return null;
        }

        Long elapsed = Datetime.now().getTime() - parsed.getTime();

        return (Integer) (elapsed / (1000L * 60L * 60L * 24L));
    }

    /** Parses an API timestamp, or returns `null` when the shape is unfamiliar. */
    public static Datetime parse(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        List<String> parts = value.trim().split(' ');

        if (parts.size() < 2) {
            return null;
        }

        List<String> date = parts[0].split('/');
        List<String> time = parts[1].split(':');

        if (date.size() != 3 || time.size() != 3) {
            return null;
        }

        try {
            Integer month = Integer.valueOf(date[0]);
            Integer day = Integer.valueOf(date[1]);
            Integer year = Integer.valueOf(date[2]);
            Integer hour = Integer.valueOf(time[0]);
            Integer minute = Integer.valueOf(time[1]);
            Integer second = Integer.valueOf(time[2]);

            if (parts.size() > 2) {
                String meridiem = parts[2].toUpperCase();

                if (meridiem == 'PM' && hour < 12) {
                    hour += 12;
                } else if (meridiem == 'AM' && hour == 12) {
                    hour = 0;
                }
            }

            return Datetime.newInstance(year, month, day, hour, minute, second);
        } catch (Exception unparseable) {
            return null;
        }
    }
}
