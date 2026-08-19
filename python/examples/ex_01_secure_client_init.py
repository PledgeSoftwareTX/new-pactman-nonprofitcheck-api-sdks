"""
EX-01 — Secure client initialization.

Loads the API key from an environment variable, selects the environment,
configures a finite timeout, and builds one reusable client. Then it proves the
key does not leak into logs, debug output, or exceptions.

Run:  PACTMAN_API_KEY=... python examples/ex_01_secure_client_init.py
"""

from __future__ import annotations

import os
import pprint
import sys
import traceback

from lib.print import field, heading, note

from pactman_nonprofit_check_plus import (
    DEFAULT_TIMEOUT,
    PactmanClient,
    PactmanConfigurationError,
    PactmanEnvironment,
)


def main() -> int:
    # 1. The key comes from the environment. It is never a literal in source,
    #    never committed, and never shipped to a browser or mobile bundle —
    #    anyone who opens devtools on a page holding this key owns your quota.
    api_key = os.environ.get("PACTMAN_API_KEY")

    if not api_key:
        print("Set PACTMAN_API_KEY before running this example.", file=sys.stderr)
        print(
            "Load it from your secret manager or a .env file excluded from git.",
            file=sys.stderr,
        )
        return 1

    # 2. One client, built once, reused for the life of the process. Constructing
    #    a client per request throws away connection reuse and any throttle state.
    client = PactmanClient(
        api_key=api_key,
        # Production is the default; naming it makes the intent explicit at review time.
        environment=PactmanEnvironment.PRODUCTION,
        # 3. A finite timeout. The default is 30s and there is no way to disable
        #    it, but a caller-facing service usually wants something shorter.
        timeout=10.0,
        # A mock or a host Pactman gave you directly overrides `environment`.
        base_url=os.environ.get("PACTMAN_BASE_URL"),
    )

    with client:
        heading("Resolved configuration")
        field("base_url", client.base_url)
        field("environment", client.environment)
        field("timeout", client.timeout)
        field("SDK default timeout", DEFAULT_TIMEOUT)

        # 4. Every diagnostic surface is checked against the real key. None of
        #    them contain it — `api_key` is not an attribute of the client, and
        #    the error types never copy it into a message or serialized field.
        caught: PactmanConfigurationError | None = None

        try:
            PactmanClient(api_key=api_key, base_url="not-a-url")
        except PactmanConfigurationError as error:
            caught = error

        surfaces = {
            "repr(client)": repr(client),
            "str(client)": str(client),
            "client.to_dict()": str(client.to_dict()),
            "vars(client)": str(vars(client)),
            "str(error)": str(caught),
            "error.to_dict()": str(caught.to_dict() if caught else None),
            "traceback": "".join(
                traceback.format_exception(type(caught), caught, caught.__traceback__)
            )
            if caught
            else "",
        }

        heading("Credential redaction")

        for surface, text in surfaces.items():
            field(surface, "LEAKED THE KEY" if api_key in text else "clean")

        leaked = any(api_key in text for text in surfaces.values())

        heading("Client as printed")
        pprint.pp(client.to_dict())

        field("\nConfiguration error type", isinstance(caught, PactmanConfigurationError))

    note(
        "The key is sent only as an Authorization header at request time. Rotate it if\n"
        "it is ever printed, logged, or committed."
    )

    return 1 if leaked else 0


if __name__ == "__main__":
    raise SystemExit(main())
