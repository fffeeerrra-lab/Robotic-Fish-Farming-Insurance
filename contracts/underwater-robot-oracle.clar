;; underwater-robot-oracle
;; Real-time monitoring of robotic fish farming equipment and underwater navigation systems

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u1001))
(define-constant ERR_NOT_FOUND (err u1002))
(define-constant ERR_INVALID_PARAMS (err u1003))
(define-constant ERR_EQUIPMENT_EXISTS (err u1004))
(define-constant ERR_INVALID_STATUS (err u1005))

;; Equipment status constants
(define-constant STATUS_ACTIVE u1)
(define-constant STATUS_INACTIVE u2)
(define-constant STATUS_MAINTENANCE u3)
(define-constant STATUS_ERROR u4)
(define-constant STATUS_CRITICAL u5)

;; data vars
(define-data-var next-equipment-id uint u1)
(define-data-var total-equipment uint u0)
(define-data-var active-equipment uint u0)
(define-data-var critical-alerts uint u0)
(define-data-var maintenance-count uint u0)

;; data maps
(define-map equipment-registry
  { equipment-id: (string-ascii 64) }
  {
    id: uint,
    name: (string-ascii 128),
    equipment-type: (string-ascii 64),
    status: uint,
    location: { x: int, y: int, z: int },
    owner: principal,
    installation-date: uint,
    last-maintenance: uint,
    next-maintenance: uint,
    operating-hours: uint,
    efficiency-rating: uint,
    warranty-expires: uint
  }
)

(define-map equipment-metrics
  { equipment-id: (string-ascii 64), metric-type: (string-ascii 32) }
  {
    value: uint,
    timestamp: uint,
    threshold-min: uint,
    threshold-max: uint,
    alert-triggered: bool
  }
)

(define-map navigation-data
  { equipment-id: (string-ascii 64) }
  {
    current-position: { x: int, y: int, z: int },
    target-position: { x: int, y: int, z: int },
    velocity: uint,
    heading: uint,
    depth: uint,
    battery-level: uint,
    gps-signal-strength: uint,
    collision-sensors: bool,
    autonomous-mode: bool,
    last-navigation-update: uint
  }
)

(define-map environmental-readings
  { location: { x: int, y: int, z: int }, reading-type: (string-ascii 32) }
  {
    value: uint,
    timestamp: uint,
    equipment-source: (string-ascii 64),
    quality-index: uint,
    anomaly-detected: bool
  }
)

(define-map authorized-operators
  { operator: principal }
  { authorized: bool, role: (string-ascii 32), permissions: uint }
)

;; public functions

(define-public (register-equipment 
  (equipment-id (string-ascii 64))
  (name (string-ascii 128))
  (equipment-type (string-ascii 64))
  (location-x int)
  (location-y int)
  (location-z int)
  (warranty-period uint)
)
  (let 
    (
      (current-id (var-get next-equipment-id))
      (installation-time stacks-block-height)
    )
    (asserts! (is-authorized-operator tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? equipment-registry { equipment-id: equipment-id })) ERR_EQUIPMENT_EXISTS)
    (asserts! (> (len equipment-id) u0) ERR_INVALID_PARAMS)
    (asserts! (> (len name) u0) ERR_INVALID_PARAMS)
    
    (map-set equipment-registry
      { equipment-id: equipment-id }
      {
        id: current-id,
        name: name,
        equipment-type: equipment-type,
        status: STATUS_ACTIVE,
        location: { x: location-x, y: location-y, z: location-z },
        owner: tx-sender,
        installation-date: installation-time,
        last-maintenance: installation-time,
        next-maintenance: (+ installation-time u2592000), ;; 30 days
        operating-hours: u0,
        efficiency-rating: u100,
        warranty-expires: (+ installation-time warranty-period)
      }
    )
    
    (var-set next-equipment-id (+ current-id u1))
    (var-set total-equipment (+ (var-get total-equipment) u1))
    (var-set active-equipment (+ (var-get active-equipment) u1))
    
    (ok current-id)
  )
)

(define-public (update-equipment-status
  (equipment-id (string-ascii 64))
  (new-status uint)
)
  (let
    (
      (equipment (unwrap! (map-get? equipment-registry { equipment-id: equipment-id }) ERR_NOT_FOUND))
      (old-status (get status equipment))
    )
    (asserts! (is-authorized-operator tx-sender) ERR_UNAUTHORIZED)
    (asserts! (<= new-status STATUS_CRITICAL) ERR_INVALID_STATUS)
    (asserts! (>= new-status STATUS_ACTIVE) ERR_INVALID_STATUS)
    
    (map-set equipment-registry
      { equipment-id: equipment-id }
      (merge equipment { status: new-status })
    )
    
    ;; Update counters based on status changes
    (if (and (is-eq old-status STATUS_ACTIVE) (not (is-eq new-status STATUS_ACTIVE)))
      (var-set active-equipment (- (var-get active-equipment) u1))
      (if (and (not (is-eq old-status STATUS_ACTIVE)) (is-eq new-status STATUS_ACTIVE))
        (var-set active-equipment (+ (var-get active-equipment) u1))
        true
      )
    )
    
    (if (is-eq new-status STATUS_CRITICAL)
      (var-set critical-alerts (+ (var-get critical-alerts) u1))
      true
    )
    
    (if (is-eq new-status STATUS_MAINTENANCE)
      (var-set maintenance-count (+ (var-get maintenance-count) u1))
      true
    )
    
    (ok true)
  )
)

(define-public (record-equipment-metric
  (equipment-id (string-ascii 64))
  (metric-type (string-ascii 32))
  (value uint)
  (threshold-min uint)
  (threshold-max uint)
)
  (let
    (
      (timestamp stacks-block-height)
      (alert-triggered (or (< value threshold-min) (> value threshold-max)))
    )
    (asserts! (is-authorized-operator tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? equipment-registry { equipment-id: equipment-id })) ERR_NOT_FOUND)
    
    (map-set equipment-metrics
      { equipment-id: equipment-id, metric-type: metric-type }
      {
        value: value,
        timestamp: timestamp,
        threshold-min: threshold-min,
        threshold-max: threshold-max,
        alert-triggered: alert-triggered
      }
    )
    
    (if alert-triggered
      (try! (update-equipment-status equipment-id STATUS_CRITICAL))
      true
    )
    
    (ok alert-triggered)
  )
)

(define-public (update-navigation-data
  (equipment-id (string-ascii 64))
  (current-x int) (current-y int) (current-z int)
  (target-x int) (target-y int) (target-z int)
  (velocity uint) (heading uint) (depth uint)
  (battery-level uint) (gps-signal uint)
  (collision-sensors bool) (autonomous-mode bool)
)
  (let
    (
      (timestamp stacks-block-height)
    )
    (asserts! (is-authorized-operator tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? equipment-registry { equipment-id: equipment-id })) ERR_NOT_FOUND)
    (asserts! (<= battery-level u100) ERR_INVALID_PARAMS)
    (asserts! (<= gps-signal u100) ERR_INVALID_PARAMS)
    (asserts! (<= heading u360) ERR_INVALID_PARAMS)
    
    (map-set navigation-data
      { equipment-id: equipment-id }
      {
        current-position: { x: current-x, y: current-y, z: current-z },
        target-position: { x: target-x, y: target-y, z: target-z },
        velocity: velocity,
        heading: heading,
        depth: depth,
        battery-level: battery-level,
        gps-signal-strength: gps-signal,
        collision-sensors: collision-sensors,
        autonomous-mode: autonomous-mode,
        last-navigation-update: timestamp
      }
    )
    
    ;; Trigger alerts for critical navigation issues
    (if (< battery-level u20)
      (try! (record-equipment-metric equipment-id "battery" battery-level u20 u100))
      true
    )
    
    (if (< gps-signal u30)
      (try! (record-equipment-metric equipment-id "gps-signal" gps-signal u30 u100))
      true
    )
    
    (ok true)
  )
)

(define-public (record-environmental-reading
  (location-x int) (location-y int) (location-z int)
  (reading-type (string-ascii 32))
  (value uint)
  (equipment-source (string-ascii 64))
  (quality-index uint)
)
  (let
    (
      (timestamp stacks-block-height)
      (location { x: location-x, y: location-y, z: location-z })
      (anomaly (< quality-index u70))
    )
    (asserts! (is-authorized-operator tx-sender) ERR_UNAUTHORIZED)
    (asserts! (<= quality-index u100) ERR_INVALID_PARAMS)
    (asserts! (> (len reading-type) u0) ERR_INVALID_PARAMS)
    
    (map-set environmental-readings
      { location: location, reading-type: reading-type }
      {
        value: value,
        timestamp: timestamp,
        equipment-source: equipment-source,
        quality-index: quality-index,
        anomaly-detected: anomaly
      }
    )
    
    (ok anomaly)
  )
)

(define-public (authorize-operator
  (operator principal)
  (role (string-ascii 32))
  (permissions uint)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-operators
      { operator: operator }
      { authorized: true, role: role, permissions: permissions }
    )
    (ok true)
  )
)

(define-public (revoke-operator-authorization (operator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-delete authorized-operators { operator: operator })
    (ok true)
  )
)

;; read only functions

(define-read-only (get-equipment-info (equipment-id (string-ascii 64)))
  (map-get? equipment-registry { equipment-id: equipment-id })
)

(define-read-only (get-equipment-metrics (equipment-id (string-ascii 64)) (metric-type (string-ascii 32)))
  (map-get? equipment-metrics { equipment-id: equipment-id, metric-type: metric-type })
)

(define-read-only (get-navigation-data (equipment-id (string-ascii 64)))
  (map-get? navigation-data { equipment-id: equipment-id })
)

(define-read-only (get-environmental-reading (location-x int) (location-y int) (location-z int) (reading-type (string-ascii 32)))
  (map-get? environmental-readings { location: { x: location-x, y: location-y, z: location-z }, reading-type: reading-type })
)

(define-read-only (get-system-stats)
  {
    total-equipment: (var-get total-equipment),
    active-equipment: (var-get active-equipment),
    critical-alerts: (var-get critical-alerts),
    maintenance-count: (var-get maintenance-count),
    next-equipment-id: (var-get next-equipment-id)
  }
)

(define-read-only (is-authorized-operator (operator principal))
  (match (map-get? authorized-operators { operator: operator })
    auth-data (get authorized auth-data)
    (is-eq operator CONTRACT_OWNER)
  )
)

(define-read-only (get-operator-info (operator principal))
  (map-get? authorized-operators { operator: operator })
)

(define-read-only (equipment-needs-maintenance (equipment-id (string-ascii 64)))
  (match (map-get? equipment-registry { equipment-id: equipment-id })
    equipment
      (let
        (
          (current-time stacks-block-height)
          (next-maintenance (get next-maintenance equipment))
        )
        (>= current-time next-maintenance)
      )
    false
  )
)

(define-read-only (get-critical-equipment)
  (var-get critical-alerts)
)

;; private functions

(define-private (calculate-distance (pos1 { x: int, y: int, z: int }) (pos2 { x: int, y: int, z: int }))
  (let
    (
      (dx (- (get x pos2) (get x pos1)))
      (dy (- (get y pos2) (get y pos1)))
      (dz (- (get z pos2) (get z pos1)))
    )
    (+ (* dx dx) (* dy dy) (* dz dz))
  )
)

(define-private (is-equipment-critical (equipment-id (string-ascii 64)))
  (match (map-get? equipment-registry { equipment-id: equipment-id })
    equipment (is-eq (get status equipment) STATUS_CRITICAL)
    false
  )
)

