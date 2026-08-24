"""
The ``.env`` beside the package, and the organizations every live script reads.

Kept here rather than in one script so ``smoke_live.py`` and
``record_baseline.py`` read the same file the same way and talk about the same
subjects. The two have to agree on which deployment and which organizations they
are describing — a signature collapses every element of ``data[]`` onto one path,
so a recording made from one batch and a run made from another disagree wherever
the two sets of organizations differ. A second copy of this parser, or a second
list of EINs, is how they would stop agreeing.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

__all__ = [
    "API_KEY_ENV",
    "BULK_EINS",
    "BULK_PROBE_LIMIT",
    "EIN",
    "MISSING_EIN",
    "ROOT",
    "EnvFile",
    "load_env_file",
]

ROOT = Path(__file__).resolve().parents[1]

#: The variable the credential is read from, in the environment or in ``.env``.
API_KEY_ENV = "PACTMAN_API_KEY"

# The organizations this harness checks.
#
# A primary subject with a record, a second one to give the bulk order and
# duplicate probes something to work with, and a well-formed EIN with no record
# for the not-found and partial-success paths. They are the test data in the test
# plan, and the first two are reachable on a free-tier key, so a free key gets as
# far as a free key can.
#
# These are also the subjects ``src/pactman_nonprofit_check_plus/response_baseline.json``
# describes. Changing one means re-recording it.
EIN = "996589560"
BULK_EINS = ["996589560", "996202676"]
MISSING_EIN = "999999999"

#: How many of the bulk subjects a run actually sends.
#:
#: The bulk probes read the first few and the rest would cost quota unspent — but
#: the recorder has to send the same batch the smoke run does. Same number, same
#: subjects, or the comparison reports the batch size as drift.
BULK_PROBE_LIMIT = 3


@dataclass(frozen=True)
class EnvFile:
    """A loaded ``.env``, and which names it supplied."""

    path: Path
    names: set[str]


_ASSIGNMENT = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$")


def load_env_file() -> EnvFile | None:
    """
    Loads ``python/.env``, so the key and any standing overrides live in a file
    rather than in the shell for every run. The file is gitignored.

    A variable already in the environment wins: exporting one for a single run
    must not be silently overridden by a file someone set up months ago.
    """
    path = ROOT / ".env"

    if not path.exists():
        return None

    names: set[str] = set()

    for line in path.read_text(encoding="utf-8").splitlines():
        matched = _ASSIGNMENT.match(line)

        if not matched or matched.group(1) in os.environ:
            continue

        name, raw = matched.group(1), matched.group(2).strip()

        if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "'\"":
            raw = raw[1:-1]

        os.environ[name] = raw
        names.add(name)

    return EnvFile(path=path, names=names)
