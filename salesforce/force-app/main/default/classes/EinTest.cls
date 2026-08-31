@IsTest
private class EinTest {
    @IsTest
    static void normalizesBothAcceptedShapes() {
        Assert.areEqual('411787097', Ein.normalize('41-1787097'));
        Assert.areEqual('411787097', Ein.normalize('411787097'));
        Assert.areEqual('411787097', Ein.normalize('  41-1787097  '));
    }

    @IsTest
    static void rejectsNull() {
        try {
            Ein.normalize(null);
            Assert.fail('Expected a ValidationException.');
        } catch (ValidationException e) {
            Assert.areEqual('EIN is required.', e.getMessage());
            Assert.areEqual(ErrorCategory.VALIDATION, e.category);
            Assert.areEqual(ErrorOrigin.LOCAL, e.origin);
        }
    }

    @IsTest
    static void rejectsEmpty() {
        try {
            Ein.normalize('   ');
            Assert.fail('Expected a ValidationException.');
        } catch (ValidationException e) {
            Assert.areEqual('EIN is empty.', e.getMessage());
        }
    }

    @IsTest
    static void rejectsWrongShapeAndQuotesWhatItSaw() {
        try {
            Ein.normalize('4-11787097');
            Assert.fail('Expected a ValidationException.');
        } catch (ValidationException e) {
            Assert.areEqual(
                'EIN must be 9 digits, optionally hyphenated as XX-XXXXXXX. Received "4-11787097".',
                e.getMessage()
            );
        }
    }

    @IsTest
    static void reportsPositionWhenGivenOne() {
        try {
            Ein.normalize('nope', 3);
            Assert.fail('Expected a ValidationException.');
        } catch (ValidationException e) {
            Assert.isTrue(e.getMessage().startsWith('EIN at index 3 must be 9 digits'), e.getMessage());
            Assert.areEqual(3, e.issues[0].index);
            Assert.areEqual('nope', e.issues[0].value);
        }
    }

    @IsTest
    static void normalizeManyKeepsOrderAndDuplicates() {
        List<String> result = Ein.normalizeMany(
            new List<String>{ '41-1787097', '411787097', '99-6589560' }
        );

        Assert.areEqual(new List<String>{ '411787097', '411787097', '996589560' }, result);
    }

    @IsTest
    static void normalizeManyReportsEveryFailureAtOnce() {
        try {
            Ein.normalizeMany(new List<String>{ '411787097', 'bad', '996589560', '' , 'also-bad' });
            Assert.fail('Expected a ValidationException.');
        } catch (ValidationException e) {
            Assert.areEqual(
                '3 of 5 EINs are invalid (at index 1, 3, 4). No request was sent.',
                e.getMessage()
            );
            Assert.areEqual(3, e.issues.size());
            Assert.areEqual(1, e.issues[0].index);
            Assert.areEqual(4, e.issues[2].index);
        }
    }

    @IsTest
    static void isValidNeverThrows() {
        Assert.isTrue(Ein.isValid('41-1787097'));
        Assert.isFalse(Ein.isValid(null));
        Assert.isFalse(Ein.isValid('12345'));
    }

    @IsTest
    static void chunkSplitsAtTheBulkLimit() {
        List<String> eins = new List<String>();

        for (Integer i = 0; i < 120; i++) {
            eins.add('411787097');
        }

        List<List<String>> batches = Ein.chunk(eins);

        Assert.areEqual(3, batches.size());
        Assert.areEqual(Constants.MAX_BULK_EINS, batches[0].size());
        Assert.areEqual(Constants.MAX_BULK_EINS, batches[1].size());
        Assert.areEqual(20, batches[2].size());
        Assert.areEqual(0, Ein.chunk(new List<String>()).size());
    }
}
