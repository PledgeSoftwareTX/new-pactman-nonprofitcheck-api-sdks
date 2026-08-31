@IsTest
private class DataObjectTest {
    @IsTest
    static void hasDistinguishesAbsentFromNull() {
        Nonprofit nonprofit = new Nonprofit(new Map<String, Object>{ 'ofac_status' => null });

        Assert.isTrue(nonprofit.has('ofac_status'), 'The API returned the field, as null.');
        Assert.isFalse(nonprofit.has('bmf_status'), 'The API did not return the field.');
        Assert.isNull(nonprofit.get('ofac_status'));
        Assert.isNull(nonprofit.get('bmf_status'));
    }

    @IsTest
    static void readsEveryNumericShapeJsonCanProduce() {
        Map<String, Object> decoded = (Map<String, Object>) JSON.deserializeUntyped(
            '{"a":42,"b":42.5,"c":9007199254740993,"d":"not a number"}'
        );
        ApiErrorDetail detail = new ApiErrorDetail(decoded);

        Assert.areEqual(42, detail.getInteger('a'));
        Assert.areEqual(42, detail.getInteger('b'), 'A decimal truncates toward zero.');
        Assert.areEqual(42.5, detail.getDecimal('b'));
        Assert.areEqual(9007199254740993L, detail.getDecimal('c').longValue());
        Assert.isNull(detail.getInteger('d'));
        Assert.isNull(detail.getInteger('missing'));
    }

    @IsTest
    static void typedGettersRefuseTheWrongType() {
        ApiErrorDetail detail = new ApiErrorDetail(
            new Map<String, Object>{ 'flag' => 'true', 'list' => 'nope', 'nested' => 7 }
        );

        Assert.isNull(detail.getBoolean('flag'), 'A string is not a Boolean.');
        Assert.isNull(detail.getList('list'));
        Assert.isNull(detail.getMap('nested'));
    }

    @IsTest
    static void getStringRendersNonStrings() {
        ApiErrorDetail detail = new ApiErrorDetail(
            new Map<String, Object>{ 'code' => 404, 'flag' => true }
        );

        Assert.areEqual('404', detail.getString('code'));
        Assert.areEqual('true', detail.getString('flag'));
        Assert.isNull(detail.getString('missing'));
    }

    @IsTest
    static void unknownFieldsSurviveWithoutAnUpgrade() {
        Nonprofit nonprofit = new Nonprofit(
            new Map<String, Object>{ 'a_field_added_next_quarter' => 'readable' }
        );

        Assert.areEqual('readable', nonprofit.get('a_field_added_next_quarter'));
        Assert.isTrue(nonprofit.keys().contains('a_field_added_next_quarter'));
    }

    @IsTest
    static void toMapIsACopy() {
        Map<String, Object> source = new Map<String, Object>{ 'ein' => '411787097' };
        Nonprofit nonprofit = new Nonprofit(source);

        nonprofit.toMap().put('ein', 'tampered');

        Assert.areEqual('411787097', nonprofit.ein);
    }

    @IsTest
    static void toleratesNullFields() {
        Nonprofit nonprofit = new Nonprofit(null);

        Assert.isFalse(nonprofit.has('ein'));
        Assert.areEqual(0, nonprofit.keys().size());
    }
}
