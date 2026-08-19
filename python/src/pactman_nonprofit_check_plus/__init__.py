"""
Pactman Nonprofit Check Plus SDK for Python.

Server-side only — the API key is a private credential.

    import os
    from pactman_nonprofit_check_plus import PactmanClient

    with PactmanClient(api_key=os.environ["PACTMAN_API_KEY"]) as client:
        result = client.nonprofits.check("41-1787097")
        print(result.nonprofit["organization_name"])

An ``AsyncPactmanClient`` with the same surface is available for asyncio code.
"""

from .client import (
    AsyncNonprofitsResource,
    AsyncPactmanClient,
    NonprofitsResource,
    PactmanClient,
)
from .config import (
    DEFAULT_RETRY,
    DEFAULT_TIMEOUT,
    ResolvedConfig,
    RetryOptions,
)
from .ein import EIN_LENGTH, is_valid_ein, normalize_ein, normalize_eins
from .environments import (
    BULK_CHECK_PATH,
    DEFAULT_ENVIRONMENT,
    MAX_BULK_EINS,
    SINGLE_CHECK_PATH,
    PactmanEnvironment,
    base_url_for_environment,
    supported_environments,
)
from .errors import (
    PactmanApiError,
    PactmanApiErrorInit,
    PactmanAuthenticationError,
    PactmanAuthorizationError,
    PactmanBadRequestError,
    PactmanConfigurationError,
    PactmanError,
    PactmanErrorCategory,
    PactmanErrorOrigin,
    PactmanNetworkError,
    PactmanNotFoundError,
    PactmanRateLimitError,
    PactmanServerError,
    PactmanTimeoutError,
    PactmanValidationError,
    ValidationIssue,
    is_pactman_error,
)
from .sources import (
    AroeSource,
    BmfSource,
    OfacSource,
    Pub78Source,
    get_aroe,
    get_bmf,
    get_ofac,
    get_pub78,
)
from .types import (
    ApiEnvelope,
    ApiErrorDetail,
    BulkCheckResult,
    Nonprofit,
    OrganizationType,
    PactmanResult,
    SingleCheckResult,
)
from .version import VERSION

__version__ = VERSION

__all__ = [
    # Client
    "PactmanClient",
    "AsyncPactmanClient",
    "NonprofitsResource",
    "AsyncNonprofitsResource",
    # Configuration
    "DEFAULT_RETRY",
    "DEFAULT_TIMEOUT",
    "ResolvedConfig",
    "RetryOptions",
    # Environments
    "BULK_CHECK_PATH",
    "DEFAULT_ENVIRONMENT",
    "MAX_BULK_EINS",
    "SINGLE_CHECK_PATH",
    "PactmanEnvironment",
    "base_url_for_environment",
    "supported_environments",
    # EIN helpers
    "EIN_LENGTH",
    "is_valid_ein",
    "normalize_ein",
    "normalize_eins",
    # Errors
    "PactmanError",
    "PactmanApiError",
    "PactmanApiErrorInit",
    "PactmanAuthenticationError",
    "PactmanAuthorizationError",
    "PactmanBadRequestError",
    "PactmanConfigurationError",
    "PactmanErrorCategory",
    "PactmanErrorOrigin",
    "PactmanNetworkError",
    "PactmanNotFoundError",
    "PactmanRateLimitError",
    "PactmanServerError",
    "PactmanTimeoutError",
    "PactmanValidationError",
    "ValidationIssue",
    "is_pactman_error",
    # Source projections
    "AroeSource",
    "BmfSource",
    "OfacSource",
    "Pub78Source",
    "get_aroe",
    "get_bmf",
    "get_ofac",
    "get_pub78",
    # Response models
    "ApiEnvelope",
    "ApiErrorDetail",
    "BulkCheckResult",
    "Nonprofit",
    "OrganizationType",
    "PactmanResult",
    "SingleCheckResult",
    # Version
    "VERSION",
    "__version__",
]
