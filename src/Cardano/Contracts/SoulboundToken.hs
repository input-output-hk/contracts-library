{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Cardano.Contracts.SoulboundToken
    ( -- * Types
      SoulboundTokenParams (..)
    , SoulboundTokenState (..)
    , SoulboundTokenAction (..)
    , TokenId
    , Holder
      -- * Validators
    , mintingPolicy
    , validator
      -- * Off-chain
    , mintSoulbound
    , revokeSoulbound
    , getSoulboundInfo
    ) where

import           Cardano.Api.Shelley (PlutusScript, PlutusScriptV2)
import           Codec.Serialise (serialise)
import           Data.Aeson (FromJSON, ToJSON)
import           Data.ByteString.Lazy (toStrict)
import           Data.Text (Text)
import qualified Data.Text as T
import           GHC.Generics (Generic)
import           Ledger (Address, CurrencySymbol, TokenName, TxOutRef, Value)
import qualified Ledger.Ada as Ada
import           Ledger.Constraints (TxConstraints)
import qualified Ledger.Constraints as Constraints
import           Ledger.Typed.Scripts (ValidatorTypes, mkTypedValidator)
import qualified Ledger.Typed.Scripts as Scripts
import           Plutus.Contract (Contract, Promise, awaitTxConfirmed, submitTxConstraintsWith)
import qualified Plutus.Contract as Contract
import           Plutus.V2.Ledger.Api (BuiltinData, POSIXTime, PubKeyHash, ScriptContext, TxInfo)
import qualified Plutus.V2.Ledger.Api as V2
import           PlutusTx (CompiledCode, compile)
import qualified PlutusTx
import           PlutusTx.Prelude hiding (check)
import           Prelude (Show (..), String)
import qualified Prelude as P

-- | Unique identifier for a soulbound token
type TokenId = TokenName

-- | Holder of a soulbound token
type Holder = PubKeyHash

-- | Parameters for the soulbound token contract
data SoulboundTokenParams = SoulboundTokenParams
    { stpIssuer      :: !PubKeyHash  -- ^ The issuer who can mint/revoke
    , stpTokenName   :: !TokenName   -- ^ The token name
    , stpExpiration  :: !(Maybe POSIXTime)  -- ^ Optional expiration time
    } deriving (P.Show, Generic, FromJSON, ToJSON, PlutusTx.ToData, PlutusTx.FromData, PlutusTx.UnsafeFromData)

PlutusTx.makeLift ''SoulboundTokenParams

-- | State of a soulbound token
data SoulboundTokenState = SoulboundTokenState
    { stsHolder     :: !Holder     -- ^ Current holder
    , stsIssuedAt   :: !POSIXTime  -- ^ When it was issued
    , stsRevoked    :: !Bool       -- ^ Whether it's revoked
    } deriving (P.Show, Generic, FromJSON, ToJSON, PlutusTx.ToData, PlutusTx.FromData, PlutusTx.UnsafeFromData)

PlutusTx.makeLift ''SoulboundTokenState

-- | Actions that can be performed on a soulbound token
data SoulboundTokenAction
    = Mint !Holder       -- ^ Mint token to a holder
    | Revoke             -- ^ Revoke the token
    | Check              -- ^ Check token validity
    deriving (P.Show, Generic, FromJSON, ToJSON, PlutusTx.ToData, PlutusTx.FromData, PlutusTx.UnsafeFromData)

PlutusTx.makeLift ''SoulboundTokenAction

-- | Minting policy that enforces non-transferability
mintingPolicy :: SoulboundTokenParams -> Scripts.MintingPolicy
mintingPolicy params = mkMintingPolicyScript $
    $$(PlutusTx.compile [|| \p -> wrapMintingPolicy (mintingPolicyScript p) ||])
    `PlutusTx.applyCode`
    PlutusTx.liftCode params

mintingPolicyScript :: SoulboundTokenParams -> V2.MintingPolicyRedeemer -> V2.ScriptContext -> Bool
mintingPolicyScript params _ ctx =
    let info = V2.scriptContextTxInfo ctx
        ownSymbol = V2.ownCurrencySymbol ctx
        
        -- Check if this is a mint or burn
        minted = V2.txInfoMint info
        tokenValue = V2.singleton ownSymbol (stpTokenName params) 1
        
        -- Get the issuer's signature
        signedByIssuer = V2.txSignedBy info (stpIssuer params)
        
        -- Check minting conditions
        isMint = V2.valueOf minted (stpTokenName params) == 1
        isBurn = V2.valueOf minted (stpTokenName params) == -1
        
        -- For minting, ensure token goes to the intended holder
        validMint = case V2.txInfoOutputs info of
            [output] -> V2.txOutDatum output == V2.NoOutputDatum
                        && V2.txOutValue output `V2.geq` tokenValue
            _ -> False
            
    in if isMint
       then signedByIssuer && validMint
       else if isBurn
            then signedByIssuer  -- Only issuer can burn/revoke
            else False

-- | Validator for the soulbound token state
validator :: SoulboundTokenParams -> Scripts.TypedValidator SoulboundTokenState
validator params = Scripts.mkTypedValidator @SoulboundTokenState
    ($$(PlutusTx.compile [|| validateSoulbound ||])
        `PlutusTx.applyCode`
        PlutusTx.liftCode params)
    ($$(PlutusTx.compile [|| wrap ||]))
  where
    wrap = Scripts.wrapValidator @SoulboundTokenAction

validateSoulbound :: SoulboundTokenParams -> SoulboundTokenState -> SoulboundTokenAction -> ScriptContext -> Bool
validateSoulbound params state action ctx =
    let info = V2.scriptContextTxInfo ctx
        signedByIssuer = V2.txSignedBy info (stpIssuer params)
        signedByHolder = V2.txSignedBy info (stsHolder state)
    in case action of
        Mint holder ->
            -- Only issuer can mint
            signedByIssuer
            
        Revoke ->
            -- Only issuer can revoke
            signedByIssuer
            
        Check ->
