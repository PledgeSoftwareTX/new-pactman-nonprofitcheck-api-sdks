package pactman

import (
	"errors"
	"slices"
	"strings"
	"testing"
)

func TestNormalizeEIN(t *testing.T) {
	t.Run("normalizes hyphenated and bare EINs to the same value", func(t *testing.T) {
		for _, input := range []string{"41-1787097", "411787097"} {
			got, err := NormalizeEIN(input)
			if err != nil || got != "411787097" {
				t.Fatalf("NormalizeEIN(%q) = %q, %v", input, got, err)
			}
		}
	})

	t.Run("ignores surrounding whitespace", func(t *testing.T) {
		got, err := NormalizeEIN("  41-1787097  ")
		if err != nil || got != "411787097" {
			t.Fatalf("NormalizeEIN = %q, %v", got, err)
		}
	})

	rejected := map[string]string{
		"eight digits":                "41178709",
		"ten digits":                  "4117870971",
		"letters":                     "41-178709A",
		"all letters":                 "abcdefghi",
		"unsupported punctuation":     "41.1787097",
		"a hyphen in the wrong place": "4117-87097",
		"spaces inside":               "41 1787097",
		"two hyphens":                 "41--1787097",
		"non-ASCII digits":            "٤١١٧٨٧٠٩٧",
		"empty":                       "",
		"whitespace only":             "   ",
	}

	for label, input := range rejected {
		t.Run("rejects "+label, func(t *testing.T) {
			_, err := NormalizeEIN(input)

			var verr *ValidationError
			if !errors.As(err, &verr) {
				t.Fatalf("NormalizeEIN(%q) error = %v, want *ValidationError", input, err)
			}

			if IsValidEIN(input) {
				t.Fatalf("IsValidEIN(%q) = true", input)
			}
		})
	}

	t.Run("names the offending value and reports it as local", func(t *testing.T) {
		_, err := NormalizeEIN("41178709")

		var verr *ValidationError
		if !errors.As(err, &verr) {
			t.Fatalf("error = %v", err)
		}

		if !strings.Contains(verr.Error(), "41178709") {
			t.Errorf("message %q does not name the value", verr.Error())
		}

		if verr.Origin() != OriginLocal || verr.Category() != CategoryValidation {
			t.Errorf("origin/category = %s/%s", verr.Origin(), verr.Category())
		}

		if len(verr.Issues) != 1 || verr.Issues[0].Value != "41178709" || verr.Issues[0].Index != -1 {
			t.Errorf("issues = %+v", verr.Issues)
		}

		if !errors.Is(err, ErrValidation) {
			t.Error("errors.Is(err, ErrValidation) = false")
		}
	})
}

func TestNormalizeEINs(t *testing.T) {
	t.Run("preserves order and duplicates", func(t *testing.T) {
		got, err := NormalizeEINs([]string{"41-1787097", "996589560", "411787097"})
		want := []string{"411787097", "996589560", "411787097"}

		if err != nil || !slices.Equal(got, want) {
			t.Fatalf("NormalizeEINs = %v, %v; want %v", got, err, want)
		}
	})

	t.Run("identifies every failing item, by index and value", func(t *testing.T) {
		_, err := NormalizeEINs([]string{"411787097", "nope", "996589560", "1234"})

		var verr *ValidationError
		if !errors.As(err, &verr) {
			t.Fatalf("error = %v", err)
		}

		if len(verr.Issues) != 2 || verr.Issues[0].Index != 1 || verr.Issues[1].Index != 3 {
			t.Fatalf("issues = %+v", verr.Issues)
		}

		if verr.Issues[0].Value != "nope" {
			t.Errorf("first issue value = %q", verr.Issues[0].Value)
		}

		if !strings.Contains(verr.Error(), "index 1, 3") {
			t.Errorf("message %q does not list the positions", verr.Error())
		}
	})

	t.Run("does not modify the caller's slice", func(t *testing.T) {
		supplied := []string{"41-1787097"}

		if _, err := NormalizeEINs(supplied); err != nil {
			t.Fatal(err)
		}

		if supplied[0] != "41-1787097" {
			t.Errorf("caller's slice was modified: %v", supplied)
		}
	})
}
