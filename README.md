# Pactman Nonprofit Check Plus — SDKs

Official client libraries for the **Pactman Nonprofit Check Plus API**: look up US nonprofits by EIN and read the IRS and OFAC findings behind the result.

One directory per language, each published independently.

| Language             | Package                            | Status    | Docs                                   |
| -------------------- | ---------------------------------- | --------- | -------------------------------------- |
| Node.js / TypeScript | `@pactmandev/nonprofit-check-plus` | Available | [nodejs/README.md](./nodejs/README.md) |
| Python               | `pactman-nonprofit-check-plus`     | Available | [python/README.md](./python/README.md) |
| .NET / C#            | `Pactman.NonprofitCheckPlus`       | Available | [dotnet/README.md](./dotnet/README.md) |
| Java                 | `org.pactman:pactman-nonprofit-check-plus` | Available | [java/README.md](./java/README.md)     |
| Go                   | `github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-api-sdks/go` | In development | [go/README.md](./go/README.md) |
| PHP                  | `pactmandev/nonprofit-check-plus`  | Available | [separate repository][php-sdk]         |

[php-sdk]: https://github.com/PledgeSoftwareTX/new-pactman-nonprofitcheck-php-sdk

The PHP SDK lives in its own repository. Packagist builds a release from the git
tag and reads `composer.json` from the repository root, so it cannot be published
from a subdirectory of this one.

## API surface

All SDKs wrap the same two developer endpoints:

|              | Endpoint                                                         |
| ------------ | ---------------------------------------------------------------- |
| Single check | `GET /api/entities/nonprofitcheck/v1/us/ein/{ein}`               |
| Bulk check   | `POST /api/entities/nonprofitcheckbulk/v1/us/eins` (max 50 EINs) |

Authentication is `Authorization: Bearer <api key>` on every request.

## Getting an API key

Register at [pactman.org](https://pactman.org) and generate a key from your developer dashboard. Keys are private, server-side credentials — never ship one to a browser or commit one to source control.

## API documentation

<https://pactman.org/nonprofitcheckplus-api/docs>

## License

MIT — see [LICENSE](./LICENSE).
