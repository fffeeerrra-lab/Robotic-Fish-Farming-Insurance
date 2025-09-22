;; fish-health-monitor
;; Automated fish health assessment using computer vision and behavioral analysis

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u2001))
(define-constant ERR_NOT_FOUND (err u2002))
(define-constant ERR_INVALID_PARAMS (err u2003))
(define-constant ERR_TANK_EXISTS (err u2004))
(define-constant ERR_INVALID_HEALTH_SCORE (err u2005))
(define-constant ERR_INVALID_BEHAVIOR (err u2006))

;; Health status constants
(define-constant HEALTH_EXCELLENT u5)
(define-constant HEALTH_GOOD u4)
(define-constant HEALTH_FAIR u3)
(define-constant HEALTH_POOR u2)
(define-constant HEALTH_CRITICAL u1)

;; Behavior constants
(define-constant BEHAVIOR_NORMAL u1)
(define-constant BEHAVIOR_ABNORMAL u2)
(define-constant BEHAVIOR_STRESSED u3)
(define-constant BEHAVIOR_AGGRESSIVE u4)
(define-constant BEHAVIOR_LETHARGIC u5)

;; data vars
(define-data-var total-tanks uint u0)
(define-data-var total-fish-monitored uint u0)
(define-data-var critical-health-alerts uint u0)
(define-data-var disease-outbreaks uint u0)
(define-data-var mortality-events uint u0)
(define-data-var next-tank-id uint u1)

;; data maps
(define-map fish-tanks
  { tank-id: (string-ascii 64) }
  {
    id: uint,
    name: (string-ascii 128),
    location: { x: int, y: int, z: int },
    capacity: uint,
    current-fish-count: uint,
    species: (string-ascii 64),
    water-temp: uint,
    ph-level: uint,
    oxygen-level: uint,
    salinity: uint,
    owner: principal,
    installation-date: uint,
    last-inspection: uint,
    health-status: uint
  }
)

(define-map fish-health-records
  { tank-id: (string-ascii 64), timestamp: uint }
  {
    health-score: uint,
    fish-count: uint,
    average-size: uint,
    growth-rate: int,
    mortality-count: uint,
    disease-indicators: uint,
    behavior-score: uint,
    feeding-response: uint,
    water-quality-impact: uint,
    ai-assessment: (string-ascii 256),
    inspector: principal
  }
)

(define-map behavioral-analysis
  { tank-id: (string-ascii 64), behavior-type: (string-ascii 32) }
  {
    frequency: uint,
    intensity: uint,
    duration: uint,
    affected-fish: uint,
    timestamp: uint,
    anomaly-level: uint,
    correlation-factors: (list 5 (string-ascii 32))
  }
)

(define-map disease-tracking
  { tank-id: (string-ascii 64), disease-type: (string-ascii 64) }
  {
    outbreak-start: uint,
    affected-fish: uint,
    severity: uint,
    treatment-applied: (string-ascii 128),
    recovery-rate: uint,
    quarantine-status: bool,
    containment-measures: (list 5 (string-ascii 64))
  }
)

(define-map growth-tracking
  { tank-id: (string-ascii 64), measurement-date: uint }
  {
    average-length: uint,
    average-weight: uint,
    growth-rate: int,
    feed-conversion-ratio: uint,
    size-distribution: { small: uint, medium: uint, large: uint },
    uniformity-index: uint
  }
)

(define-map authorized-inspectors
  { inspector: principal }
  { authorized: bool, expertise: (string-ascii 64), certifications: (list 3 (string-ascii 32)) }
)

;; public functions

(define-public (register-fish-tank
  (tank-id (string-ascii 64))
  (name (string-ascii 128))
  (location-x int) (location-y int) (location-z int)
  (capacity uint)
  (species (string-ascii 64))
  (initial-fish-count uint)
)
  (let
    (
      (current-id (var-get next-tank-id))
      (installation-time stacks-block-height)
    )
    (asserts! (is-authorized-inspector tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? fish-tanks { tank-id: tank-id })) ERR_TANK_EXISTS)
    (asserts! (> (len tank-id) u0) ERR_INVALID_PARAMS)
    (asserts! (> capacity u0) ERR_INVALID_PARAMS)
    (asserts! (<= initial-fish-count capacity) ERR_INVALID_PARAMS)
    
    (map-set fish-tanks
      { tank-id: tank-id }
      {
        id: current-id,
        name: name,
        location: { x: location-x, y: location-y, z: location-z },
        capacity: capacity,
        current-fish-count: initial-fish-count,
        species: species,
        water-temp: u24, ;; Default 24 degrees Celsius
        ph-level: u72, ;; Default pH 7.2
        oxygen-level: u8, ;; Default 8 mg/L
        salinity: u35, ;; Default 35 ppt for marine
        owner: tx-sender,
        installation-date: installation-time,
        last-inspection: installation-time,
        health-status: HEALTH_GOOD
      }
    )
    
    (var-set next-tank-id (+ current-id u1))
    (var-set total-tanks (+ (var-get total-tanks) u1))
    (var-set total-fish-monitored (+ (var-get total-fish-monitored) initial-fish-count))
    
    (ok current-id)
  )
)

(define-public (record-health-assessment
  (tank-id (string-ascii 64))
  (health-score uint)
  (fish-count uint)
  (average-size uint)
  (growth-rate int)
  (mortality-count uint)
  (disease-indicators uint)
  (behavior-score uint)
  (feeding-response uint)
  (ai-assessment (string-ascii 256))
)
  (let
    (
      (timestamp stacks-block-height)
      (tank-info (unwrap! (map-get? fish-tanks { tank-id: tank-id }) ERR_NOT_FOUND))
      (water-quality-impact (calculate-water-quality-impact tank-info))
    )
    (asserts! (is-authorized-inspector tx-sender) ERR_UNAUTHORIZED)
    (asserts! (<= health-score u100) ERR_INVALID_HEALTH_SCORE)
    (asserts! (<= behavior-score u100) ERR_INVALID_HEALTH_SCORE)
    (asserts! (<= feeding-response u100) ERR_INVALID_HEALTH_SCORE)
    (asserts! (<= disease-indicators u100) ERR_INVALID_HEALTH_SCORE)
    
    (map-set fish-health-records
      { tank-id: tank-id, timestamp: timestamp }
      {
        health-score: health-score,
        fish-count: fish-count,
        average-size: average-size,
        growth-rate: growth-rate,
        mortality-count: mortality-count,
        disease-indicators: disease-indicators,
        behavior-score: behavior-score,
        feeding-response: feeding-response,
        water-quality-impact: water-quality-impact,
        ai-assessment: ai-assessment,
        inspector: tx-sender
      }
    )
    
    ;; Update tank information
    (map-set fish-tanks
      { tank-id: tank-id }
      (merge tank-info {
        current-fish-count: fish-count,
        last-inspection: timestamp,
        health-status: (convert-score-to-health-level health-score)
      })
    )
    
    ;; Track mortality events
    (if (> mortality-count u0)
      (var-set mortality-events (+ (var-get mortality-events) u1))
      true
    )
    
    ;; Trigger critical health alert
    (if (< health-score u40)
      (begin
        (var-set critical-health-alerts (+ (var-get critical-health-alerts) u1))
        (trigger-health-alert tank-id health-score)
      )
      true
    )
    
    (ok true)
  )
)

(define-public (record-behavioral-analysis
  (tank-id (string-ascii 64))
  (behavior-type (string-ascii 32))
  (frequency uint)
  (intensity uint)
  (duration uint)
  (affected-fish uint)
  (anomaly-level uint)
  (correlation-factors (list 5 (string-ascii 32)))
)
  (let
    (
      (timestamp stacks-block-height)
    )
    (asserts! (is-authorized-inspector tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? fish-tanks { tank-id: tank-id })) ERR_NOT_FOUND)
    (asserts! (<= intensity u10) ERR_INVALID_PARAMS)
    (asserts! (<= anomaly-level u100) ERR_INVALID_PARAMS)
    
    (map-set behavioral-analysis
      { tank-id: tank-id, behavior-type: behavior-type }
      {
        frequency: frequency,
        intensity: intensity,
        duration: duration,
        affected-fish: affected-fish,
        timestamp: timestamp,
        anomaly-level: anomaly-level,
        correlation-factors: correlation-factors
      }
    )
    
    ;; Alert on high anomaly levels
    (if (> anomaly-level u70)
      (trigger-behavior-alert tank-id behavior-type anomaly-level)
      true
    )
    
    (ok true)
  )
)

(define-public (record-disease-outbreak
  (tank-id (string-ascii 64))
  (disease-type (string-ascii 64))
  (affected-fish uint)
  (severity uint)
  (treatment-applied (string-ascii 128))
  (containment-measures (list 5 (string-ascii 64)))
)
  (let
    (
      (outbreak-start stacks-block-height)
      (quarantine-needed (> severity u7))
    )
    (asserts! (is-authorized-inspector tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? fish-tanks { tank-id: tank-id })) ERR_NOT_FOUND)
    (asserts! (<= severity u10) ERR_INVALID_PARAMS)
    (asserts! (> affected-fish u0) ERR_INVALID_PARAMS)
    
    (map-set disease-tracking
      { tank-id: tank-id, disease-type: disease-type }
      {
        outbreak-start: outbreak-start,
        affected-fish: affected-fish,
        severity: severity,
        treatment-applied: treatment-applied,
        recovery-rate: u0,
        quarantine-status: quarantine-needed,
        containment-measures: containment-measures
      }
    )
    
    (var-set disease-outbreaks (+ (var-get disease-outbreaks) u1))
    
    ;; Update tank health status based on severity
    (if (> severity u5)
      (try! (update-tank-health-status tank-id HEALTH_CRITICAL))
      (try! (update-tank-health-status tank-id HEALTH_POOR))
    )
    
    (ok quarantine-needed)
  )
)

(define-public (update-growth-metrics
  (tank-id (string-ascii 64))
  (average-length uint)
  (average-weight uint)
  (growth-rate int)
  (feed-conversion-ratio uint)
  (small-fish uint) (medium-fish uint) (large-fish uint)
  (uniformity-index uint)
)
  (let
    (
      (measurement-date stacks-block-height)
    )
    (asserts! (is-authorized-inspector tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? fish-tanks { tank-id: tank-id })) ERR_NOT_FOUND)
    (asserts! (<= uniformity-index u100) ERR_INVALID_PARAMS)
    
    (map-set growth-tracking
      { tank-id: tank-id, measurement-date: measurement-date }
      {
        average-length: average-length,
        average-weight: average-weight,
        growth-rate: growth-rate,
        feed-conversion-ratio: feed-conversion-ratio,
        size-distribution: { small: small-fish, medium: medium-fish, large: large-fish },
        uniformity-index: uniformity-index
      }
    )
    
    ;; Alert on poor growth performance
    (if (< growth-rate -10) ;; Negative growth rate threshold
      (trigger-growth-alert tank-id growth-rate)
      true
    )
    
    (ok true)
  )
)

(define-public (authorize-inspector
  (inspector principal)
  (expertise (string-ascii 64))
  (certifications (list 3 (string-ascii 32)))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-inspectors
      { inspector: inspector }
      { authorized: true, expertise: expertise, certifications: certifications }
    )
    (ok true)
  )
)

(define-public (revoke-inspector-authorization (inspector principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-delete authorized-inspectors { inspector: inspector })
    (ok true)
  )
)

;; read only functions

(define-read-only (get-tank-info (tank-id (string-ascii 64)))
  (map-get? fish-tanks { tank-id: tank-id })
)

(define-read-only (get-health-record (tank-id (string-ascii 64)) (timestamp uint))
  (map-get? fish-health-records { tank-id: tank-id, timestamp: timestamp })
)

(define-read-only (get-behavioral-data (tank-id (string-ascii 64)) (behavior-type (string-ascii 32)))
  (map-get? behavioral-analysis { tank-id: tank-id, behavior-type: behavior-type })
)

(define-read-only (get-disease-info (tank-id (string-ascii 64)) (disease-type (string-ascii 64)))
  (map-get? disease-tracking { tank-id: tank-id, disease-type: disease-type })
)

(define-read-only (get-growth-data (tank-id (string-ascii 64)) (measurement-date uint))
  (map-get? growth-tracking { tank-id: tank-id, measurement-date: measurement-date })
)

(define-read-only (get-system-statistics)
  {
    total-tanks: (var-get total-tanks),
    total-fish-monitored: (var-get total-fish-monitored),
    critical-health-alerts: (var-get critical-health-alerts),
    disease-outbreaks: (var-get disease-outbreaks),
    mortality-events: (var-get mortality-events),
    next-tank-id: (var-get next-tank-id)
  }
)

(define-read-only (is-authorized-inspector (inspector principal))
  (match (map-get? authorized-inspectors { inspector: inspector })
    auth-data (get authorized auth-data)
    (is-eq inspector CONTRACT_OWNER)
  )
)

(define-read-only (get-inspector-info (inspector principal))
  (map-get? authorized-inspectors { inspector: inspector })
)

(define-read-only (calculate-tank-health-score (tank-id (string-ascii 64)))
  (match (map-get? fish-tanks { tank-id: tank-id })
    tank-info
      (let
        (
          (base-score u70)
          (temp-score (if (and (>= (get water-temp tank-info) u22) (<= (get water-temp tank-info) u28)) u10 u0))
          (ph-score (if (and (>= (get ph-level tank-info) u68) (<= (get ph-level tank-info) u78)) u10 u0))
          (oxygen-score (if (>= (get oxygen-level tank-info) u6) u10 u0))
        )
        (+ base-score temp-score ph-score oxygen-score)
      )
    u0
  )
)

;; private functions

(define-private (convert-score-to-health-level (score uint))
  (if (>= score u80)
    HEALTH_EXCELLENT
    (if (>= score u60)
      HEALTH_GOOD
      (if (>= score u40)
        HEALTH_FAIR
        (if (>= score u20)
          HEALTH_POOR
          HEALTH_CRITICAL
        )
      )
    )
  )
)

(define-private (calculate-water-quality-impact (tank-info { id: uint, name: (string-ascii 128), location: { x: int, y: int, z: int }, capacity: uint, current-fish-count: uint, species: (string-ascii 64), water-temp: uint, ph-level: uint, oxygen-level: uint, salinity: uint, owner: principal, installation-date: uint, last-inspection: uint, health-status: uint }))
  (let
    (
      (temp-impact (if (and (>= (get water-temp tank-info) u20) (<= (get water-temp tank-info) u30)) u0 u20))
      (ph-impact (if (and (>= (get ph-level tank-info) u65) (<= (get ph-level tank-info) u80)) u0 u25))
      (oxygen-impact (if (>= (get oxygen-level tank-info) u5) u0 u30))
    )
    (+ temp-impact ph-impact oxygen-impact)
  )
)

(define-private (trigger-health-alert (tank-id (string-ascii 64)) (health-score uint))
  ;; This would typically trigger external notifications
  true
)

(define-private (trigger-behavior-alert (tank-id (string-ascii 64)) (behavior-type (string-ascii 32)) (anomaly-level uint))
  ;; This would typically trigger external notifications
  true
)

(define-private (trigger-growth-alert (tank-id (string-ascii 64)) (growth-rate int))
  ;; This would typically trigger external notifications
  true
)

(define-private (update-tank-health-status (tank-id (string-ascii 64)) (new-status uint))
  (match (map-get? fish-tanks { tank-id: tank-id })
    tank-info
      (begin
        (map-set fish-tanks
          { tank-id: tank-id }
          (merge tank-info { health-status: new-status })
        )
        (ok true)
      )
    ERR_NOT_FOUND
  )
)

