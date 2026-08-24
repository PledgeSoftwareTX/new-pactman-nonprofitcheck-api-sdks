#!/usr/bin/env python3
"""
Records the shape of the production API into ``response_baseline.json``.

``response_contract.json`` says what this package *promises* a response looks
like. This file says what production *actually returned*, once, on a day someone
looked. They answer different questions and both are needed: the contract catches
the API drifting away from the declared types, the baseline catches the API
drifting at all — including in the fields the contract leaves as a bare
``string``, where a promise is too loose to notice anything.

The recording is committed, so it is the same for everyone and a change to it
shows up in review as what it is: production moved, and someone accepted it. That
is also why writing it is a deliberate command rather than something a smoke run
does on the side. A baseline that rewrites itself on every run agrees with the
API by construction and can never fail.

Usage
    python scripts/record_baseline.py [--allow-any-target] [--dry-run]

The key and the target come from the environment or ``.env``, and the subjects
from ``env.py``, exactly as ``smoke_live.py`` reads them. Recording spends
billable checks: one single lookup and one bulk lookup against the key you point
it at.
"""

from __future__ import annotations

import json
import os
import sys
from collections.abc import Callable
from datetime import datetime, timezone
from functools import partial
from typing import Any

from contract import signature_of
from env import API_KEY_ENV, BULK_EINS, BULK_PROBE_LIMIT, EIN, MISSING_EIN, ROOT, load_env_file

from pactman_nonprofit_check_plus import (
    DEFAULT_ENVIRONMENT,
    VERSION,
    PactmanClient,
    RetryOptions,
    base_url_for_environment,
    normalize_ein,
    normalize_eins,
)

BASELINE_PATH = ROOT / "src" / "pactman_nonprofit_check_plus" / "response_baseline.json"

NOTE = (
    "The shape production returned when this was recorded: path, JSON type and value format, "
    "never a value. Committed, so every run of scripts/smoke_live.py is held against the same "
    "recording — any path added or removed, and any token that changed, fails there. Rewrite "
    "it with `python scripts/record_baseline.py` only when production has moved and the move "
    "is intended."
)


def normalize_url(value: str) -> str:
    return value.rstrip("/").lower()


def main() -> int:
    load_env_file()

    arguments = sys.argv[1:]
    allow_any_target = "--allow-any-target" in arguments
    dry_run = "--dry-run" in arguments

    api_key = os.environ.get(API_KEY_ENV)

    if not api_key:
        print(
            f"No API key. Put {API_KEY_ENV} in python/.env, or export it, and run this again.",
            file=sys.stderr,
        )

        return 2

    def redact(value: object) -> str:
        """Replaces the credential wherever it surfaces. Applied to everything printed."""
        text = value if isinstance(value, str) else str(value)

        return text.replace(api_key, "[redacted]")

    def say(text: str = "") -> None:
        print(redact(text))

    production_url = base_url_for_environment(DEFAULT_ENVIRONMENT)
    base_url = os.environ.get("PACTMAN_BASE_URL") or production_url

    # The baseline every run is held against has to come from the deployment those
    # runs are about. A recording made against a sandbox would quietly turn the
    # sandbox into the standard, and nothing downstream could tell.
    if normalize_url(base_url) != normalize_url(production_url) and not allow_any_target:
        print(
            f"Refusing to record from {base_url}.\n"
            f"The committed baseline describes production ({production_url}); recording it "
            "from anywhere else makes that deployment the standard for everyone.\n"
            "Unset PACTMAN_BASE_URL, or pass --allow-any-target if you mean it.",
            file=sys.stderr,
        )

        return 2

    try:
        ein = normalize_ein(EIN)
        missing_ein = normalize_ein(MISSING_EIN)
        # The same batch ``smoke_live.py`` sends, so the two signatures describe
        # the same set of organizations rather than differing by batch size.
        bulk_eins = normalize_eins(BULK_EINS[:BULK_PROBE_LIMIT])
    except ValueError as error:
        print(str(error), file=sys.stderr)

        return 2

    client = PactmanClient(
        api_key=api_key,
        base_url=base_url,
        timeout=20.0,
        retry=RetryOptions(max_retries=2),
    )

    # The batches to try, in the order ``smoke_live.py`` would arrive at them.
    #
    # That run keeps the first bulk response any of its probes returns, and the
    # probes go in a fixed order: the partial-success batch first, because its
    # envelope is the only one carrying the item-level ``errors`` a batch with a
    # miss comes back with, then the duplicate probe, which is what a key whose
    # bulk EINs are allowlisted falls back to — such a key refuses the whole batch
    # the moment an EIN with no record is in it.
    #
    # Recording a batch the run will never send would disagree with every run on
    # batch composition alone, and report the difference as the API moving.
    bulk_attempts: list[list[str]] = []

    if bulk_eins:
        bulk_attempts.append([*bulk_eins, missing_ein])

    if len(bulk_eins) >= 2:
        bulk_attempts.append([bulk_eins[1], bulk_eins[0], bulk_eins[1]])

    say(f"Target        {base_url}")
    say(f"Subjects      {ein} · bulk {', '.join(bulk_eins) if bulk_eins else 'none'}")
    say(f"Cost          up to {1 + len(bulk_attempts)} billable request(s)")
    say()

    def record(label: str, call: Callable[[], Any]) -> dict[str, str] | None:
        """Runs one lookup and reduces it to a signature, or reports why it could not."""
        try:
            result = call()
        # Any failure is a reason not to record, and the message is the whole point.
        except Exception as error:
            say(f"  {label:<8} failed — {redact(error)}")

            return None

        if result.raw is None:
            say(f"  {label:<8} no response body to record")

            return None

        signature = signature_of(result.raw)

        say(f"  {label:<8} {len(signature)} paths")

        return signature

    try:
        single = record("single", lambda: client.nonprofits.check(ein))

        bulk: dict[str, str] | None = None

        for attempt in bulk_attempts:
            # partial rather than a lambda: the batch is bound now, not read from
            # the loop variable when the call is finally made.
            bulk = record("bulk", partial(client.nonprofits.check_bulk, attempt))

            if bulk:
                break
    finally:
        client.close()

    if not single and not bulk:
        print("\nNothing was recorded. The baseline on disk is unchanged.", file=sys.stderr)

        return 1

    # A half that could not be recorded keeps whatever is already on disk.
    #
    # A key whose allowlist refuses the batch, or a lookup that timed out, is a
    # reason to record nothing new — not a reason to throw away a good recording
    # made on a day the call worked. Overwriting it with null would delete the
    # standard the bulk checks are held against, and the run that noticed would be
    # the one that stopped failing.
    existing: dict[str, Any] = (
        json.loads(BASELINE_PATH.read_text(encoding="utf-8")) if BASELINE_PATH.exists() else {}
    )

    kept: list[str] = []

    def half(kind: str, recorded: dict[str, str] | None) -> Any:
        if recorded:
            return {"signature": recorded}

        stored = existing.get(kind)

        if isinstance(stored, dict) and stored.get("signature"):
            kept.append(kind)

        return stored

    baseline = {
        "note": NOTE,
        "recorded_at": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
        "base_url": base_url,
        "sdk_version": VERSION,
        "single": half("single", single),
        "bulk": half("bulk", bulk),
    }

    if dry_run:
        say("\n--dry-run: nothing written.")

        return 0

    BASELINE_PATH.write_text(
        json.dumps(baseline, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    say(f"\nWrote {BASELINE_PATH.name} — recorded from {base_url} on SDK {VERSION}.")

    if kept:
        say(f"The {' and '.join(kept)} half was left as it was — this run could not record it.")

    say("Commit it. Every smoke run from now on is held against it.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
