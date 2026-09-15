/**
 * EX-14 — How fresh the underlying data is.
 *
 * Every finding on a record is as old as the extract it came from. A clean result
 * from a two-year-old extract is a clean result about two years ago, which is a
 * different statement from the one most workflows think they are making.
 */
@IsTest
private class Ex14DataFreshness {
    /** A re-review threshold. Yours belongs in your policy, not in the SDK. */
    private static final Integer STALE_AFTER_DAYS = 180;

    @IsTest
    static void readsHowOldTheFindingsAre() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        Map<String, Integer> oldestByEin = new Map<String, Integer>();

        Test.startTest();

        for (
            String ein : new List<String>{
                ExampleFixtures.PUBLIC_CHARITY, ExampleFixtures.STALE_DATA
            }
        ) {
            Nonprofit nonprofit = ExampleApiMock.client().nonprofits.check(ein).nonprofit;

            ExampleOutput.heading(nonprofit.organization_name + ' (' + ein + ')');

            Map<String, String> sources = new Map<String, String>{
                'most_recent_bmf' => nonprofit.most_recent_bmf,
                'most_recent_pub78' => nonprofit.most_recent_pub78,
                'organization_info_last_modified' => nonprofit.organization_info_last_modified,
                'report_date' => nonprofit.report_date
            };

            for (String label : sources.keySet()) {
                String value = sources.get(label);
                Integer age = ExampleDates.ageInDays(value);

                ExampleOutput.field(
                    label,
                    ExampleOutput.render(value) + (age == null ? '' : '  (' + age + ' days ago)')
                );
            }

            Integer oldest = ExampleScreening.oldestSourceAgeDays(nonprofit);
            oldestByEin.put(ein, oldest);

            System.debug('');

            String oldestLabel = oldest == null ? null : oldest + ' days';
            String pastTheRule = oldest == null
                ? 'unknown - no source date could be read'
                : String.valueOf(oldest > STALE_AFTER_DAYS);

            ExampleOutput.field('oldest source', oldestLabel);
            ExampleOutput.field('past a ' + STALE_AFTER_DAYS + '-day rule', pastTheRule);
        }

        Test.stopTest();

        // The dates are relative to today, so these hold however long after
        // they were written the example runs.
        Integer fresh = oldestByEin.get(ExampleFixtures.PUBLIC_CHARITY);
        Integer stale = oldestByEin.get(ExampleFixtures.STALE_DATA);

        Assert.isNotNull(fresh, 'The API dates should have parsed.');
        Assert.isNotNull(stale, 'The API dates should have parsed.');
        Assert.isFalse(fresh > STALE_AFTER_DAYS, 'The clean record is inside the window.');
        Assert.isTrue(stale > STALE_AFTER_DAYS, 'The stale record is well outside it.');

        ExampleOutput.note(
            'The second organization has nothing adverse on its record and every source is\n' +
            'well over a year old. Both facts are true, and a workflow that reads only the\n' +
            'first has re-verified nothing.\n\n' +
            'The API formats dates for display, not for machines. Parsing them means\n' +
            'assuming a format and a time zone, which is why the SDK hands them back as\n' +
            'String and leaves the assumption to ExampleDates, where it is visible. Note\n' +
            'that it does not use Datetime.parse: that follows the running user\'s locale,\n' +
            'so the same record would parse in one org and fail in another.'
        );
    }
}
