/**
 * EX-02 — EIN normalization and validation.
 *
 * Every accepted spelling of an EIN, every rejected one, and what the SDK says
 * about each. No callout is made: this all happens locally, which is the point —
 * a malformed EIN should never cost a billable call, and in Apex it should never
 * cost one of the transaction's 100 callouts either.
 */
@IsTest
private class Ex02EinNormalization {
    @IsTest
    static void normalizesAndRejectsLocally() {
        ExampleOutput.heading('Accepted spellings');

        for (String input : new List<String>{ '411787097', '41-1787097', '  41-1787097  ' }) {
            ExampleOutput.field('"' + input + '"', Ein.normalize(input));
            Assert.areEqual('411787097', Ein.normalize(input));
        }

        ExampleOutput.heading('Rejected values');

        for (
            String input : new List<String>{
                '41178709', '4117870977', '41-178709', '41 1787097', 'abcdefghi', '', null
            }
        ) {
            String label = input == null ? 'null' : '"' + input + '"';

            try {
                Ein.normalize(input);
                Assert.fail(label + ' should not have been accepted.');
            } catch (ValidationException e) {
                ExampleOutput.field(label, e.getMessage(), 16);
                Assert.areEqual(ErrorOrigin.LOCAL, e.origin);
            }
        }

        // A batch reports every failure at once, by index, so that a caller
        // fixes one upload rather than discovering the next bad row on the next
        // attempt.
        ExampleOutput.heading('A batch reports every failure at once');

        try {
            Ein.normalizeMany(new List<String>{ '411787097', 'nope', '996589560', '1234' });
            Assert.fail('The batch should have been rejected.');
        } catch (ValidationException e) {
            System.debug('  ' + e.getMessage());

            for (ValidationIssue issue : e.issues) {
                ExampleOutput.bullet(
                    'index ' + issue.index + ': ' + issue.value + ' - ' + issue.message
                );
                Assert.isNotNull(issue.index, 'A batch issue should name the row it came from.');
            }

            Assert.areEqual(2, e.issues.size(), 'Both bad rows should be reported.');
        }

        // Chunking is explicit here, and it matters more in Apex than
        // elsewhere: a transaction is capped at 100 callouts, so the number of
        // batches is something you have to reason about before you loop.
        ExampleOutput.heading('Splitting a larger list into acceptable batches');

        List<String> many = new List<String>();

        for (Integer index = 0; index < 120; index++) {
            many.add('411787097');
        }

        List<List<String>> batches = Ein.chunk(many);

        ExampleOutput.field('EINs', many.size());
        ExampleOutput.field('Constants.MAX_BULK_EINS', Constants.MAX_BULK_EINS);
        ExampleOutput.field('batches', batches.size());
        ExampleOutput.field('last batch size', batches[batches.size() - 1].size());

        Assert.areEqual(3, batches.size());
        Assert.areEqual(20, batches[2].size());

        ExampleOutput.heading('What validation does not tell you');
        ExampleOutput.field('Ein.isValid("00-0000000")', Ein.isValid('00-0000000'));

        Assert.isTrue(Ein.isValid('00-0000000'), 'It is shaped like an EIN, and that is all.');

        ExampleOutput.note(
            'Formatting validation confirms only that a value is shaped like an EIN. It\n' +
            'says nothing about tax-exempt status, identity, eligibility, or good standing.\n' +
            'No IRS prefix rules are applied.'
        );
    }
}
