#import "../diagrams-template.typ": *

= Create Stake Position
Creates a stake position UTxO with a stake NFT and the initial staked tokens.

#let tx_create_stake_position = [
#vanilla_transaction(
  "Create Stake Position",
  mint: (
    "stakeNFT": "1",
  ),
  inputs: (
    (
      name: "Owner UTxO",
      value: (
        "stakedToken": [*N*],
      ),
    ),
  ),
  outputs: (
    (
      name: "Stake UTxO",
      address: "stake_addr",
      value: (
        "stakeNFT": "1",
        "stakedToken": [*N*],
      ),
      datum: (
        "owner": "Credential",
        "delegatee": "Maybe Credential",
        "lockedBy": [[]],
      ),
    ),
  ),
  signatures: (
    "owner",
  ),
)
]

#figure(tx_create_stake_position)
#pagebreak()

= Deposit Stake
Adds more staked tokens to an existing stake position UTxO.

#let tx_deposit_stake = [
#vanilla_transaction(
  "Deposit Stake",
  inputs: (
    (
      name: "Stake UTxO",
      address: "stake_addr",
      redeemer: [Deposit],
      value: (
        "stakeNFT": "1",
        "stakedToken": [*N*],
      ),
      datum: (
        "owner": "",
        "delegatee": "",
        "lockedBy": "",
      ),
    ),
    (
      name: "Owner UTxO",
      value: (
        "stakedToken": [*M*],
      ),
    ),
  ),
  outputs: (
    (
      name: "Stake UTxO",
      address: "stake_addr",
      value: (
        "stakeNFT": "1",
        "stakedToken": [*N + M*],
      ),
      datum: (
        "owner": "",
        "delegatee": "",
        "lockedBy": "",
      ),
    ),
  ),
  signatures: (
    "owner",
  )
)
]

#figure(tx_deposit_stake)
#pagebreak()

= Withdraw Stake
Removes a portion of free staked tokens from a stake position.

#let tx_withdraw_stake = [
#vanilla_transaction(
  "Withdraw Stake",
  inputs: (
    (
      name: "Stake UTxO",
      address: "stake_addr",
      redeemer: [#h(-0.5em) Withdraw {M}],
      value: (
        "stakeNFT": "1",
        "stakedToken": [*N*],
      ),
      datum: (
        "owner": "",
        "delegatee": "",
        "lockedBy": [L],
      ),
    ),
  ),
  outputs: (
    (
      name: "Stake UTxO",
      address: "stake_addr",
      value: (
        "stakeNFT": "1",
        "stakedToken": [*N - M*],
      ),
      datum: (
        "owner": "",
        "delegatee": "",
        "lockedBy": [L'],
      ),
    ),
    (
      name: "Owner UTxO",
      address: "owner_addr",
      value: (
        "stakedToken": [*M*],
      ),
    ),
  ),
  signatures: (
    "owner",
  ),
  notes: [

    $L' = [("pId"_1, t_1, s_1), ... , ("pId"_n, t_n, s_n)]$
    - `lockedStaked = max(s_i)`
    - `freeStaked = N - lockedStaked`
    - `M <= freeStaked`
  ],
)
]

#figure(tx_withdraw_stake)
#pagebreak()

= Close Stake Position
Burns the stake NFT and returns all staked tokens after all locks expire.

#let tx_close_stake_position = [
#vanilla_transaction(
  "Close Stake Position",
  mint: (
    "stakeNFT": "-1",
  ),
  inputs: (
    (
      name: "Stake UTxO",
      address: "stake_addr",
      redeemer: [ClosePosition],
      value: (
        "stakeNFT": "1",
        "stakedToken": [*N*],
      ),
      datum: (
        "owner": "",
        "delegatee": "",
        "lockedBy": [L],
      ),
    ),
  ),
  outputs: (
    (
      name: "Owner UTxO",
      address: "owner_addr",
      value: (
        "stakedToken": [*N*],
      ),
    ),
  ),
  validRange: ("lower": "T"),
  signatures: (
    "owner",
  ),
  notes: [

    $L = [("pId"_1, t_1, s_1), ... , ("pId"_n, t_n, s_n)]$

    $t_i <= "T" forall i$
  ],
)
]

#figure(tx_close_stake_position)
#pagebreak()

= Delegate Stake
Updates the delegatee of a stake position to redirect voting power.

#let tx_delegate_stake = [
#vanilla_transaction(
  "Delegate Stake",
  inputs: (
    (
      name: "Stake UTxO",
      address: "stake_addr",
      redeemer: [R],
      value: (
        "stakeNFT": "1",
        "stakedToken": [*N*],
      ),
      datum: (
        "owner": "",
        "delegatee": "",
        "lockedBy": "",
      ),
    ),
  ),
  outputs: (
    (
      name: "Stake UTxO",
      address: "stake_addr",
      value: (
        "stakeNFT": "1",
        "stakedToken": [*N*],
      ),
      datum: (
        "owner": "",
        "delegatee": [*newDelegatee*],
        "lockedBy": "",
      ),
    ),
  ),
  signatures: (
    "owner",
  ),
  notes: [

    R = DelegateTo { newDelegatee }
  ],
)
]

#figure(tx_delegate_stake)
#pagebreak()

= Create Proposal
Mints a proposal NFT and starts a new governance proposal in draft phase.

#let tx_create_proposal = [
#vanilla_transaction(
  "Create Proposal",
  mint: (
    "proposalNFT": "1",
  ),
  inputs: (
    (
      name: "Stake UTxO",
      address: "stake_addr",
      redeemer: [#h(-1em) CreateProposal],
      value: (
        "stakeNFT": "1",
        "stakedToken": [*S*],
      ),
      datum: (
        "owner": "",
        "delegatee": "",
        "lockedBy": [L],
      ),
    ),
    (
      name: "Settings UTxO",
      address: "governor_addr",
      reference: true,
      value: (
        "settingsNFT": "1",
      ),
      datum: (
        "proposalThresholds": "",
        "proposalTimings": "",
      ),
    ),
  ),
  outputs: (
    (
      name: "Stake UTxO",
      address: "stake_addr",
      value: (
        "stakeNFT": "1",
        "stakedToken": [*S*],
      ),
      datum: (
        "owner": "",
        "delegatee": "",
        "lockedBy": [L'],
      ),
    ),
    (
      name: "Proposal UTxO",
      address: "proposal_addr",
      value: (
        "proposalNFT": "1",
      ),
      datum: (
        "thresholds": [proposalThresholds],
        "timingConfig": [proposalTimingConfig],
        "startingTime": [*T*],
        "status": [Draft { cosigningStake: S }],
        "results": "",
      ),
    ),
  ),
  signatures: (
    "owner",
  ),
  validRange: (
    "lower": [*T*],
    "upper": [*T + maxWidth*],
  ),
  notes: [
    - `pId = proposalNFT.tokenName = hash(stakeUtxo.outputReference)`
    - `L' = [..L, (pId, T + timingConfig.draftlength, S)]`
    - `S >= thresholds.create`
  ],
)
]

#figure(tx_create_proposal)
#pagebreak()

= Cosign Proposal
Adds stake to a proposal's cosigning requirements during the draft phase.

#let tx_cosign_proposal = [
#vanilla_transaction(
  "Cosign Proposal",
  inputs: (
    (
      name: "Proposal UTxO",
      address: "proposal_addr",
      redeemer: [Cosign],
      value: (
        "proposalNFT": "1",
      ),
      datum: (
        "thresholds": "",
        "timingConfig": "",
        "startingTime": "",
        "status": [Draft {cosigningStake: N}],
        "results": "",
      ),
    ),
    (
      name: "Stake UTxO",
      address: "stake_addr",
      redeemer: [Cosign],
      value: (
        "stakeNFT": "1",
        "stakedToken": [*S*],
      ),
      datum: (
        "owner": "",
        "delegatee": "",
        "lockedBy": [L],
      ),
    ),
  ),
  outputs: (
    (
      name: "Proposal UTxO",
      address: "proposal_addr",
      value: (
        "proposalNFT": "1",
      ),
      datum: (
        "thresholds": "",
        "timingConfig": "",
        "startingTime": "",
        "status": [Draft {cosigningStake: N + S}],
        "results": "",
      )
    ),
    (
      name: "Stake UTxO",
      address: "stake_addr",
      value: (
        "stakeNFT": "1",
        "stakedToken": [*S*],
      ),
      datum: (
        "owner": "",
        "delegatee": "",
        "lockedBy": [L'],
      ),
    ),
  ),
  signatures: (
    [*auth*],
  ),
  validRange: (
    "upper": [*T'*],
  ),
  notes: [
    - `pId = proposalNFT.tokenName`
    - `pId not in L`
    - `T' = startingTime + timingConfig.draftLength`
    - `L' = [..L, (pId, T', S)]`
    - `S >= thresholds.cosign`
    ```
    auth = when delegatee is
      Some d = d
      None = owner
    ```
  ],
)
]

#figure(tx_cosign_proposal)
#pagebreak()

= Accept Draft
Advances a proposal from draft to voting phase once co-signing thresholds are met.

#let tx_accept_draft = [
#vanilla_transaction(
  "Accept Draft",
  inputs: (
    (
      name: "Proposal UTxO",
      address: "proposal_addr",
      redeemer: [AcceptDraft],
      value: (
        "proposalNFT": "1",
      ),
      datum: (
        "thresholds": "",
        "timingConfig": "",
        "startTime": "",
        "status": [Draft { cosignStake: N }],
        "results": "",
      ),
    ),
  ),
  outputs: (
    (
      name: "Proposal UTxO",
      address: "proposal_addr",
      value: (
        "proposalNFT": "1",
      ),
      datum: (
        "thresholds": "",
        "timingConfig": "",
        "startTime": "",
        "status": [Voting],
        "results": "",
      ),
    ),
  ),
  validRange: (
    "upper": [*T'*],
  ),
  notes: [
    - T' = startingTime + timingConfig.draftLength
    - N >= thresholds.accept
  ],
)
]

#figure(tx_accept_draft)
#pagebreak()

= Reject Draft
Destroys a proposal that fails to meet co-signing thresholds before the draft deadline.

#let tx_reject_draft = [
#vanilla_transaction(
  "Reject Draft",
  inputs: (
    (
      name: "Proposal UTxO",
      address: "proposal_addr",
      redeemer: [RejectDraft],
      value: (
        "proposalNFT": "1",
      ),
      datum: (
        "thresholds": "",
        "timingConfig": "",
        "startTime": "",
        "status": [Draft { cosignStake: N }],
        "results": "",
      ),
    ),
  ),
  mint: ("proposalNFT": "-1"),
  validRange: (
    "lower": [*T'*],
  ),
  notes: [
    - T' = startingTime + timingConfig.draftLength
  ],
)
]

#figure(tx_reject_draft)
#pagebreak()

= Vote
Casts a vote on a proposal by minting a vote NFT locked to the voter's choice.

#let tx_vote = [
#vanilla_transaction(
  "Vote",
  mint: (
    "voteNFT": "1",
  ),
  inputs: (
    (
      name: "Stake UTxO",
      address: "stake_addr",
      redeemer: [VoteProposal],
      value: (
        "stakeNFT": "1",
        "stakedToken": [*S*],
      ),
      datum: (
        "owner": "",
        "delegatee": "",
        "lockedBy": [L],
      ),
    ),
    (
      name: "Proposal UTxO",
      address: "proposal_addr",
      reference: true,
      value: (
        "proposalNFT": "1",
      ),
      datum: (
        "thresholds": "",
        "timingConfig": "",
        "startTime": [T],
        "status": [Voting],
        "results": "",
      ),
    ),
  ),
  outputs: (
    (
      name: "Stake UTxO",
      address: "stake_addr",
      value: (
        "stakeNFT": "1",
        "stakedToken": [*S*],
      ),
      datum: (
        "owner": "",
        "delegatee": "",
        "lockedBy": [L'],
      ),
    ),
    (
      name: "Vote UTxO",
      address: "vote_addr",
      value: (
        "voteNFT": "1",
      ),
      datum: (
        "stakeOwner": "Address",
        "proposal": [pID],
        "votedOption": "Integer",
        "stake": [S],
      ),
    ),
  ),
  signatures: (
    "auth",
  ),
  validRange: (
    "upper": [*T'*],
  ),
  notes: [
    - `pId = proposalNFT.tokenName`
    - `pId not in L`
    - `L' = [..L, (pId, T, S)]`
    - `S >= thresholds.vote`

    - `T' = T + timingConfig.draftLength + timingConfig.votingLength`
    ```
    auth = when delegatee is
      Some d = d
      None = owner
    ```
  ],
)
]

#figure(tx_vote)
#pagebreak()

= Close Vote
Cancels a vote by burning its NFT, releasing the stake owner's ADA.

#let tx_close_vote = [
#vanilla_transaction(
  "Close Vote",
  mint: (
    "voteNFT": "-1",
  ),
  inputs: (
    (
      name: "Vote UTxO",
      address: "vote_addr",
      redeemer: [Cancel],
      value: (
        "ADA": "A",
        "voteNFT": "1",
      ),
      datum: (
        "stakeOwner": "",
        "proposal": "",
        "votedOption": "",
        "stake": "",
      ),
    ),
  ),
  outputs: (
    (
      name: "Owner UTxO",
      address: "owner_addr",
      value: (
        "ADA": "A",
      ),
    ),
  ),
  signatures: (
    [*auth*],
  ),
  notes: [
    ```
    auth = stakeOwner
    ```
  ],
)
]

#figure(tx_close_vote)
#pagebreak()

= End Voting Stage
Closes the voting period and transitions the proposal to the tally stage.

#let tx_end_voting_stage = [
#vanilla_transaction(
  "End Voting Stage",
  inputs: (
    (
      name: "Proposal UTxO",
      address: "proposal_addr",
      redeemer: [#h(-1em) EndVotingStage],
      value: (
        "proposalNFT": "1",
      ),
      datum: (
        "thresholds": "",
        "timingConfig": "",
        "startingTime": "",
        "status": [Voting],
        "results": ""
      ),
    ),
  ),
  outputs: (
    (
      name: "Proposal UTxO",
      address: "proposal_addr",
      value: (
        "proposalNFT": "1",
      ),
      datum: (
        "thresholds": "",
        "timingConfig": "",
        "startingTime": "",
        "status": [Tally { votes }],
        "results": ""
      ),
    ),
  ),
  validRange: (
    "lower": [*T'*],
  ),
  notes: [
    - `T' = T + timingConfig.draftLength + timingConfig.votingLength`
    - votes = {}
  ],
)
]

#figure(tx_end_voting_stage)
#pagebreak()

= Tally
Counts all votes submitted for a proposal and updates the results.

#let tx_tally = [
#vanilla_transaction(
  "Tally",
  mint: (
    "voteNFT₁": "-1",
    "...": "-",
    "voteNFTₙ": "-1"
  ),
  inputs: (
    (
      name: "Proposal UTxO",
      address: "proposal_addr",
      redeemer: [TallyVotes],
      value: (
        "proposalNFT": "1",
      ),
      datum: (
        "thresholds": "",
        "timingConfig": "",
        "startingTime": [T],
        "status": [Tally { votes }],
        "results": "",
      ),
    ),
    (
      name: "Vote UTxO₁",
      address: "vote_addr",
      redeemer: [()],
      value: (
        "ADA": "A₁",
        "voteNFT₁": "1",
      ),
      datum: (
        "stakeOwner": [addr₁],
        "proposal": [*pId*],
        "votedOption": [*rt₁*],
        "stake": [*S₁*],
      ),
    ),
    ("dots": ""),
    (
      name: "Vote UTxOₙ",
      address: "vote_addr",
      redeemer: [()],
      value: (
        "ADA": "Aₙ",
        "voteNFTₙ": "1",
      ),
      datum: (
        "stakeOwner": [addrₙ],
        "proposal": [*pId*],
        "votedOption": [*rtₙ*],
        "stake": [*Sₙ*],
      ),
    ),
  ),
  outputs: (
    (
      name: "Proposal UTxO",
      address: "proposal_addr",
      value: (
        "proposalNFT": "1",
      ),
    datum: (
        "thresholds": "",
        "timingConfig": "",
        "startingTime": "",
        "status": [Tally { votes' }],
        "results": "",
      ),
    ),
    (
      name: "User UTxO",
      address: "addr₁",
      value: (
        "ADA": "A₁",
      ),
    ),
    ("dots": ""),
    (
      name: "User UTxO",
      address: "addrₙ",
      value: (
        "ADA": "Aₙ",
      ),
    ),
  ),
  validRange: (
    "upper": [*T'*],
  ),
  withdrawals: (
    "tallyValidator",
  ),
  notes: [
    - `pId = proposalNFT.tokenName`
    - `T' = T + timingConfig.draftLength + timingConfig.votingLength + timingConfig.tallyLength`
    - `votes` map get each $"rt"_i$ incremented by $S_i$
  ],
)
]

#figure(tx_tally)
#pagebreak()

= End Proposal
Executes the winning outcome or destroys a failed proposal after the tally period.

#let tx_end_proposal = [
#vanilla_transaction(
  "End Proposal",
  inputs: (
    (
      name: "Proposal UTxO",
      address: "proposal_addr",
      redeemer: [EndProposal],
      value: (
        "proposalNFT": "1",
      ),
      datum: (
        "thresholds": "",
        "timingConfig": "",
        "startingTime": [*T*],
        "status": [Tally { votes }],
        "results": ""
      ),
    ),
  ),
  mint: ("proposalNFT": "-1"),
  validRange: (
    "lower": [*T'*],
  ),
  withdrawals: ([$"e"_w$],),
  notes: [
    - T' = T + timingConfig.draftLength + timingConfig.votingLength + timingConfig.tallyLength
    - votes = ${"rt"_1: v_i, ..., "rt"_n: v_n}$
    - mostVoted = $"rt"_i "where" v_i > v_j forall j != i$
    - `v_i >= thresholds.execute`
    - $e_w$ = results[$"rt"_i$]

    if tie or not enough votes, just destroy UTxO (ie. $e_w$ = None)
  ],
)
]

#figure(tx_end_proposal)
