{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.Contracts.SoulboundTokenSpec (tests) where

import           Cardano.Contracts.SoulboundToken
import           Cardano.Api.Shelley (PlutusScriptV2)
import           Control.Monad (void)
import           Data.Default (def)
import           Ledger (Address, PubKeyHash, TxOutRef, Value)
import qualified Ledger.Ada as Ada
import           Ledger.Constraints (TxConstraints)
import qualified Ledger.Constraints as Constraints
import           Ledger.Typed.Scripts (ValidatorTypes)
import qualified Ledger.Typed.Scripts as Scripts
import           Plutus.Contract.Test (Wallet, w1, w2, w3)
import qualified Plutus.Contract.Test as Test
import           Plutus.Trace.Emulator (EmulatorTrace, activateContractWallet, waitNSlots)
import qualified Plutus.Trace.Emulator as Trace
import           Plutus.V2.Ledger.Api (POSIXTime, TokenName)
import qualified PlutusTx.Prelude as P
import           Test.Tasty (TestTree, testGroup)
import           Test.Tasty.HUnit (testCase, (@?=))
import           Wallet.Emulator (Wallet)
import qualified Wallet.Emulator as Wallet

-- | Test wallet helpers
walletPubKey :: Wallet -> PubKeyHash
walletPubKey = Wallet.mockWalletPaymentPubKeyHash

-- | Test parameters
testTokenName :: TokenName
testTokenName = "SoulboundBadge"

testParams :: SoulboundTokenParams
testParams = SoulboundTokenParams
    { stpIssuer = walletPubKey w1
    , stpTokenName = testTokenName
    , stpExpiration = Nothing
    }

-- | Test suite
tests :: TestTree
tests = testGroup "Soulbound Token Tests"
    [ testMinting
    , testNonTransferability
    , testRevocation
    , testExpiration
    , testUnauthorizedMint
    ]

-- | Test basic minting of soulbound token
testMinting :: TestTree
testMinting = testCase "Mint soulbound token to holder" $
    Test.runEmulatorTraceIO' def emTrace
  where
    emTrace :: EmulatorTrace ()
    emTrace = do
        -- Activate contract for issuer (w1)
        issuerContract <- activateContractWallet w1 (soulboundContract testParams)
        
        -- Mint token to w2
        void $ Trace.callEndpoint @"mint" issuerContract (walletPubKey w2)
        
        -- Wait for confirmation
        void $ waitNSlots 2
        
        -- Check token exists
        result <- Trace.callEndpoint @"check" issuerContract ()
        
        -- Assert token was minted successfully
        Test.assertContract issuerContract $ do
            Test.assertTrue "Token should be minted" result

-- | Test that tokens cannot be transferred
testNonTransferability :: TestTree
testNonTransferability = testCase "Soulbound tokens cannot be transferred" $
    Test.runEmulatorTraceIO' def emTrace
  where
    emTrace :: EmulatorTrace ()
    emTrace = do
        -- Activate contract for issuer (w1)
        issuerContract <- activateContractWallet w1 (soulboundContract testParams)
        
        -- Mint token to w2
        void $ Trace.callEndpoint @"mint" issuerContract (walletPubKey w2)
        void $ waitNSlots 2
        
        -- Try to transfer from w2 to w3 (should fail)
        holderContract <- activateContractWallet w2 (soulboundContract testParams)
        
        -- Attempt transfer should fail
        result <- Trace.callEndpoint @"transfer" holderContract (walletPubKey w3)
        
        -- Assert transfer failed
        Test.assertContract issuerContract $ do
            Test.assertFalse "Transfer should fail" result

-- | Test token revocation by issuer
testRevocation :: TestTree
testRevocation = testCase "Issuer can revoke soulbound token" $
    Test.runEmulatorTraceIO' def emTrace
  where
    emTrace :: EmulatorTrace ()
    emTrace = do
        -- Activate contract for issuer (w1)
        issuerContract <- activateContractWallet w1 (soulboundContract testParams)
        
        -- Mint token to w2
        void $ Trace.callEndpoint @"mint" issuerContract (walletPubKey w2)
        void $ waitNSlots 2
        
        -- Revoke token
        void $ Trace.callEndpoint @"revoke" issuerContract ()
        void $ waitNSlots 2
        
        -- Check token is revoked
        result <- Trace.callEndpoint @"check" issuerContract ()
        
        -- Assert token is revoked
        Test.assertContract issuerContract $ do
            Test.assertFalse "Token should be revoked" result

-- | Test token expiration
testExpiration :: TestTree
testExpiration = testCase "Soulbound token expires correctly" $
    Test.runEmulatorTraceIO' def emTrace
  where
    emTrace :: EmulatorTrace ()
    emTrace = do
        -- Create params with expiration
        let expiredParams = testParams { stpExpiration = Just 100 }
        
        -- Activate contract
        contract <- activateContractWallet w1 (soulboundContract expiredParams)
        
        -- Mint token
        void $ Trace.callEndpoint @"mint" contract (walletPubKey w2)
        void $ waitNSlots 2
        
        -- Check token validity after expiration
        result <- Trace.callEndpoint @"check" contract ()
        
        -- Assert token is expired
        Test.assertContract contract $ do
            Test.assertFalse "Token should be expired" result
