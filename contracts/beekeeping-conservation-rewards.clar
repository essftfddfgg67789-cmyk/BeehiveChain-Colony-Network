;; beekeeping-conservation-rewards
;; Token rewards for maintaining healthy bee colonies and supporting pollinator conservation

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_INSUFFICIENT_BALANCE (err u401))
(define-constant ERR_INVALID_AMOUNT (err u402))
(define-constant ERR_REWARD_NOT_FOUND (err u403))
(define-constant ERR_ALREADY_CLAIMED (err u404))
(define-constant ERR_STAKE_NOT_FOUND (err u405))
(define-constant ERR_STAKE_LOCKED (err u406))

;; Token constants
(define-constant TOKEN_NAME "BeehiveChain Conservation Token")
(define-constant TOKEN_SYMBOL "BHCT")
(define-constant TOKEN_DECIMALS u6)
(define-constant INITIAL_SUPPLY u1000000000000) ;; 1M tokens with 6 decimals

;; Reward multipliers
(define-constant HEALTH_BONUS_MULTIPLIER u150) ;; 1.5x for healthy colonies
(define-constant DISEASE_PREVENTION_MULTIPLIER u200) ;; 2x for disease prevention
(define-constant CONSERVATION_MULTIPLIER u175) ;; 1.75x for conservation activities
(define-constant EARLY_ADOPTER_MULTIPLIER u125) ;; 1.25x for early participants

;; Staking parameters
(define-constant MIN_STAKE_AMOUNT u1000000) ;; 1 token minimum stake
(define-constant STAKE_LOCK_PERIOD u144000) ;; ~100 days in blocks
(define-constant ANNUAL_STAKE_REWARD_RATE u8) ;; 8% annual reward rate

;; data maps and vars
(define-map token-balances
  { account: principal }
  { balance: uint }
)

(define-map reward-claims
  { claim-id: uint }
  {
    claimant: principal,
    reward-type: (string-ascii 50),
    base-amount: uint,
    multiplier: uint,
    final-amount: uint,
    claimed-at: uint,
    verified: bool,
    verifier: (optional principal),
    evidence-hash: (optional (string-ascii 64)),
    notes: (string-ascii 200)
  }
)

(define-map staking-positions
  { stake-id: uint }
  {
    staker: principal,
    amount: uint,
    start-block: uint,
    lock-period: uint,
    rewards-claimed: uint,
    auto-renew: bool,
    active: bool
  }
)

(define-map governance-proposals
  { proposal-id: uint }
  {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposal-type: (string-ascii 50),
    votes-for: uint,
    votes-against: uint,
    voting-ends: uint,
    executed: bool,
    execution-data: (optional (string-ascii 200))
  }
)

(define-map user-achievements
  { user: principal }
  {
    total-rewards-earned: uint,
    conservation-score: uint,
    hive-maintenance-score: uint,
    community-participation-score: uint,
    achievements-unlocked: (list 20 (string-ascii 50)),
    level: uint,
    badges: (list 10 (string-ascii 30))
  }
)

(define-map reward-pools
  { pool-name: (string-ascii 50) }
  {
    total-allocated: uint,
    total-distributed: uint,
    active: bool,
    distribution-rate: uint,
    eligibility-criteria: (string-ascii 200)
  }
)

(define-data-var total-supply uint INITIAL_SUPPLY)
(define-data-var claim-counter uint u0)
(define-data-var stake-counter uint u0)
(define-data-var proposal-counter uint u0)
(define-data-var contract-active bool true)
(define-data-var total-staked uint u0)
(define-data-var governance-threshold uint u5000000) ;; 5 tokens minimum to propose

;; private functions
(define-private (mint-tokens (recipient principal) (amount uint))
  (let (
    (current-balance (default-to u0 (get balance (map-get? token-balances { account: recipient }))))
  )
    (map-set token-balances { account: recipient } 
             { balance: (+ current-balance amount) })
    (var-set total-supply (+ (var-get total-supply) amount))
    true
  )
)

(define-private (transfer-tokens (sender principal) (recipient principal) (amount uint))
  (let (
    (sender-balance (default-to u0 (get balance (map-get? token-balances { account: sender }))))
    (recipient-balance (default-to u0 (get balance (map-get? token-balances { account: recipient }))))
  )
    (asserts! (>= sender-balance amount) false)
    (map-set token-balances { account: sender } 
             { balance: (- sender-balance amount) })
    (map-set token-balances { account: recipient } 
             { balance: (+ recipient-balance amount) })
    true
  )
)

(define-private (calculate-reward-with-multiplier (base-amount uint) (multiplier uint))
  (/ (* base-amount multiplier) u100)
)

(define-private (calculate-staking-reward (amount uint) (blocks-staked uint))
  (let (
    (annual-blocks u52560) ;; Approximate blocks per year
    (reward-rate ANNUAL_STAKE_REWARD_RATE)
    (time-factor (/ blocks-staked annual-blocks))
  )
    (/ (* (* amount reward-rate) time-factor) u100)
  )
)

(define-private (update-user-achievement (user principal) (achievement-type (string-ascii 50)) (points uint))
  (let (
    (current-data (default-to 
                    { 
                      total-rewards-earned: u0, 
                      conservation-score: u0, 
                      hive-maintenance-score: u0, 
                      community-participation-score: u0, 
                      achievements-unlocked: (list), 
                      level: u1, 
                      badges: (list) 
                    }
                    (map-get? user-achievements { user: user })))
    (new-total (+ (get total-rewards-earned current-data) points))
    (new-conservation-score (if (is-eq achievement-type "CONSERVATION")
                               (+ (get conservation-score current-data) points)
                               (get conservation-score current-data)))
    (new-hive-score (if (is-eq achievement-type "HIVE_MAINTENANCE")
                       (+ (get hive-maintenance-score current-data) points)
                       (get hive-maintenance-score current-data)))
    (new-level (calculate-user-level new-total))
  )
    (map-set user-achievements { user: user }
             (merge current-data {
               total-rewards-earned: new-total,
               conservation-score: new-conservation-score,
               hive-maintenance-score: new-hive-score,
               level: new-level
             }))
    true
  )
)

(define-private (calculate-user-level (total-rewards uint))
  (if (< total-rewards u1000000) 
      u1
      (if (< total-rewards u5000000)
          u2
          (if (< total-rewards u10000000)
              u3
              (if (< total-rewards u25000000)
                  u4
                  (if (< total-rewards u50000000)
                      u5
                      u6)))))
)

;; public functions
(define-public (claim-conservation-reward (reward-type (string-ascii 50)) (base-amount uint) (evidence-hash (optional (string-ascii 64))) (notes (string-ascii 200)))
  (let (
    (new-claim-id (+ (var-get claim-counter) u1))
    (multiplier (get-reward-multiplier reward-type))
    (final-amount (calculate-reward-with-multiplier base-amount multiplier))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (> base-amount u0) ERR_INVALID_AMOUNT)
    
    (map-set reward-claims { claim-id: new-claim-id }
             {
               claimant: tx-sender,
               reward-type: reward-type,
               base-amount: base-amount,
               multiplier: multiplier,
               final-amount: final-amount,
               claimed-at: stacks-block-height,
               verified: false,
               verifier: none,
               evidence-hash: evidence-hash,
               notes: notes
             })
    
    (var-set claim-counter new-claim-id)
    
    ;; Mint tokens for verified reward types or small amounts
    (if (or (<= final-amount u100000) (is-eq reward-type "SURVEY_COMPLETION"))
        (begin
          (unwrap! (mint-tokens tx-sender final-amount) ERR_UNAUTHORIZED)
          (unwrap! (update-user-achievement tx-sender reward-type final-amount) ERR_UNAUTHORIZED)
          (map-set reward-claims { claim-id: new-claim-id }
                   (merge (unwrap! (map-get? reward-claims { claim-id: new-claim-id }) ERR_REWARD_NOT_FOUND)
                          { verified: true, verifier: (some CONTRACT_OWNER) }))
        )
        true
    )
    
    (print { 
      event: "reward-claimed", 
      claim-id: new-claim-id, 
      claimant: tx-sender, 
      reward-type: reward-type,
      final-amount: final-amount
    })
    (ok new-claim-id)
  )
)

(define-private (get-reward-multiplier (reward-type (string-ascii 50)))
  (if (is-eq reward-type "HEALTHY_COLONY")
      HEALTH_BONUS_MULTIPLIER
      (if (is-eq reward-type "DISEASE_PREVENTION")
          DISEASE_PREVENTION_MULTIPLIER
          (if (is-eq reward-type "CONSERVATION_ACTIVITY")
              CONSERVATION_MULTIPLIER
              (if (is-eq reward-type "EARLY_ADOPTER")
                  EARLY_ADOPTER_MULTIPLIER
                  u100))))
)

(define-public (verify-reward-claim (claim-id uint) (approved bool))
  (let (
    (claim-data (unwrap! (map-get? reward-claims { claim-id: claim-id }) ERR_REWARD_NOT_FOUND))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (not (get verified claim-data)) ERR_ALREADY_CLAIMED)
    
    (if approved
        (begin
          (unwrap! (mint-tokens (get claimant claim-data) (get final-amount claim-data)) ERR_UNAUTHORIZED)
          (unwrap! (update-user-achievement (get claimant claim-data) (get reward-type claim-data) (get final-amount claim-data)) ERR_UNAUTHORIZED)
          (map-set reward-claims { claim-id: claim-id }
                   (merge claim-data { verified: true, verifier: (some tx-sender) }))
        )
        (map-set reward-claims { claim-id: claim-id }
                 (merge claim-data { verified: false, verifier: (some tx-sender) }))
    )
    
    (print { event: "reward-verified", claim-id: claim-id, approved: approved })
    (ok true)
  )
)

(define-public (stake-tokens (amount uint) (lock-period uint) (auto-renew bool))
  (let (
    (new-stake-id (+ (var-get stake-counter) u1))
    (user-balance (default-to u0 (get balance (map-get? token-balances { account: tx-sender }))))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (>= amount MIN_STAKE_AMOUNT) ERR_INVALID_AMOUNT)
    (asserts! (>= user-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (>= lock-period STAKE_LOCK_PERIOD) ERR_INVALID_AMOUNT)
    
    ;; Transfer tokens from user to staking
    (unwrap! (transfer-tokens tx-sender CONTRACT_OWNER amount) ERR_INSUFFICIENT_BALANCE)
    
    (map-set staking-positions { stake-id: new-stake-id }
             {
               staker: tx-sender,
               amount: amount,
               start-block: stacks-block-height,
               lock-period: lock-period,
               rewards-claimed: u0,
               auto-renew: auto-renew,
               active: true
             })
    
    (var-set stake-counter new-stake-id)
    (var-set total-staked (+ (var-get total-staked) amount))
    
    (print { 
      event: "tokens-staked", 
      stake-id: new-stake-id, 
      staker: tx-sender, 
      amount: amount, 
      lock-period: lock-period 
    })
    (ok new-stake-id)
  )
)

(define-public (unstake-tokens (stake-id uint))
  (let (
    (stake-data (unwrap! (map-get? staking-positions { stake-id: stake-id }) ERR_STAKE_NOT_FOUND))
    (unlock-block (+ (get start-block stake-data) (get lock-period stake-data)))
    (staking-reward (calculate-staking-reward (get amount stake-data) 
                                             (- stacks-block-height (get start-block stake-data))))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get staker stake-data)) ERR_UNAUTHORIZED)
    (asserts! (get active stake-data) ERR_STAKE_NOT_FOUND)
    (asserts! (>= stacks-block-height unlock-block) ERR_STAKE_LOCKED)
    
    ;; Return staked tokens plus rewards
    (unwrap! (mint-tokens tx-sender staking-reward) ERR_UNAUTHORIZED)
    (unwrap! (transfer-tokens CONTRACT_OWNER tx-sender (get amount stake-data)) ERR_INSUFFICIENT_BALANCE)
    
    ;; Update stake position
    (map-set staking-positions { stake-id: stake-id }
             (merge stake-data { 
               active: false, 
               rewards-claimed: (+ (get rewards-claimed stake-data) staking-reward) 
             }))
    
    (var-set total-staked (- (var-get total-staked) (get amount stake-data)))
    
    ;; Handle auto-renewal
    (if (get auto-renew stake-data)
        (unwrap! (stake-tokens (get amount stake-data) (get lock-period stake-data) true) ERR_UNAUTHORIZED)
        true)
    
    (print { 
      event: "tokens-unstaked", 
      stake-id: stake-id, 
      amount: (get amount stake-data), 
      rewards: staking-reward 
    })
    (ok { amount: (get amount stake-data), rewards: staking-reward })
  )
)

(define-public (create-governance-proposal (title (string-ascii 100)) (description (string-ascii 500)) (proposal-type (string-ascii 50)) (execution-data (optional (string-ascii 200))))
  (let (
    (new-proposal-id (+ (var-get proposal-counter) u1))
    (user-balance (default-to u0 (get balance (map-get? token-balances { account: tx-sender }))))
    (voting-period u1008) ;; ~1 week in blocks
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (>= user-balance (var-get governance-threshold)) ERR_UNAUTHORIZED)
    
    (map-set governance-proposals { proposal-id: new-proposal-id }
             {
               proposer: tx-sender,
               title: title,
               description: description,
               proposal-type: proposal-type,
               votes-for: u0,
               votes-against: u0,
               voting-ends: (+ stacks-block-height voting-period),
               executed: false,
               execution-data: execution-data
             })
    
    (var-set proposal-counter new-proposal-id)
    
    (print { 
      event: "proposal-created", 
      proposal-id: new-proposal-id, 
      proposer: tx-sender, 
      title: title 
    })
    (ok new-proposal-id)
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote-for bool) (voting-power uint))
  (let (
    (proposal-data (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) ERR_REWARD_NOT_FOUND))
    (user-balance (default-to u0 (get balance (map-get? token-balances { account: tx-sender }))))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (< stacks-block-height (get voting-ends proposal-data)) ERR_UNAUTHORIZED)
    (asserts! (<= voting-power user-balance) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> voting-power u0) ERR_INVALID_AMOUNT)
    
    (if vote-for
        (map-set governance-proposals { proposal-id: proposal-id }
                 (merge proposal-data { votes-for: (+ (get votes-for proposal-data) voting-power) }))
        (map-set governance-proposals { proposal-id: proposal-id }
                 (merge proposal-data { votes-against: (+ (get votes-against proposal-data) voting-power) })))
    
    (print { 
      event: "vote-cast", 
      proposal-id: proposal-id, 
      voter: tx-sender, 
      vote-for: vote-for, 
      voting-power: voting-power 
    })
    (ok true)
  )
)

;; read-only functions
(define-read-only (get-balance (account principal))
  (default-to u0 (get balance (map-get? token-balances { account: account })))
)

(define-read-only (get-reward-claim (claim-id uint))
  (map-get? reward-claims { claim-id: claim-id })
)

(define-read-only (get-staking-position (stake-id uint))
  (map-get? staking-positions { stake-id: stake-id })
)

(define-read-only (get-governance-proposal (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id })
)

(define-read-only (get-user-achievements (user principal))
  (map-get? user-achievements { user: user })
)

(define-read-only (get-contract-stats)
  {
    total-supply: (var-get total-supply),
    total-claims: (var-get claim-counter),
    total-stakes: (var-get stake-counter),
    total-proposals: (var-get proposal-counter),
    total-staked: (var-get total-staked),
    contract-active: (var-get contract-active)
  }
)

(define-read-only (calculate-potential-rewards (reward-type (string-ascii 50)) (base-amount uint))
  (let (
    (multiplier (get-reward-multiplier reward-type))
  )
    (calculate-reward-with-multiplier base-amount multiplier)
  )
)

;; Initialize contract with owner balance
(begin
  (unwrap! (mint-tokens CONTRACT_OWNER INITIAL_SUPPLY) ERR_UNAUTHORIZED)
)

