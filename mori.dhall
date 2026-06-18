let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/026ae74331e5c516542af1dd96f041c658ed4621/package.dhall
        sha256:18258ef583580a897f4af3e7c86db0342afb42fb40efc535b217ba1089230141

in  Schema.Project::{
    , project = Schema.ProjectIdentity::{
      , name = "openapi-hs"
      , namespace = "shinzui"
      , type = Schema.PackageType.Library
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , description = Some
          "OpenAPI 3.1 data model for Haskell (fork of openapi3); decode, encode, and manipulate OpenAPI specs under the Data.OpenApi.* namespace"
      , domains = [ "openapi", "web", "json-schema" ]
      , owners = [ "shinzui" ]
      }
    , repos =
      [ Schema.Repo::{ name = "openapi-hs", github = Some "shinzui/openapi-hs" }
      ]
    , packages =
      [ Schema.Package::{
        , name = "openapi-hs"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "./"
        , description = Some "OpenAPI 3.1 data model, decoding and encoding"
        }
      ]
    , docs =
      [ Schema.DocRef::{
        , key = "migration-3.0-to-3.1"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Migrating OpenAPI 3.0 specs to 3.1"
        , location = Schema.DocLocation.LocalFile "MIGRATION_3.0_TO_3.1.md"
        }
      ]
    }
