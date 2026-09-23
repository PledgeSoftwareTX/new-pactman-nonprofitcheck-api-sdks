@IsTest
private class NonprofitTest {
    @IsTest
    static void accessorsUseTheWireNames() {
        Nonprofit nonprofit = new Nonprofit(FixtureMock.sampleOrganization('41-1787097'));

        Assert.areEqual('411787097', nonprofit.ein);
        Assert.areEqual('Fixture Charitable Trust', nonprofit.organization_name);
        Assert.areEqual('Austin', nonprofit.city);
        Assert.areEqual('TX', nonprofit.state);
        Assert.areEqual(true, nonprofit.pub78_verified);
        Assert.areEqual(true, nonprofit.bmf_status);
        Assert.areEqual(false, nonprofit.irs_bmf_pub78_conflict);
    }

    @IsTest
    static void absentFieldsReadAsNullRatherThanThrowing() {
        Nonprofit nonprofit = new Nonprofit(new Map<String, Object>{ 'ein' => '411787097' });

        Assert.isNull(nonprofit.organization_name);
        Assert.isNull(nonprofit.pub78_verified);
        Assert.isNull(nonprofit.revocation_date);
        Assert.areEqual(0, nonprofit.organization_types.size());
    }

    @IsTest
    static void organizationTypesAreTyped() {
        Nonprofit nonprofit = new Nonprofit(FixtureMock.sampleOrganization('411787097'));
        List<OrganizationType> types = nonprofit.organization_types;

        Assert.areEqual(1, types.size());
        Assert.areEqual('PC', types[0].organization_type);
        Assert.areEqual('Contributions are deductible', types[0].deductibility_status_description);
    }

    @IsTest
    static void organizationTypesSkipsNullEntries() {
        Nonprofit nonprofit = new Nonprofit(new Map<String, Object>{
            'organization_types' => new List<Object>{ null, new Map<String, Object>{ 'organization_type' => 'PF' } }
        });

        Assert.areEqual(1, nonprofit.organization_types.size());
        Assert.areEqual('PF', nonprofit.organization_types[0].organization_type);
    }

    @IsTest
    static void ofacStatusIsProseNotAFlag() {
        Nonprofit nonprofit = new Nonprofit(FixtureMock.sampleOrganization('411787097'));

        Assert.isTrue(nonprofit.ofac_status.contains('No OFAC SDN match'), nonprofit.ofac_status);
    }

    @IsTest
    static void everyContractFieldIsReadable() {
        StaticResource resource = [
            SELECT Body FROM StaticResource WHERE Name = 'pactman_response_contract' LIMIT 1
        ];
        Map<String, Object> contract = (Map<String, Object>) JSON.deserializeUntyped(
            resource.Body.toString()
        );
        Map<String, Object> fields = (Map<String, Object>) contract.get('nonprofit');

        Nonprofit nonprofit = new Nonprofit(fields);

        for (String field : fields.keySet()) {
            Assert.isTrue(nonprofit.has(field), 'Contract field not readable: ' + field);
        }

        Assert.areEqual(43, fields.size(), 'The contract changed size; regenerate the accessors.');
    }
}
