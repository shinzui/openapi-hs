# openapi-hs

[![Hackage](https://img.shields.io/hackage/v/openapi-hs.svg)](http://hackage.haskell.org/package/openapi-hs)

> **Fork notice.** `openapi-hs` is a fork of [`openapi3`](https://github.com/biocad/openapi3),
> which is no longer actively maintained and supports only OpenAPI 3.0. This fork updates the
> library to **OpenAPI 3.1 / JSON Schema 2020-12**. The Haskell module namespace remains
> `Data.OpenApi.*`, so downstream code only swaps the dependency name `openapi3` → `openapi-hs`.
> The fork preserves the original BSD-3-Clause license and copyright — see [License](#license).

OpenAPI 3.1 data model.

The OpenAPI 3.1 specification is available at https://spec.openapis.org/oas/v3.1.0.

This package is heavily based on excellent work on Swagger 2.0 at
https://github.com/GetShopTV/swagger2.

## Usage

This library is intended to be used for decoding and encoding OpenAPI 3.1 specifications as well as manipulating them.

Migrating an existing OpenAPI 3.0 document? See [`MIGRATION_3.0_TO_3.1.md`](/MIGRATION_3.0_TO_3.1.md) and the `Data.OpenApi.Migration` module.

Please refer to [haddock documentation](http://hackage.haskell.org/package/openapi-hs).

Some examples can be found in [`examples/` directory](/examples).

## Trying out

All generated swagger specifications can be interactively viewed on [Swagger Editor](http://editor.swagger.io/).

Ready-to-use specification can be served as JSON and interactive API documentation
can be displayed using [Swagger UI](https://github.com/swagger-api/swagger-ui).

Many Swagger tools, including server and client code generation for many languages, can be found on
[Swagger's Tools and Integrations page](http://swagger.io/open-source-integrations/).

## Contributing

We are happy to receive bug reports, fixes, documentation enhancements, and other improvements.

Please report bugs via the [github issue tracker](https://github.com/shinzui/openapi-hs/issues).

*GetShopTV Team*

*Biocad Team*

## License

`openapi-hs` retains the original BSD-3-Clause license of the upstream
[`openapi3`](https://github.com/biocad/openapi3) project, including the original copyright. See
the [`LICENSE`](/LICENSE) file for the full text. This fork's changes are released under the same
BSD-3-Clause terms.
