# Pactman Nonprofit Check Plus — SDKs

Official client libraries for the **Pactman Nonprofit Check Plus API**: look up US nonprofits by EIN and read the IRS and OFAC findings behind the result.

One directory per language, each published independently.

| Language | Package | Status | Docs |
|---|---|---|---|
| Node.js / TypeScript | `@pactmandev/nonprofit-check-plus` | Available | [nodejs/README.md](./nodejs/README.md) |

## API surface

All SDKs wrap the same two developer endpoints:

| | Endpoint |
|---|---|
| Single check | `GET /api/entities/nonprofitcheck/v1/us/ein/{ein}` |
| Bulk check | `POST /api/entities/nonprofitcheckbulk/v1/us/eins` (max 50 EINs) |

Authentication is `Authorization: Bearer <api key>` on every request.

## Getting an API key

Register at [pactman.org](https://pactman.org) and generate a key from your developer dashboard. Keys are private, server-side credentials — never ship one to a browser or commit one to source control.

## API documentation

<https://entities.pactman.org/api/entities/api-doc>

## License

MIT — see [LICENSE](./LICENSE).
