from __future__ import annotations

from pathlib import Path
from typing import Any, cast

import sys

import pytest

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib  # type: ignore[no-redef]

from conftest import TEST_API_KEY, Stub, TransportMock, client_with, envelope
from pactman_nonprofit_check_plus import (
    DEFAULT_TIMEOUT,
    PactmanClient,
    PactmanConfigurationError,
    PactmanEnvironment,
    PactmanErrorCategory,
    RetryOptions,
    base_url_for_environment,
    supported_environments,
)
from pactman_nonprofit_check_plus.config import build_user_agent
from pactman_nonprofit_check_plus.version import PACKAGE_NAME, VERSION

PYPROJECT = Path(__file__).resolve().parents[1] / "pyproject.toml"


class TestClientConstruction:
    def test_creates_a_client_from_the_minimum_documented_configuration(self) -> None:
        with PactmanClient(api_key=TEST_API_KEY) as client:
            assert client.base_url == "https://entities.pactman.org"
            assert client.environment is PactmanEnvironment.PRODUCTION
            assert client.timeout == DEFAULT_TIMEOUT

    @pytest.mark.parametrize("api_key", [None, "", "   ", 12345])
    def test_reports_a_configuration_category_on_a_bad_api_key(self, api_key: object) -> None:
        with pytest.raises(PactmanConfigurationError) as excinfo:
            PactmanClient(api_key=api_key)  # type: ignore[arg-type]

        assert excinfo.value.category is PactmanErrorCategory.CONFIGURATION

    def test_sends_no_request_when_the_api_key_is_empty(self) -> None:
        mock = TransportMock([Stub(body=envelope(None))])

        with pytest.raises(PactmanConfigurationError):
            PactmanClient(api_key="", base_url="http://mock.test", http_client=mock.client())

        assert mock.requests == []


class TestEnvironmentAndBaseUrlSelection:
    def test_resolves_a_url_for_every_named_environment(self) -> None:
        for environment in supported_environments():
            assert base_url_for_environment(environment).startswith("https://")

    def test_exposes_production_only(self) -> None:
        # Internal QA, SIT and sandbox hosts are deliberately not selectable.
        assert supported_environments() == [PactmanEnvironment.PRODUCTION]

    def test_accepts_a_custom_base_url_for_a_local_mock_server(self) -> None:
        with PactmanClient(api_key=TEST_API_KEY, base_url="http://127.0.0.1:8787") as client:
            assert client.base_url == "http://127.0.0.1:8787"
            assert client.environment is None

    def test_strips_a_trailing_slash_from_a_custom_base_url(self) -> None:
        with PactmanClient(api_key=TEST_API_KEY, base_url="https://proxy.example.com/v1//") as client:
            assert client.base_url == "https://proxy.example.com/v1"

    def test_rejects_an_unknown_environment_name(self) -> None:
        with pytest.raises(PactmanConfigurationError, match="Unknown environment"):
            PactmanClient(api_key=TEST_API_KEY, environment="sandbox")

    @pytest.mark.parametrize("base_url", ["", "   ", "not a url", "ftp://entities.pactman.org", 42])
    def test_rejects_a_malformed_base_url(self, base_url: object) -> None:
        with pytest.raises(PactmanConfigurationError):
            PactmanClient(api_key=TEST_API_KEY, base_url=base_url)  # type: ignore[arg-type]


class TestOptionValidation:
    @pytest.mark.parametrize("timeout", [0, -1, float("inf"), float("nan"), "30"])
    def test_rejects_a_nonsensical_timeout(self, timeout: object) -> None:
        with pytest.raises(PactmanConfigurationError):
            PactmanClient(api_key=TEST_API_KEY, timeout=timeout)  # type: ignore[arg-type]

    def test_honours_an_explicit_timeout_override(self) -> None:
        with PactmanClient(api_key=TEST_API_KEY, timeout=1.5) as client:
            assert client.timeout == 1.5

    @pytest.mark.parametrize(
        "retry",
        [{"max_retries": -1}, {"initial_delay": -1}, {"backoff_factor": 0.5}, {"max_delay": -1}],
    )
    def test_rejects_a_nonsensical_retry_policy(self, retry: dict[str, float]) -> None:
        with pytest.raises(PactmanConfigurationError):
            PactmanClient(api_key=TEST_API_KEY, retry=retry)

    def test_rejects_an_unknown_retry_option(self) -> None:
        with pytest.raises(PactmanConfigurationError, match="Unknown retry option"):
            PactmanClient(api_key=TEST_API_KEY, retry={"maxRetries": 3})

    @pytest.mark.parametrize("limit", [0, -1, "5"])
    def test_rejects_a_nonsensical_request_rate(self, limit: object) -> None:
        with pytest.raises(PactmanConfigurationError):
            PactmanClient(api_key=TEST_API_KEY, max_requests_per_second=limit)  # type: ignore[arg-type]

    def test_retry_false_disables_retrying(self) -> None:
        with PactmanClient(api_key=TEST_API_KEY, retry=False) as client:
            assert client.to_dict()["retry"]["max_retries"] == 0

    def test_a_caller_list_cannot_mutate_a_live_policy(self) -> None:
        statuses = [429, 503]
        policy = RetryOptions(retryable_statuses=statuses)  # type: ignore[arg-type]
        statuses.append(404)

        assert policy.retryable_statuses == (429, 503)


class TestCredentialRedaction:
    def test_keeps_the_key_out_of_the_serializable_view(self) -> None:
        with PactmanClient(api_key=TEST_API_KEY) as client:
            assert TEST_API_KEY not in str(client.to_dict())
            assert client.to_dict()["api_key"] == "[redacted]"

    def test_keeps_the_key_out_of_repr_and_str(self) -> None:
        with PactmanClient(api_key=TEST_API_KEY) as client:
            assert TEST_API_KEY not in repr(client)
            assert TEST_API_KEY not in str(client)

    def test_does_not_expose_the_key_as_a_client_attribute(self) -> None:
        with PactmanClient(api_key=TEST_API_KEY) as client:
            assert TEST_API_KEY not in str(vars(client))

    def test_sends_the_key_but_never_stores_it_on_a_result(self) -> None:
        mock = TransportMock([Stub(body=envelope(None))])
        result = client_with(mock).nonprofits.check("411787097")

        assert mock.requests[0].headers["authorization"] == f"Bearer {TEST_API_KEY}"
        assert TEST_API_KEY not in str(result)


class TestDefaultHeaders:
    def test_sends_caller_supplied_default_headers(self) -> None:
        mock = TransportMock([Stub(body=envelope(None))])
        client_with(mock, default_headers={"X-Trace": "abc"}).nonprofits.check("411787097")

        assert mock.requests[0].headers["x-trace"] == "abc"

    def test_default_headers_cannot_displace_the_credential(self) -> None:
        mock = TransportMock([Stub(body=envelope(None))])
        client = client_with(mock, default_headers={"Authorization": "Bearer attacker"})
        client.nonprofits.check("411787097")

        assert mock.requests[0].headers["authorization"] == f"Bearer {TEST_API_KEY}"

    def test_per_request_headers_cannot_displace_the_credential(self) -> None:
        mock = TransportMock([Stub(body=envelope(None))])
        client_with(mock).nonprofits.check(
            "411787097", headers={"Authorization": "Bearer attacker"}
        )

        assert mock.requests[0].headers["authorization"] == f"Bearer {TEST_API_KEY}"


class TestUserAgent:
    def test_identifies_the_sdk_language_and_version(self) -> None:
        user_agent = build_user_agent()

        assert user_agent.startswith(f"{PACKAGE_NAME}/{VERSION}")
        assert "python/" in user_agent

    def test_matches_the_distribution_name_declared_in_pyproject(self) -> None:
        assert _pyproject()["project"]["name"] == PACKAGE_NAME

    def test_matches_the_version_declared_in_pyproject(self) -> None:
        assert _pyproject()["project"]["version"] == VERSION


def _pyproject() -> dict[str, Any]:
    with PYPROJECT.open("rb") as handle:
        return cast(dict[str, Any], tomllib.load(handle))
