@IsTest
private class SourcesTest {
    @IsTest
    static void projectionsCopyFieldsOneForOne() {
        Nonprofit nonprofit = new Nonprofit(FixtureMock.sampleOrganization('411787097'));

        Pub78Source pub78 = Sources.getPub78(nonprofit);
        Assert.areEqual(true, pub78.verified);
        Assert.areEqual('411787097', pub78.ein);
        Assert.areEqual('PC', pub78.indicator);
        Assert.areEqual(1, pub78.organization_types.size());

        BmfSource bmf = Sources.getBmf(nonprofit);
        Assert.areEqual(true, bmf.status);
        Assert.areEqual('03', bmf.subsection);
        Assert.areEqual('Charitable Organization', bmf.subsection_description);

        OfacSource ofac = Sources.getOfac(nonprofit);
        Assert.isTrue(ofac.status.contains('No OFAC SDN match'));
    }

    @IsTest
    static void anAbsentSourceIsNullNotAnEmptyView() {
        Nonprofit nonprofit = new Nonprofit(new Map<String, Object>{ 'ein' => '411787097' });

        Assert.isNull(Sources.getPub78(nonprofit));
        Assert.isNull(Sources.getBmf(nonprofit));
        Assert.isNull(Sources.getAroe(nonprofit));
        Assert.isNull(Sources.getOfac(nonprofit));
    }

    @IsTest
    static void aSourceReturnedAsNullIsStillPresent() {
        Nonprofit nonprofit = new Nonprofit(new Map<String, Object>{ 'pub78_verified' => null });
        Pub78Source pub78 = Sources.getPub78(nonprofit);

        Assert.isNotNull(pub78, 'The API returned the field, so the source is present.');
        Assert.isTrue(pub78.has('verified'));
        Assert.isNull(pub78.verified);
    }

    @IsTest
    static void projectionsDeriveNothing() {
        Nonprofit nonprofit = new Nonprofit(new Map<String, Object>{ 'pub78_verified' => false });
        Pub78Source pub78 = Sources.getPub78(nonprofit);

        Assert.areEqual(false, pub78.verified);
        Assert.areEqual(1, pub78.keys().size(), 'Nothing beyond what the API returned.');
    }

    @IsTest
    static void aroeMapsThePrefixedListDate() {
        Nonprofit nonprofit = new Nonprofit(new Map<String, Object>{
            'revocation_code' => 'A',
            'aroe_list_published_date' => '2026-07-01'
        });
        AroeSource aroe = Sources.getAroe(nonprofit);

        Assert.areEqual('A', aroe.revocation_code);
        Assert.areEqual('2026-07-01', aroe.list_published_date);
    }

    @IsTest
    static void nullNonprofitYieldsNull() {
        Assert.isNull(Sources.getPub78(null));
    }
}
