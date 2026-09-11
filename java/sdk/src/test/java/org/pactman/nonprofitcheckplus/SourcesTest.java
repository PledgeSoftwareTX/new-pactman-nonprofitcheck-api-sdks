package org.pactman.nonprofitcheckplus;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.pactman.nonprofitcheckplus.support.Fixtures.nonprofit;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.pactman.nonprofitcheckplus.models.BmfSource;
import org.pactman.nonprofitcheckplus.models.Nonprofit;
import org.pactman.nonprofitcheckplus.models.OfacSource;
import org.pactman.nonprofitcheckplus.models.Pub78Source;

class SourcesTest {

    private static Nonprofit organization() {
        return new Nonprofit(nonprofit());
    }

    @Test
    @DisplayName("groups Publication 78 fields under their source-free names")
    void groupsPub78Fields() {
        Pub78Source pub78 = Sources.pub78(organization());

        assertNotNull(pub78);
        assertEquals(Boolean.TRUE, pub78.getVerified());
        assertEquals("Example Nonprofit", pub78.getOrganizationName());
        assertEquals("411787097", pub78.getEin());
        assertEquals("Westfield", pub78.getCity());
        assertEquals("MA", pub78.getState());
        assertEquals("0", pub78.getIndicator());
        assertEquals("12/12/2025 12:00:00 AM", pub78.getMostRecent());
        assertEquals(1, pub78.getOrganizationTypes().size());
        assertEquals("50%", pub78.getOrganizationTypes().get(0).getDeductibilityLimitation());
    }

    @Test
    @DisplayName("groups Business Master File fields, including the shared ones")
    void groupsBmfFields() {
        BmfSource bmf = Sources.bmf(organization());

        assertNotNull(bmf);
        assertEquals(Boolean.TRUE, bmf.getStatus());
        assertEquals("EXAMPLE NONPROFIT", bmf.getOrganizationName());
        assertEquals("03", bmf.getSubsection());
        assertEquals("501(c)(3) Public Charity", bmf.getSubsectionDescription());
        assertEquals("10", bmf.getFoundationCode());
        assertEquals("2024", bmf.getRulingYear());
        assertEquals("00", bmf.getFilingReqCode());
        assertEquals("12/09/2025 12:00:00 AM", bmf.getMostRecent());
    }

    @Test
    @DisplayName("returns null when the API returned nothing for a source")
    void returnsNullForAbsentSource() {
        Map<String, Object> bare = new LinkedHashMap<>();
        bare.put("ein", "411787097");
        bare.put("organization_name", "EXAMPLE NONPROFIT");

        Nonprofit organization = new Nonprofit(bare);

        assertNull(Sources.pub78(organization));
        assertNull(Sources.bmf(organization));
        assertNull(Sources.aroe(organization));
        assertNull(Sources.ofac(organization));
    }

    @Test
    @DisplayName("keeps an explicit negative distinguishable from an absent source")
    void keepsExplicitNegative() {
        Map<String, Object> fields = nonprofit();
        fields.put("pub78_verified", Boolean.FALSE);

        Pub78Source pub78 = Sources.pub78(new Nonprofit(fields));

        assertNotNull(pub78, "false is a finding, not an absence");
        assertEquals(Boolean.FALSE, pub78.getVerified());
    }

    @Test
    @DisplayName("keeps a field the API returned as null present in the view")
    void keepsNullFieldPresent() {
        Map<String, Object> fields = new LinkedHashMap<>();
        fields.put("ofac_status", null);

        OfacSource ofac = Sources.ofac(new Nonprofit(fields));

        assertNotNull(ofac, "a null the API sent is still something it sent");
        assertTrue(ofac.has("status"));
        assertNull(ofac.getStatus());
    }

    @Test
    @DisplayName("projects only the keys the API actually returned")
    void projectsOnlyReturnedKeys() {
        Map<String, Object> fields = new LinkedHashMap<>();
        fields.put("revocation_code", "R1");

        assertEquals(
                Collections.singleton("revocation_code"),
                Sources.aroe(new Nonprofit(fields)).fieldNames());
        assertFalse(Sources.aroe(new Nonprofit(fields)).has("revocation_date"));
    }

    @Test
    @DisplayName("copies values without deriving a verdict from them")
    void derivesNoVerdict() {
        OfacSource ofac = Sources.ofac(organization());

        assertNotNull(ofac);
        assertEquals(organization().getOfacStatus(), ofac.getStatus());
        // The finding is prose. Nothing in the SDK turns it into a boolean.
        assertFalse(ofac.toMap().containsKey("matched"));
        assertFalse(ofac.toMap().containsKey("clear"));
    }

    @Test
    @DisplayName("tolerates a null organization rather than throwing")
    void tolerlatesNullOrganization() {
        assertNull(Sources.pub78(null));
        assertNull(Sources.bmf(null));
        assertNull(Sources.aroe(null));
        assertNull(Sources.ofac(null));
    }

    @Test
    @DisplayName("drops an unresolvable null inside organization_types")
    void dropsNullOrganizationTypes() {
        Map<String, Object> fields = nonprofit();
        fields.put("organization_types", java.util.Arrays.asList(null, new LinkedHashMap<>()));

        assertEquals(1, new Nonprofit(fields).getOrganizationTypes().size());
    }
}
