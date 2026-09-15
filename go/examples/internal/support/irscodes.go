package support

import "strings"

// Local lookup tables for IRS codes the API returns without a description.
//
// The API already describes most classifications for you —
// subsection_description, foundation_code_description,
// foundation_type_description. Prefer those: they come from the source and
// change with it. Only fields returned as a bare code need a table, and a table
// you own is a table you have to maintain.
//
// Two rules make that safe:
//
//  1. Every lookup has an unknown-value fallback that keeps the original code
//     visible, so a value the IRS adds degrades to `code "42", meaning unknown
//     to this application` rather than to nil or to a wrong label.
//  2. A nil code is reported as nil, never as an unknown code. Reporting
//     "unknown code" for a field the API never sent invents a code, and someone
//     downstream will investigate it.
//
// Verify these against the current IRS Exempt Organizations Business Master
// File data dictionary and Publication 78 documentation before relying on them
// for a policy decision.

// IRS EO BMF FILING_REQ_CD — which annual return the organization files.
var filingRequirementCodes = map[string]string{
	"00": "No 990 return required",
	"01": "Form 990 or 990-EZ required",
	"02": "Form 990-N (e-Postcard) required",
	"03": "Group return",
	"04": "Form 990-BL required (black lung trust)",
	"06": "Not required to file (church)",
	"07": "Government 501(c)(1)",
	"13": "Not required to file (religious organization)",
	"14": "Not required to file (instrumentalities of states or political subdivisions)",
}

// IRS EO BMF STATUS — the exempt status the IRS records.
var exemptStatusCodes = map[string]string{
	"01": "Unconditional exemption",
	"02": "Conditional exemption",
	"12": "Trust described in section 4947(a)(2)",
	"25": "Exemption automatically revoked for failure to file",
}

// IRS Automatic Revocation of Exemption reason codes.
var revocationCodes = map[string]string{
	"01": "Automatic revocation for failure to file for three consecutive years",
}

// Publication 78 deductibility indicator.
var pub78IndicatorCodes = map[string]string{
	"0": "Listed in Publication 78",
	"1": "Listed under a group ruling",
}

// DescribeFilingRequirement describes an IRS filing requirement code.
func DescribeFilingRequirement(code *string) any {
	return describe(filingRequirementCodes, code, "filing requirement")
}

// DescribeExemptStatus describes an IRS exempt status code.
func DescribeExemptStatus(code *string) any {
	return describe(exemptStatusCodes, code, "exempt status")
}

// DescribeRevocationCode describes an IRS automatic revocation code.
func DescribeRevocationCode(code *string) any {
	return describe(revocationCodes, code, "revocation")
}

// DescribePub78Indicator describes a Publication 78 deductibility indicator.
func DescribePub78Indicator(code *string) any {
	return describe(pub78IndicatorCodes, code, "Publication 78 indicator")
}

// describe returns nil for a code the API did not send, the description for one
// the table knows, and a sentence that keeps the code visible for one it does
// not.
func describe(table map[string]string, code *string, kind string) any {
	if code == nil {
		return nil
	}

	if description, ok := table[strings.TrimSpace(*code)]; ok {
		return description
	}

	return kind + " code \"" + *code + "\", meaning unknown to this application"
}
