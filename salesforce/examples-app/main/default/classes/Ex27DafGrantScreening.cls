/**
 * EX-27 — Donor-advised fund grant screening.
 *
 * A DAF has obligations a donation platform does not. A grant to a private
 * foundation triggers expenditure responsibility; an OFAC finding stops the
 * grant outright; and "the API returned no OFAC data" is not a clean screen.
 *
 * Same API responses as ex-26, stricter policy. Both are correct.
 */
@IsTest
private class Ex27DafGrantScreening {
    @IsTest
    static void appliesAStricterPolicyToTheSameEvidence() {
        Test.setMock(HttpCalloutMock.class, new ExampleApiMock());

        List<String> candidates = new List<String>{
            ExampleFixtures.PUBLIC_CHARITY,
            ExampleFixtures.PRIVATE_FOUNDATION,
            ExampleFixtures.OFAC_MATCH,
            ExampleFixtures.OFAC_UNAVAILABLE,
            ExampleFixtures.CONFLICTED
        };

        Test.startTest();
        BulkCheckResult result = ExampleApiMock.client().nonprofits.checkBulk(candidates);
        Test.stopTest();

        Map<String, Nonprofit> byEin = result.byEin();
        Map<String, String> decisions = new Map<String, String>();

        for (String ein : candidates) {
            Nonprofit nonprofit = byEin.get(ein);

            if (nonprofit == null) {
                ExampleOutput.heading(ein + ' - no record');
                decisions.put(ein, 'HOLD');
                ExampleOutput.field('decision', 'HOLD - no record to screen against');
                continue;
            }

            ExampleOutput.heading(nonprofit.organization_name + ' (' + ein + ')');

            String ofac = ExampleScreening.ofacState(nonprofit);
            BmfSource bmf = Sources.getBmf(nonprofit);

            Boolean privateFoundation =
                bmf != null &&
                bmf.subsection_description != null &&
                bmf.subsection_description.toLowerCase().contains('private foundation');

            ExampleOutput.field('ofac', ofac);
            ExampleOutput.field('pub78_verified', nonprofit.pub78_verified);
            ExampleOutput.field(
                'classification',
                bmf == null ? null : bmf.subsection_description
            );
            ExampleOutput.field('bmf/pub78 conflict', nonprofit.irs_bmf_pub78_conflict);

            // The DAF's policy. Anything other than an affirmative OFAC
            // no-match stops the grant, because an unscreened grant and a
            // screened one are not the same thing.
            String decision;
            String outcome;

            if (ofac != ExampleScreening.OFAC_NO_MATCH) {
                outcome = 'STOP';
                decision = 'STOP - OFAC screening did not return an affirmative no-match';
            } else if (nonprofit.pub78_verified != true) {
                outcome = 'STOP';
                decision = 'STOP - not listed in Publication 78';
            } else if (nonprofit.irs_bmf_pub78_conflict == true) {
                outcome = 'HOLD';
                decision = 'HOLD - the IRS sources disagree';
            } else if (privateFoundation) {
                outcome = 'HOLD';
                decision = 'HOLD - expenditure responsibility applies to a private foundation';
            } else {
                outcome = 'PROCEED';
                decision = 'PROCEED under this fund\'s policy';
            }

            decisions.put(ein, outcome);
            ExampleOutput.field('decision', decision);
        }

        Assert.areEqual('PROCEED', decisions.get(ExampleFixtures.PUBLIC_CHARITY));
        Assert.areEqual(
            'HOLD',
            decisions.get(ExampleFixtures.PRIVATE_FOUNDATION),
            'Expenditure responsibility, not a problem with the organization.'
        );
        Assert.areEqual('STOP', decisions.get(ExampleFixtures.OFAC_MATCH));
        Assert.areEqual(
            'STOP',
            decisions.get(ExampleFixtures.OFAC_UNAVAILABLE),
            'The field came back with no value: this fund treats that as unscreened.'
        );
        Assert.areEqual('STOP', decisions.get(ExampleFixtures.CONFLICTED));

        // ex-26 proceeded on the record this fund holds. Both are defensible.
        ExampleOutput.note(
            'Two organizations here have no OFAC match. One of them returned the field with\n' +
            'no value, and this fund stops on it - because "we did not screen" and "we\n' +
            'screened and found nothing" are different sentences to write in a file that a\n' +
            'regulator may later read.\n\n' +
            'Compare with ex-26: a donation platform reading these same responses\n' +
            'reasonably proceeds where this fund holds. The SDK returns identical data to\n' +
            'both; the policy is the part you own.'
        );
    }
}
