{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Emit a representative API's OpenAPI 3.1 document as JSON to stdout.
--
-- Besides serving as a runnable example, this feeds Layer-3 (external,
-- authoritative) validation:
--
-- > cabal run example > openapi.json
-- > nix run nixpkgs#vacuum-go -- lint -d openapi.json
--
-- The document is deliberately a complete OpenAPI 3.1 contract — it carries
-- @info@ (title/version/description), a @server@, top-level @tags@, and a
-- unique @operationId@ per operation — so an external linter has a realistic
-- document to validate rather than a bare skeleton.
module Main where

import Control.Lens
import Data.Aeson
import Data.ByteString.Lazy.Char8 qualified as BL
import Data.OpenApi
import Data.OpenApi.Declare
import Data.OpenApi.Lens
import Data.OpenApi.Operation
import Data.Proxy
import Data.Text (Text)
import GHC.Generics

type Username = Text

data UserSummary = UserSummary
  { summaryUsername :: Username,
    summaryUserid :: Int
  }
  deriving stock (Generic)

instance ToSchema UserSummary where
  declareNamedSchema _ = do
    usernameSchema <- declareSchemaRef (Proxy :: Proxy Username)
    useridSchema <- declareSchemaRef (Proxy :: Proxy Int)
    return $
      NamedSchema (Just "UserSummary") $
        mempty
          & type_ ?~ OpenApiTypeSingle OpenApiObject
          & properties
            .~ [ ("summaryUsername", usernameSchema),
                 ("summaryUserid", useridSchema)
               ]
          & required
            .~ [ "summaryUsername",
                 "summaryUserid"
               ]

type Group = Text

data UserDetailed = UserDetailed
  { username :: Username,
    userid :: Int,
    groups :: [Group]
  }
  deriving stock (Generic)
  deriving anyclass (ToSchema)

newtype Package = Package {packageName :: Text}
  deriving stock (Generic)
  deriving anyclass (ToSchema)

hackageOpenApi :: OpenApi
hackageOpenApi = spec & components . schemas .~ defs
  where
    (defs, spec) = runDeclare declareHackageOpenApi mempty

declareHackageOpenApi :: Declare (Definitions Schema) OpenApi
declareHackageOpenApi = do
  -- param schemas
  let usernameParamSchema = toParamSchema (Proxy :: Proxy Username)

  -- responses
  userSummaryResponse <- declareResponse "application/json" (Proxy :: Proxy UserSummary)
  userDetailedResponse <- declareResponse "application/json" (Proxy :: Proxy UserDetailed)
  packagesResponse <- declareResponse "application/json" (Proxy :: Proxy [Package])

  return $
    mempty
      & info . title .~ "Hackage API"
      & info . version .~ "1.0.0"
      & info . description ?~ "A small, representative Hackage-style read API."
      & servers .~ ["https://hackage.haskell.org"]
      & tags
        .~ [ Tag "users" (Just "User lookup operations") Nothing,
             Tag "packages" (Just "Package operations") Nothing
           ]
      & paths
        .~ [ ( "/users",
               mempty
                 & get
                   ?~ ( mempty
                          & operationId ?~ "getUsers"
                          & tags .~ ["users"]
                          & at 200 ?~ Inline userSummaryResponse
                      )
             ),
             ( "/user/{username}",
               mempty
                 & get
                   ?~ ( mempty
                          & operationId ?~ "getUser"
                          & tags .~ ["users"]
                          & parameters
                            .~ [ Inline $
                                   mempty
                                     & name .~ "username"
                                     & required ?~ True
                                     & in_ .~ ParamPath
                                     & schema ?~ Inline usernameParamSchema
                               ]
                          & at 200 ?~ Inline userDetailedResponse
                      )
             ),
             ( "/packages",
               mempty
                 & get
                   ?~ ( mempty
                          & operationId ?~ "getPackages"
                          & tags .~ ["packages"]
                          & at 200 ?~ Inline packagesResponse
                      )
             )
           ]

main :: IO ()
main = BL.putStrLn (encode hackageOpenApi)
