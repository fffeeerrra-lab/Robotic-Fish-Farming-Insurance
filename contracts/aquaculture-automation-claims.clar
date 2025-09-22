;; aquaculture-automation-claims
;; Instant claims processing for robotic fish farming system failures

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u3001))
(define-constant ERR_NOT_FOUND (err u3002))
(define-constant ERR_INVALID_PARAMS (err u3003))
(define-constant ERR_CLAIM_EXISTS (err u3004))
(define-constant ERR_INSUFFICIENT_COVERAGE (err u3005))
(define-constant ERR_CLAIM_EXPIRED (err u3006))
(define-constant ERR_INVALID_CLAIM_STATUS (err u3007))
(define-constant ERR_PAYOUT_FAILED (err u3008))

;; Claim status constants
(define-constant CLAIM_SUBMITTED u1)
(define-constant CLAIM_REVIEWING u2)
(define-constant CLAIM_APPROVED u3)
(define-constant CLAIM_REJECTED u4)
(define-constant CLAIM_PAID u5)
(define-constant CLAIM_APPEALED u6)

;; Failure type constants
(define-constant FAILURE_EQUIPMENT u1)
(define-constant FAILURE_FISH_HEALTH u2)
(define-constant FAILURE_ENVIRONMENTAL u3)
(define-constant FAILURE_NAVIGATION u4)
(define-constant FAILURE_AUTOMATION u5)

;; Coverage type constants
(define-constant COVERAGE_BASIC u1)
(define-constant COVERAGE_PREMIUM u2)
(define-constant COVERAGE_COMPREHENSIVE u3)

;; data vars
(define-data-var next-claim-id uint u1)
(define-data-var total-claims uint u0)
(define-data-var approved-claims uint u0)
(define-data-var total-payouts uint u0)
(define-data-var pending-claims uint u0)
(define-data-var insurance-pool uint u10000000) ;; 10M initial pool
(define-data-var claim-processing-fee uint u1000) ;; Processing fee in microstacks

;; data maps
(define-map insurance-policies
  { policy-id: (string-ascii 64) }
  {
    id: uint,
    policyholder: principal,
    coverage-type: uint,
    premium-paid: uint,
    coverage-amount: uint,
    deductible: uint,
    policy-start: uint,
    policy-end: uint,
    equipment-covered: (list 10 (string-ascii 64)),
    tanks-covered: (list 10 (string-ascii 64)),
    active: bool,
    claims-count: uint,
    last-claim: uint
  }
)

(define-map insurance-claims
  { claim-id: (string-ascii 64) }
  {
    id: uint,
    policy-id: (string-ascii 64),
    claimant: principal,
    failure-type: uint,
    affected-equipment: (string-ascii 64),
    affected-tanks: (list 5 (string-ascii 64)),
    claim-amount: uint,
    actual-loss: uint,
    incident-date: uint,
    claim-date: uint,
    status: uint,
    description: (string-ascii 512),
    evidence-hash: (string-ascii 64),
    assessor: principal,
    assessment-notes: (string-ascii 512),
    payout-amount: uint,
    payout-date: uint
  }
)

(define-map claim-evidence
  { claim-id: (string-ascii 64), evidence-type: (string-ascii 32) }
  {
    data-hash: (string-ascii 64),
    timestamp: uint,
    source: (string-ascii 64),
    verified: bool,
    uploader: principal
  }
)

(define-map loss-assessments
  { claim-id: (string-ascii 64) }
  {
    assessor: principal,
    assessment-date: uint,
    damage-severity: uint,
    repair-cost: uint,
    replacement-cost: uint,
    business-interruption: uint,
    total-assessed-loss: uint,
    recommended-payout: uint,
    assessment-confidence: uint,
    notes: (string-ascii 512)
  }
)

(define-map authorized-assessors
  { assessor: principal }
  {
    authorized: bool,
    specialization: (string-ascii 64),
    license-number: (string-ascii 32),
    assessment-count: uint,
    approval-rating: uint
  }
)

(define-map payout-history
  { claim-id: (string-ascii 64) }
  {
    amount: uint,
    payout-date: uint,
    transaction-id: (string-ascii 64),
    method: (string-ascii 32),
    recipient: principal,
    processed-by: principal
  }
)

;; public functions

(define-public (create-insurance-policy
  (policy-id (string-ascii 64))
  (coverage-type uint)
  (coverage-amount uint)
  (deductible uint)
  (policy-duration uint)
  (equipment-list (list 10 (string-ascii 64)))
  (tanks-list (list 10 (string-ascii 64)))
  (premium-payment uint)
)
  (let
    (
      (current-id (var-get next-claim-id))
      (policy-start stacks-block-height)
      (policy-end (+ policy-start policy-duration))
      (required-premium (calculate-premium coverage-type coverage-amount))
    )
    (asserts! (is-none (map-get? insurance-policies { policy-id: policy-id })) ERR_CLAIM_EXISTS)
    (asserts! (> (len policy-id) u0) ERR_INVALID_PARAMS)
    (asserts! (<= coverage-type COVERAGE_COMPREHENSIVE) ERR_INVALID_PARAMS)
    (asserts! (>= coverage-type COVERAGE_BASIC) ERR_INVALID_PARAMS)
    (asserts! (> coverage-amount u0) ERR_INVALID_PARAMS)
    (asserts! (>= premium-payment required-premium) ERR_INSUFFICIENT_COVERAGE)
    
    (map-set insurance-policies
      { policy-id: policy-id }
      {
        id: current-id,
        policyholder: tx-sender,
        coverage-type: coverage-type,
        premium-paid: premium-payment,
        coverage-amount: coverage-amount,
        deductible: deductible,
        policy-start: policy-start,
        policy-end: policy-end,
        equipment-covered: equipment-list,
        tanks-covered: tanks-list,
        active: true,
        claims-count: u0,
        last-claim: u0
      }
    )
    
    ;; Add premium to insurance pool
    (var-set insurance-pool (+ (var-get insurance-pool) premium-payment))
    
    (ok current-id)
  )
)

(define-public (submit-claim
  (claim-id (string-ascii 64))
  (policy-id (string-ascii 64))
  (failure-type uint)
  (affected-equipment (string-ascii 64))
  (affected-tanks (list 5 (string-ascii 64)))
  (claim-amount uint)
  (actual-loss uint)
  (incident-date uint)
  (description (string-ascii 512))
  (evidence-hash (string-ascii 64))
)
  (let
    (
      (current-id (var-get next-claim-id))
      (claim-date stacks-block-height)
      (policy (unwrap! (map-get? insurance-policies { policy-id: policy-id }) ERR_NOT_FOUND))
      (current-time stacks-block-height)
    )
    (asserts! (is-none (map-get? insurance-claims { claim-id: claim-id })) ERR_CLAIM_EXISTS)
    (asserts! (is-eq (get policyholder policy) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (get active policy) ERR_INVALID_PARAMS)
    (asserts! (>= current-time (get policy-start policy)) ERR_INVALID_PARAMS)
    (asserts! (<= current-time (get policy-end policy)) ERR_CLAIM_EXPIRED)
    (asserts! (<= failure-type FAILURE_AUTOMATION) ERR_INVALID_PARAMS)
    (asserts! (>= failure-type FAILURE_EQUIPMENT) ERR_INVALID_PARAMS)
    (asserts! (> claim-amount u0) ERR_INVALID_PARAMS)
    (asserts! (<= claim-amount (get coverage-amount policy)) ERR_INSUFFICIENT_COVERAGE)
    
    (map-set insurance-claims
      { claim-id: claim-id }
      {
        id: current-id,
        policy-id: policy-id,
        claimant: tx-sender,
        failure-type: failure-type,
        affected-equipment: affected-equipment,
        affected-tanks: affected-tanks,
        claim-amount: claim-amount,
        actual-loss: actual-loss,
        incident-date: incident-date,
        claim-date: claim-date,
        status: CLAIM_SUBMITTED,
        description: description,
        evidence-hash: evidence-hash,
        assessor: CONTRACT_OWNER, ;; Default to owner, will be reassigned
        assessment-notes: "",
        payout-amount: u0,
        payout-date: u0
      }
    )
    
    ;; Update policy claim count
    (map-set insurance-policies
      { policy-id: policy-id }
      (merge policy {
        claims-count: (+ (get claims-count policy) u1),
        last-claim: claim-date
      })
    )
    
    (var-set next-claim-id (+ current-id u1))
    (var-set total-claims (+ (var-get total-claims) u1))
    (var-set pending-claims (+ (var-get pending-claims) u1))
    
    (ok current-id)
  )
)

(define-public (submit-claim-evidence
  (claim-id (string-ascii 64))
  (evidence-type (string-ascii 32))
  (data-hash (string-ascii 64))
  (source (string-ascii 64))
)
  (let
    (
      (timestamp stacks-block-height)
      (claim (unwrap! (map-get? insurance-claims { claim-id: claim-id }) ERR_NOT_FOUND))
    )
    (asserts! (is-eq (get claimant claim) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (> (len evidence-type) u0) ERR_INVALID_PARAMS)
    (asserts! (> (len data-hash) u0) ERR_INVALID_PARAMS)
    
    (map-set claim-evidence
      { claim-id: claim-id, evidence-type: evidence-type }
      {
        data-hash: data-hash,
        timestamp: timestamp,
        source: source,
        verified: false,
        uploader: tx-sender
      }
    )
    
    (ok true)
  )
)

(define-public (assess-claim
  (claim-id (string-ascii 64))
  (damage-severity uint)
  (repair-cost uint)
  (replacement-cost uint)
  (business-interruption uint)
  (recommended-payout uint)
  (assessment-confidence uint)
  (assessment-notes (string-ascii 512))
)
  (let
    (
      (assessment-date stacks-block-height)
      (claim (unwrap! (map-get? insurance-claims { claim-id: claim-id }) ERR_NOT_FOUND))
      (total-assessed-loss (+ repair-cost replacement-cost business-interruption))
    )
    (asserts! (is-authorized-assessor tx-sender) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq (get status claim) CLAIM_SUBMITTED) (is-eq (get status claim) CLAIM_REVIEWING)) ERR_INVALID_CLAIM_STATUS)
    (asserts! (<= damage-severity u10) ERR_INVALID_PARAMS)
    (asserts! (<= assessment-confidence u100) ERR_INVALID_PARAMS)
    
    (map-set loss-assessments
      { claim-id: claim-id }
      {
        assessor: tx-sender,
        assessment-date: assessment-date,
        damage-severity: damage-severity,
        repair-cost: repair-cost,
        replacement-cost: replacement-cost,
        business-interruption: business-interruption,
        total-assessed-loss: total-assessed-loss,
        recommended-payout: recommended-payout,
        assessment-confidence: assessment-confidence,
        notes: assessment-notes
      }
    )
    
    ;; Update claim status to reviewing
    (map-set insurance-claims
      { claim-id: claim-id }
      (merge claim {
        status: CLAIM_REVIEWING,
        assessor: tx-sender,
        assessment-notes: assessment-notes
      })
    )
    
    (ok true)
  )
)

(define-public (approve-claim
  (claim-id (string-ascii 64))
  (approved-amount uint)
)
  (let
    (
      (claim (unwrap! (map-get? insurance-claims { claim-id: claim-id }) ERR_NOT_FOUND))
      (policy (unwrap! (map-get? insurance-policies { policy-id: (get policy-id claim) }) ERR_NOT_FOUND))
      (net-payout (- approved-amount (get deductible policy)))
    )
    (asserts! (is-authorized-assessor tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status claim) CLAIM_REVIEWING) ERR_INVALID_CLAIM_STATUS)
    (asserts! (<= approved-amount (get coverage-amount policy)) ERR_INSUFFICIENT_COVERAGE)
    (asserts! (> approved-amount (get deductible policy)) ERR_INVALID_PARAMS)
    (asserts! (>= (var-get insurance-pool) net-payout) ERR_INSUFFICIENT_COVERAGE)
    
    ;; Update claim status and payout amount
    (map-set insurance-claims
      { claim-id: claim-id }
      (merge claim {
        status: CLAIM_APPROVED,
        payout-amount: net-payout
      })
    )
    
    (var-set approved-claims (+ (var-get approved-claims) u1))
    (var-set pending-claims (- (var-get pending-claims) u1))
    
    ;; Process automatic payout
    (try! (process-payout claim-id net-payout))
    
    (ok net-payout)
  )
)

(define-public (reject-claim
  (claim-id (string-ascii 64))
  (rejection-reason (string-ascii 256))
)
  (let
    (
      (claim (unwrap! (map-get? insurance-claims { claim-id: claim-id }) ERR_NOT_FOUND))
    )
    (asserts! (is-authorized-assessor tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status claim) CLAIM_REVIEWING) ERR_INVALID_CLAIM_STATUS)
    
    (map-set insurance-claims
      { claim-id: claim-id }
      (merge claim {
        status: CLAIM_REJECTED,
        assessment-notes: rejection-reason
      })
    )
    
    (var-set pending-claims (- (var-get pending-claims) u1))
    
    (ok true)
  )
)

(define-public (process-payout (claim-id (string-ascii 64)) (amount uint))
  (let
    (
      (payout-date stacks-block-height)
      (claim (unwrap! (map-get? insurance-claims { claim-id: claim-id }) ERR_NOT_FOUND))
      (transaction-id (sha256 (concat (concat (unwrap-panic (to-consensus-buff? claim-id)) (unwrap-panic (to-consensus-buff? amount))) (unwrap-panic (to-consensus-buff? payout-date)))))
    )
    (asserts! (is-authorized-assessor tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status claim) CLAIM_APPROVED) ERR_INVALID_CLAIM_STATUS)
    (asserts! (>= (var-get insurance-pool) amount) ERR_INSUFFICIENT_COVERAGE)
    
    ;; Deduct from insurance pool
    (var-set insurance-pool (- (var-get insurance-pool) amount))
    (var-set total-payouts (+ (var-get total-payouts) amount))
    
    ;; Record payout
    (map-set payout-history
      { claim-id: claim-id }
      {
        amount: amount,
        payout-date: payout-date,
        transaction-id: "auto-generated",
        method: "automatic",
        recipient: (get claimant claim),
        processed-by: tx-sender
      }
    )
    
    ;; Update claim status
    (map-set insurance-claims
      { claim-id: claim-id }
      (merge claim {
        status: CLAIM_PAID,
        payout-date: payout-date
      })
    )
    
    (ok true)
  )
)

(define-public (authorize-assessor
  (assessor principal)
  (specialization (string-ascii 64))
  (license-number (string-ascii 32))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-assessors
      { assessor: assessor }
      {
        authorized: true,
        specialization: specialization,
        license-number: license-number,
        assessment-count: u0,
        approval-rating: u100
      }
    )
    (ok true)
  )
)

;; read only functions

(define-read-only (get-policy-info (policy-id (string-ascii 64)))
  (map-get? insurance-policies { policy-id: policy-id })
)

(define-read-only (get-claim-info (claim-id (string-ascii 64)))
  (map-get? insurance-claims { claim-id: claim-id })
)

(define-read-only (get-claim-evidence (claim-id (string-ascii 64)) (evidence-type (string-ascii 32)))
  (map-get? claim-evidence { claim-id: claim-id, evidence-type: evidence-type })
)

(define-read-only (get-loss-assessment (claim-id (string-ascii 64)))
  (map-get? loss-assessments { claim-id: claim-id })
)

(define-read-only (get-payout-history (claim-id (string-ascii 64)))
  (map-get? payout-history { claim-id: claim-id })
)

(define-read-only (get-system-statistics)
  {
    total-claims: (var-get total-claims),
    approved-claims: (var-get approved-claims),
    total-payouts: (var-get total-payouts),
    pending-claims: (var-get pending-claims),
    insurance-pool: (var-get insurance-pool),
    next-claim-id: (var-get next-claim-id)
  }
)

(define-read-only (is-authorized-assessor (assessor principal))
  (match (map-get? authorized-assessors { assessor: assessor })
    auth-data (get authorized auth-data)
    (is-eq assessor CONTRACT_OWNER)
  )
)

(define-read-only (get-assessor-info (assessor principal))
  (map-get? authorized-assessors { assessor: assessor })
)

(define-read-only (calculate-premium (coverage-type uint) (coverage-amount uint))
  (let
    (
      (base-rate (if (is-eq coverage-type COVERAGE_BASIC)
                   u10
                   (if (is-eq coverage-type COVERAGE_PREMIUM)
                     u15
                     u20)))
    )
    (/ (* coverage-amount base-rate) u1000) ;; Rate per thousand
  )
)

(define-read-only (policy-is-valid (policy-id (string-ascii 64)))
  (match (map-get? insurance-policies { policy-id: policy-id })
    policy
      (let
        (
          (current-time stacks-block-height)
        )
        (and
          (get active policy)
          (>= current-time (get policy-start policy))
          (<= current-time (get policy-end policy))
        )
      )
    false
  )
)

;; private functions

(define-private (sha256-to-hex (hash (buff 32)))
  ;; This is a simplified version - in reality would need proper hex conversion
  (sha256 hash)
)

(define-private (calculate-claim-risk-score (claim-id (string-ascii 64)))
  (match (map-get? insurance-claims { claim-id: claim-id })
    claim
      (let
        (
          (failure-score (get failure-type claim))
          (amount-score (/ (get claim-amount claim) u10000))
          (time-score (if (< (- stacks-block-height (get incident-date claim)) u86400) u10 u0))
        )
        (+ failure-score amount-score time-score)
      )
    u0
  )
)

(define-private (validate-claim-eligibility (policy-id (string-ascii 64)) (failure-type uint) (equipment-id (string-ascii 64)))
  (match (map-get? insurance-policies { policy-id: policy-id })
    policy
      (let
        (
          (equipment-covered (is-some (index-of (get equipment-covered policy) equipment-id)))
          (coverage-adequate (>= (get coverage-type policy) (get-minimum-coverage-for-failure failure-type)))
        )
        (and equipment-covered coverage-adequate (get active policy))
      )
    false
  )
)

(define-private (get-minimum-coverage-for-failure (failure-type uint))
  (if (is-eq failure-type FAILURE_EQUIPMENT)
    COVERAGE_BASIC
    (if (is-eq failure-type FAILURE_FISH_HEALTH)
      COVERAGE_PREMIUM
      COVERAGE_COMPREHENSIVE
    )
  )
)

