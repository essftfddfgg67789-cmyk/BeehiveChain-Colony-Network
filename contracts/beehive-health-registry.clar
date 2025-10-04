;; beehive-health-registry
;; Track beehive locations, colony health status, and honey production across beekeeping community

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_HIVE_NOT_FOUND (err u101))
(define-constant ERR_INVALID_HEALTH_SCORE (err u102))
(define-constant ERR_INVALID_LOCATION (err u103))
(define-constant ERR_HIVE_ALREADY_EXISTS (err u104))
(define-constant ERR_INVALID_PRODUCTION (err u105))

;; data maps and vars
(define-map hive-registry
  { hive-id: uint }
  {
    owner: principal,
    latitude: int,
    longitude: int,
    registration-block: uint,
    active: bool
  }
)

(define-map hive-health
  { hive-id: uint }
  {
    health-score: uint,
    colony-size: uint,
    last-inspection: uint,
    inspector: principal,
    disease-status: (string-ascii 50),
    treatment-applied: bool,
    notes: (string-ascii 200)
  }
)

(define-map hive-production
  { hive-id: uint, season: uint }
  {
    honey-production: uint,
    wax-production: uint,
    propolis-production: uint,
    pollen-collection: uint,
    recorded-by: principal,
    recorded-at: uint
  }
)

(define-map owner-hives
  { owner: principal }
  { hive-count: uint, hive-ids: (list 100 uint) }
)

(define-data-var hive-counter uint u0)
(define-data-var total-registered-hives uint u0)
(define-data-var contract-active bool true)

;; private functions
(define-private (is-valid-health-score (score uint))
  (and (>= score u0) (<= score u100))
)

(define-private (is-valid-location (lat int) (lng int))
  (and 
    (and (>= lat -90000000) (<= lat 90000000))
    (and (>= lng -180000000) (<= lng 180000000))
  )
)

(define-private (update-owner-hives (owner principal) (hive-id uint))
  (let (
    (current-data (default-to { hive-count: u0, hive-ids: (list) } 
                               (map-get? owner-hives { owner: owner })))
    (new-count (+ (get hive-count current-data) u1))
    (new-list (unwrap! (as-max-len? (append (get hive-ids current-data) hive-id) u100) false))
  )
    (map-set owner-hives { owner: owner } 
             { hive-count: new-count, hive-ids: new-list })
    true
  )
)

(define-private (calculate-average-health (hive-ids (list 100 uint)))
  ;; Simplified calculation - return default health score
  u75
)

(define-private (get-hive-health-score (hive-id uint))
  (match (map-get? hive-health { hive-id: hive-id })
    health-data (some (get health-score health-data))
    none
  )
)

;; public functions
(define-public (register-hive (latitude int) (longitude int))
  (let (
    (new-hive-id (+ (var-get hive-counter) u1))
    (owner tx-sender)
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-valid-location latitude longitude) ERR_INVALID_LOCATION)
    (asserts! (is-none (map-get? hive-registry { hive-id: new-hive-id })) ERR_HIVE_ALREADY_EXISTS)
    
    ;; Register the hive
    (map-set hive-registry { hive-id: new-hive-id }
             {
               owner: owner,
               latitude: latitude,
               longitude: longitude,
               registration-block: stacks-block-height,
               active: true
             })
    
    ;; Update counters and owner tracking
    (var-set hive-counter new-hive-id)
    (var-set total-registered-hives (+ (var-get total-registered-hives) u1))
    (unwrap! (update-owner-hives owner new-hive-id) ERR_UNAUTHORIZED)
    
    (print { 
      event: "hive-registered", 
      hive-id: new-hive-id, 
      owner: owner, 
      latitude: latitude, 
      longitude: longitude 
    })
    (ok new-hive-id)
  )
)

(define-public (update-health-status (hive-id uint) (health-score uint) (colony-size uint) (disease-status (string-ascii 50)) (treatment-applied bool) (notes (string-ascii 200)))
  (let (
    (hive-data (unwrap! (map-get? hive-registry { hive-id: hive-id }) ERR_HIVE_NOT_FOUND))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-valid-health-score health-score) ERR_INVALID_HEALTH_SCORE)
    (asserts! (or (is-eq tx-sender (get owner hive-data)) (is-eq tx-sender CONTRACT_OWNER)) ERR_UNAUTHORIZED)
    (asserts! (get active hive-data) ERR_HIVE_NOT_FOUND)
    
    (map-set hive-health { hive-id: hive-id }
             {
               health-score: health-score,
               colony-size: colony-size,
               last-inspection: stacks-block-height,
               inspector: tx-sender,
               disease-status: disease-status,
               treatment-applied: treatment-applied,
               notes: notes
             })
    
    (print { 
      event: "health-updated", 
      hive-id: hive-id, 
      health-score: health-score, 
      inspector: tx-sender 
    })
    (ok true)
  )
)

(define-public (record-production (hive-id uint) (season uint) (honey-production uint) (wax-production uint) (propolis-production uint) (pollen-collection uint))
  (let (
    (hive-data (unwrap! (map-get? hive-registry { hive-id: hive-id }) ERR_HIVE_NOT_FOUND))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq tx-sender (get owner hive-data)) (is-eq tx-sender CONTRACT_OWNER)) ERR_UNAUTHORIZED)
    (asserts! (get active hive-data) ERR_HIVE_NOT_FOUND)
    (asserts! (> season u0) ERR_INVALID_PRODUCTION)
    
    (map-set hive-production { hive-id: hive-id, season: season }
             {
               honey-production: honey-production,
               wax-production: wax-production,
               propolis-production: propolis-production,
               pollen-collection: pollen-collection,
               recorded-by: tx-sender,
               recorded-at: stacks-block-height
             })
    
    (print { 
      event: "production-recorded", 
      hive-id: hive-id, 
      season: season, 
      honey-production: honey-production 
    })
    (ok true)
  )
)

(define-public (deactivate-hive (hive-id uint))
  (let (
    (hive-data (unwrap! (map-get? hive-registry { hive-id: hive-id }) ERR_HIVE_NOT_FOUND))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq tx-sender (get owner hive-data)) (is-eq tx-sender CONTRACT_OWNER)) ERR_UNAUTHORIZED)
    
    (map-set hive-registry { hive-id: hive-id }
             (merge hive-data { active: false }))
    
    (var-set total-registered-hives (- (var-get total-registered-hives) u1))
    
    (print { event: "hive-deactivated", hive-id: hive-id })
    (ok true)
  )
)

(define-public (transfer-hive-ownership (hive-id uint) (new-owner principal))
  (let (
    (hive-data (unwrap! (map-get? hive-registry { hive-id: hive-id }) ERR_HIVE_NOT_FOUND))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get owner hive-data)) ERR_UNAUTHORIZED)
    (asserts! (get active hive-data) ERR_HIVE_NOT_FOUND)
    
    (map-set hive-registry { hive-id: hive-id }
             (merge hive-data { owner: new-owner }))
    
    (unwrap! (update-owner-hives new-owner hive-id) ERR_UNAUTHORIZED)
    
    (print { 
      event: "ownership-transferred", 
      hive-id: hive-id, 
      old-owner: (get owner hive-data), 
      new-owner: new-owner 
    })
    (ok true)
  )
)

;; read-only functions
(define-read-only (get-hive-info (hive-id uint))
  (map-get? hive-registry { hive-id: hive-id })
)

(define-read-only (get-hive-health (hive-id uint))
  (map-get? hive-health { hive-id: hive-id })
)

(define-read-only (get-hive-production (hive-id uint) (season uint))
  (map-get? hive-production { hive-id: hive-id, season: season })
)

(define-read-only (get-owner-hives (owner principal))
  (map-get? owner-hives { owner: owner })
)

(define-read-only (get-total-hives)
  (var-get total-registered-hives)
)

(define-read-only (get-contract-stats)
  {
    total-hives: (var-get total-registered-hives),
    next-hive-id: (+ (var-get hive-counter) u1),
    contract-active: (var-get contract-active),
    contract-owner: CONTRACT_OWNER
  }
)

