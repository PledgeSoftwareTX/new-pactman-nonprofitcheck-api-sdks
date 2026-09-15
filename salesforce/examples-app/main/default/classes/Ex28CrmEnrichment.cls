/**
 * EX-28 — Enriching Account records.
 *
 * Writing API values into your own records is where "null" and "not returned"
 * stop being an academic distinction: overwriting a good local value with a null
 * the API happened not to return is data loss, and it is silent.
 *
 * This example also shows the ordering rule Apex forces on you. **Callouts are
 * illegal after DML in the same transaction**, so the check happens first and
 * the DML happens last. Get that backwards and the org throws
 * `CalloutException: You have uncommitted work pending`.
 */
@IsTest
private class Ex28CrmEnrichment {
    @IsTest
    static void neverOverwritesGoodDataWithANull() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        // What the org holds today, built in memory. The second row has a
        // hand-entered address the IRS record does not carry.
        Map<String, Account> accounts = new Map<String, Account>{
            ExampleFixtures.PUBLIC_CHARITY => new Account(
                Name = 'Meals Today',
                BillingStreet = '50 Lowell Ave',
                BillingPostalCode = '01085'
            ),
            ExampleFixtures.SPARSE_IDENTITY => new Account(
                Name = 'Quiet Harbor Trust',
                BillingStreet = 'PO Box 118',
                BillingPostalCode = '04856'
            )
        };

        List<String> eins = new List<String>(accounts.keySet());

        // 1. Every callout first. No DML has happened yet.
        Test.startTest();
        BulkCheckResult result = ExampleApiMock.client().nonprofits.checkBulk(eins);
        Test.stopTest();

        Map<String, Nonprofit> byEin = result.byEin();

        // 2. Then the enrichment, in memory.
        for (String ein : eins) {
            Account record = accounts.get(ein);
            Nonprofit nonprofit = byEin.get(ein);

            ExampleOutput.heading(record.Name + ' (' + ein + ')');

            if (nonprofit == null) {
                ExampleOutput.bullet('No record returned. Nothing is written; the row is untouched.');
                continue;
            }

            record.Name = resolveValue('Name', record.Name, nonprofit, 'organization_name');
            record.BillingStreet = resolveValue(
                'BillingStreet',
                record.BillingStreet,
                nonprofit,
                'address_line1'
            );
            record.BillingPostalCode = resolveValue(
                'BillingPostalCode',
                record.BillingPostalCode,
                nonprofit,
                'zip'
            );

            // A provenance stamp is what makes the next run able to tell a
            // stale value from a fresh one.
            record.Description = 'Verified from Pactman on ' + nonprofit.report_date;
            ExampleOutput.field('Description', record.Description);
        }

        // 3. And only now the DML.
        insert accounts.values();

        ExampleOutput.heading('The rows after the sync');

        for (Account saved : [
            SELECT Name, BillingStreet, BillingPostalCode
            FROM Account
            ORDER BY Name
        ]) {
            ExampleOutput.field(
                saved.Name,
                saved.BillingStreet + ' | ' + saved.BillingPostalCode
            );
        }

        // The IRS record carries no ZIP for the second organization. The
        // hand-entered one survives.
        Assert.areEqual(
            '04856',
            accounts.get(ExampleFixtures.SPARSE_IDENTITY).BillingPostalCode,
            'A null from the API must not erase a hand-entered postal code.'
        );

        // Where the API did return a value, it wins.
        Assert.areEqual(
            'MEALS TODAY EXAMPLE NONPROFIT',
            accounts.get(ExampleFixtures.PUBLIC_CHARITY).Name
        );
        Assert.areEqual(
            '01085-2643',
            accounts.get(ExampleFixtures.PUBLIC_CHARITY).BillingPostalCode
        );

        ExampleOutput.note(
            'The rule is one line: write when the API returned a value, keep what you have\n' +
            'when it returned null or nothing at all. has() is what makes that expressible -\n' +
            'without it both cases read as null, and the second row loses a hand-entered\n' +
            'postal code to a field the IRS extract simply does not carry.\n\n' +
            'The transaction order is not stylistic. Callouts must precede DML, which is\n' +
            'why this reads as check-everything, merge-in-memory, save-once. From a trigger\n' +
            'there is no legal order at all: use CheckQueueable.\n\n' +
            'Storing these records may bring retention and privacy obligations of your own.\n' +
            'That is your call, not the SDK\'s.'
        );
    }

    /**
     * Three cases, and only one of them is a write.
     *
     * Returns the value to store, and logs which case applied.
     */
    private static String resolveValue(
        String column,
        String current,
        Nonprofit nonprofit,
        String field
    ) {
        if (!nonprofit.has(field)) {
            ExampleOutput.field(column, 'kept "' + current + '" - API returned no field');

            return current;
        }

        Object value = nonprofit.get(field);

        if (value == null) {
            ExampleOutput.field(column, 'kept "' + current + '" - API returned null');

            return current;
        }

        ExampleOutput.field(column, 'updated to "' + value + '"');

        return String.valueOf(value);
    }
}
