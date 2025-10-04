;; disease-prevention-monitoring
;; Monitor bee diseases and coordinate treatment to prevent colony collapse disorder

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_OUTBREAK_NOT_FOUND (err u201))
(define-constant ERR_INVALID_SEVERITY (err u202))
(define-constant ERR_TREATMENT_NOT_FOUND (err u203))
(define-constant ERR_INVALID_COORDINATES (err u204))
(define-constant ERR_DUPLICATE_REPORT (err u205))

;; Disease severity levels
(define-constant SEVERITY_LOW u1)
(define-constant SEVERITY_MODERATE u2)
(define-constant SEVERITY_HIGH u3)
(define-constant SEVERITY_CRITICAL u4)

;; Treatment status
(define-constant STATUS_PENDING u1)
(define-constant STATUS_IN_PROGRESS u2)
(define-constant STATUS_COMPLETED u3)
(define-constant STATUS_FAILED u4)

;; data maps and vars
(define-map disease-outbreaks
  { outbreak-id: uint }
  {
    reporter: principal,
    disease-type: (string-ascii 50),
    latitude: int,
    longitude: int,
    severity-level: uint,
    affected-colonies: uint,
    reported-at: uint,
    status: uint,
    description: (string-ascii 200)
  }
)

(define-map treatment-protocols
  { treatment-id: uint }
  {
    outbreak-id: uint,
    treatment-type: (string-ascii 100),
    medication: (string-ascii 100),
    dosage: (string-ascii 50),
    frequency: (string-ascii 50),
    duration: uint,
    administered-by: principal,
    cost: uint,
    effectiveness: uint,
    started-at: uint,
    completed-at: (optional uint),
    notes: (string-ascii 200)
  }
)

(define-map varroa-monitoring
  { hive-id: uint, inspection-date: uint }
  {
    mite-count: uint,
    infestation-level: uint,
    treatment-needed: bool,
    inspector: principal,
    next-inspection: uint,
    notes: (string-ascii 150)
  }
)

(define-map colony-collapse-tracking
  { collapse-id: uint }
  {
    hive-id: uint,
    collapse-date: uint,
    suspected-cause: (string-ascii 100),
    symptoms: (string-ascii 200),
    environmental-factors: (string-ascii 200),
    recovery-attempts: uint,
    final-outcome: (string-ascii 50),
    investigator: principal
  }
)

(define-map disease-alerts
  { alert-id: uint }
  {
    disease-type: (string-ascii 50),
    alert-level: uint,
    affected-region: (string-ascii 100),
    recommended-actions: (string-ascii 300),
    issued-by: principal,
    issued-at: uint,
    expires-at: uint,
    active: bool
  }
)

(define-data-var outbreak-counter uint u0)
(define-data-var treatment-counter uint u0)
(define-data-var collapse-counter uint u0)
(define-data-var alert-counter uint u0)
(define-data-var contract-active bool true)

;; private functions
(define-private (is-valid-severity (severity uint))
  (and (>= severity u1) (<= severity u4))
)

(define-private (is-valid-coordinates (lat int) (lng int))
  (and 
    (and (>= lat -90000000) (<= lat 90000000))
    (and (>= lng -180000000) (<= lng 180000000))
  )
)

(define-private (calculate-risk-score (severity uint) (affected-colonies uint) (disease-type (string-ascii 50)))
  (let (
    (base-score (* severity affected-colonies))
    (disease-multiplier (if (or (is-eq disease-type "varroa_mite") 
                               (is-eq disease-type "nosema")) 
                           u2 u1))
  )
    (* base-score disease-multiplier)
  )
)

(define-private (update-outbreak-status (outbreak-id uint) (new-status uint))
  (match (map-get? disease-outbreaks { outbreak-id: outbreak-id })
    outbreak-data
      (begin
        (map-set disease-outbreaks { outbreak-id: outbreak-id }
                 (merge outbreak-data { status: new-status }))
        true)
    false
  )
)

(define-private (get-nearby-outbreaks (lat int) (lng int) (radius int))
  ;; Simplified distance calculation for demonstration
  (let (
    (lat-diff-threshold radius)
    (lng-diff-threshold radius)
  )
    ;; This would typically involve more complex geospatial calculations
    true
  )
)

;; public functions
(define-public (report-disease-outbreak (disease-type (string-ascii 50)) (latitude int) (longitude int) (severity-level uint) (affected-colonies uint) (description (string-ascii 200)))
  (let (
    (new-outbreak-id (+ (var-get outbreak-counter) u1))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-valid-severity severity-level) ERR_INVALID_SEVERITY)
    (asserts! (is-valid-coordinates latitude longitude) ERR_INVALID_COORDINATES)
    (asserts! (> affected-colonies u0) ERR_INVALID_SEVERITY)
    
    (map-set disease-outbreaks { outbreak-id: new-outbreak-id }
             {
               reporter: tx-sender,
               disease-type: disease-type,
               latitude: latitude,
               longitude: longitude,
               severity-level: severity-level,
               affected-colonies: affected-colonies,
               reported-at: stacks-block-height,
               status: STATUS_PENDING,
               description: description
             })
    
    (var-set outbreak-counter new-outbreak-id)
    
    ;; Auto-generate alert for critical outbreaks
    (if (is-eq severity-level SEVERITY_CRITICAL)
        (unwrap! (create-disease-alert disease-type SEVERITY_CRITICAL 
                                      "IMMEDIATE_QUARANTINE_REQUIRED" 
                                      "Immediate quarantine and treatment protocol activation required") 
                ERR_UNAUTHORIZED)
        true)
    
    (print { 
      event: "outbreak-reported", 
      outbreak-id: new-outbreak-id, 
      disease-type: disease-type, 
      severity: severity-level,
      reporter: tx-sender
    })
    (ok new-outbreak-id)
  )
)

(define-public (record-treatment (outbreak-id uint) (treatment-type (string-ascii 100)) (medication (string-ascii 100)) (dosage (string-ascii 50)) (frequency (string-ascii 50)) (duration uint) (cost uint) (notes (string-ascii 200)))
  (let (
    (new-treatment-id (+ (var-get treatment-counter) u1))
    (outbreak-data (unwrap! (map-get? disease-outbreaks { outbreak-id: outbreak-id }) ERR_OUTBREAK_NOT_FOUND))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (> duration u0) ERR_UNAUTHORIZED)
    
    (map-set treatment-protocols { treatment-id: new-treatment-id }
             {
               outbreak-id: outbreak-id,
               treatment-type: treatment-type,
               medication: medication,
               dosage: dosage,
               frequency: frequency,
               duration: duration,
               administered-by: tx-sender,
               cost: cost,
               effectiveness: u0,
               started-at: stacks-block-height,
               completed-at: none,
               notes: notes
             })
    
    (var-set treatment-counter new-treatment-id)
    (unwrap! (update-outbreak-status outbreak-id STATUS_IN_PROGRESS) ERR_OUTBREAK_NOT_FOUND)
    
    (print { 
      event: "treatment-recorded", 
      treatment-id: new-treatment-id, 
      outbreak-id: outbreak-id, 
      treatment-type: treatment-type 
    })
    (ok new-treatment-id)
  )
)

(define-public (update-treatment-effectiveness (treatment-id uint) (effectiveness uint) (completed bool))
  (let (
    (treatment-data (unwrap! (map-get? treatment-protocols { treatment-id: treatment-id }) ERR_TREATMENT_NOT_FOUND))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get administered-by treatment-data)) ERR_UNAUTHORIZED)
    (asserts! (<= effectiveness u100) ERR_INVALID_SEVERITY)
    
    (map-set treatment-protocols { treatment-id: treatment-id }
             (merge treatment-data {
               effectiveness: effectiveness,
               completed-at: (if completed (some stacks-block-height) none)
             }))
    
    ;; Update outbreak status if treatment is completed
    (if completed
        (let (
          (outbreak-id (get outbreak-id treatment-data))
          (new-status (if (>= effectiveness u70) STATUS_COMPLETED STATUS_FAILED))
        )
          (unwrap! (update-outbreak-status outbreak-id new-status) ERR_OUTBREAK_NOT_FOUND)
          true)
        true)
    
    (print { 
      event: "treatment-updated", 
      treatment-id: treatment-id, 
      effectiveness: effectiveness, 
      completed: completed 
    })
    (ok true)
  )
)

(define-public (record-varroa-inspection (hive-id uint) (mite-count uint) (infestation-level uint) (treatment-needed bool) (notes (string-ascii 150)))
  (let (
    (inspection-date stacks-block-height)
    (next-inspection (+ stacks-block-height u144)) ;; Roughly 1 day in blocks
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (<= infestation-level u4) ERR_INVALID_SEVERITY)
    
    (map-set varroa-monitoring { hive-id: hive-id, inspection-date: inspection-date }
             {
               mite-count: mite-count,
               infestation-level: infestation-level,
               treatment-needed: treatment-needed,
               inspector: tx-sender,
               next-inspection: next-inspection,
               notes: notes
             })
    
    ;; Auto-report outbreak if severe infestation
    (if (>= infestation-level u3)
        (unwrap! (report-disease-outbreak "varroa_mite" 0 0 infestation-level u1 "High varroa infestation detected") ERR_UNAUTHORIZED)
        true)
    
    (print { 
      event: "varroa-inspection", 
      hive-id: hive-id, 
      mite-count: mite-count, 
      infestation-level: infestation-level 
    })
    (ok true)
  )
)

(define-public (report-colony-collapse (hive-id uint) (suspected-cause (string-ascii 100)) (symptoms (string-ascii 200)) (environmental-factors (string-ascii 200)))
  (let (
    (new-collapse-id (+ (var-get collapse-counter) u1))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    
    (map-set colony-collapse-tracking { collapse-id: new-collapse-id }
             {
               hive-id: hive-id,
               collapse-date: stacks-block-height,
               suspected-cause: suspected-cause,
               symptoms: symptoms,
               environmental-factors: environmental-factors,
               recovery-attempts: u0,
               final-outcome: "INVESTIGATING",
               investigator: tx-sender
             })
    
    (var-set collapse-counter new-collapse-id)
    
    ;; Create critical alert for colony collapse
    (unwrap! (create-disease-alert "COLONY_COLLAPSE" SEVERITY_CRITICAL "REGION_WIDE" 
                                  "Colony collapse detected - investigate immediate causes and implement prevention measures") 
            ERR_UNAUTHORIZED)
    
    (print { 
      event: "colony-collapse-reported", 
      collapse-id: new-collapse-id, 
      hive-id: hive-id, 
      suspected-cause: suspected-cause 
    })
    (ok new-collapse-id)
  )
)

(define-public (create-disease-alert (disease-type (string-ascii 50)) (alert-level uint) (affected-region (string-ascii 100)) (recommended-actions (string-ascii 300)))
  (let (
    (new-alert-id (+ (var-get alert-counter) u1))
    (expires-at (+ stacks-block-height u1008)) ;; Roughly 1 week
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-valid-severity alert-level) ERR_INVALID_SEVERITY)
    
    (map-set disease-alerts { alert-id: new-alert-id }
             {
               disease-type: disease-type,
               alert-level: alert-level,
               affected-region: affected-region,
               recommended-actions: recommended-actions,
               issued-by: tx-sender,
               issued-at: stacks-block-height,
               expires-at: expires-at,
               active: true
             })
    
    (var-set alert-counter new-alert-id)
    
    (print { 
      event: "disease-alert-created", 
      alert-id: new-alert-id, 
      disease-type: disease-type, 
      alert-level: alert-level 
    })
    (ok new-alert-id)
  )
)

;; read-only functions
(define-read-only (get-outbreak-info (outbreak-id uint))
  (map-get? disease-outbreaks { outbreak-id: outbreak-id })
)

(define-read-only (get-treatment-info (treatment-id uint))
  (map-get? treatment-protocols { treatment-id: treatment-id })
)

(define-read-only (get-varroa-inspection (hive-id uint) (inspection-date uint))
  (map-get? varroa-monitoring { hive-id: hive-id, inspection-date: inspection-date })
)

(define-read-only (get-collapse-info (collapse-id uint))
  (map-get? colony-collapse-tracking { collapse-id: collapse-id })
)

(define-read-only (get-disease-alert (alert-id uint))
  (map-get? disease-alerts { alert-id: alert-id })
)

(define-read-only (get-contract-stats)
  {
    total-outbreaks: (var-get outbreak-counter),
    total-treatments: (var-get treatment-counter),
    total-collapses: (var-get collapse-counter),
    total-alerts: (var-get alert-counter),
    contract-active: (var-get contract-active)
  }
)

(define-read-only (calculate-outbreak-risk (lat int) (lng int))
  (let (
    (nearby-outbreaks (get-nearby-outbreaks lat lng 100000)) ;; 100km radius
  )
    ;; Simplified risk calculation
    (if nearby-outbreaks u75 u25)
  )
)

