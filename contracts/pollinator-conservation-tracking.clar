;; pollinator-conservation-tracking
;; Track pollinator population health and coordinate conservation efforts with local farmers

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_SURVEY_NOT_FOUND (err u301))
(define-constant ERR_INVALID_POPULATION (err u302))
(define-constant ERR_PROJECT_NOT_FOUND (err u303))
(define-constant ERR_INVALID_COORDINATES (err u304))
(define-constant ERR_HABITAT_NOT_FOUND (err u305))

;; Population health levels
(define-constant HEALTH_POOR u1)
(define-constant HEALTH_FAIR u2)
(define-constant HEALTH_GOOD u3)
(define-constant HEALTH_EXCELLENT u4)

;; Conservation project status
(define-constant STATUS_PROPOSED u1)
(define-constant STATUS_APPROVED u2)
(define-constant STATUS_ACTIVE u3)
(define-constant STATUS_COMPLETED u4)
(define-constant STATUS_CANCELLED u5)

;; data maps and vars
(define-map pollinator-surveys
  { survey-id: uint }
  {
    surveyor: principal,
    location-name: (string-ascii 100),
    latitude: int,
    longitude: int,
    survey-date: uint,
    bee-population: uint,
    butterfly-population: uint,
    other-pollinator-count: uint,
    biodiversity-index: uint,
    habitat-quality: uint,
    threats-identified: (string-ascii 200),
    recommendations: (string-ascii 300)
  }
)

(define-map conservation-projects
  { project-id: uint }
  {
    project-name: (string-ascii 100),
    project-lead: principal,
    target-species: (string-ascii 100),
    project-area: uint,
    funding-required: uint,
    funding-secured: uint,
    start-date: uint,
    end-date: uint,
    status: uint,
    participants: uint,
    description: (string-ascii 300),
    success-metrics: (string-ascii 200)
  }
)

(define-map habitat-assessments
  { habitat-id: uint }
  {
    assessor: principal,
    habitat-type: (string-ascii 50),
    size-hectares: uint,
    native-plant-diversity: uint,
    water-availability: uint,
    pesticide-usage: uint,
    human-disturbance: uint,
    overall-score: uint,
    assessment-date: uint,
    improvement-suggestions: (string-ascii 300)
  }
)

(define-map farmer-collaborations
  { collaboration-id: uint }
  {
    farmer: principal,
    farm-name: (string-ascii 100),
    collaboration-type: (string-ascii 50),
    pollinator-friendly-practices: (string-ascii 200),
    habitat-area-provided: uint,
    crops-benefited: (string-ascii 100),
    started-at: uint,
    compensation: uint,
    performance-rating: uint,
    renewal-eligible: bool
  }
)

(define-map migration-tracking
  { tracking-id: uint }
  {
    species: (string-ascii 50),
    observer: principal,
    observation-date: uint,
    latitude: int,
    longitude: int,
    population-size: uint,
    behavior-notes: (string-ascii 200),
    weather-conditions: (string-ascii 100),
    migration-direction: (string-ascii 20),
    tagged-individuals: uint
  }
)

(define-map conservation-rewards
  { reward-id: uint }
  {
    recipient: principal,
    achievement-type: (string-ascii 100),
    project-id: (optional uint),
    reward-amount: uint,
    awarded-at: uint,
    verification-status: bool,
    verifier: (optional principal),
    notes: (string-ascii 200)
  }
)

(define-data-var survey-counter uint u0)
(define-data-var project-counter uint u0)
(define-data-var habitat-counter uint u0)
(define-data-var collaboration-counter uint u0)
(define-data-var tracking-counter uint u0)
(define-data-var reward-counter uint u0)
(define-data-var contract-active bool true)

;; private functions
(define-private (is-valid-coordinates (lat int) (lng int))
  (and 
    (and (>= lat -90000000) (<= lat 90000000))
    (and (>= lng -180000000) (<= lng 180000000))
  )
)

(define-private (is-valid-health-level (level uint))
  (and (>= level u1) (<= level u4))
)

(define-private (calculate-biodiversity-score (bee-pop uint) (butterfly-pop uint) (other-pop uint) (habitat-quality uint))
  (let (
    (total-pop (+ (+ bee-pop butterfly-pop) other-pop))
    (diversity-factor (if (and (> bee-pop u0) (> butterfly-pop u0) (> other-pop u0)) u120 u100))
    (base-score (+ total-pop habitat-quality))
  )
    (/ (* base-score diversity-factor) u100)
  )
)

(define-private (update-project-funding (project-id uint) (additional-funding uint))
  (match (map-get? conservation-projects { project-id: project-id })
    project-data
      (let (
        (new-funding (+ (get funding-secured project-data) additional-funding))
        (is-fully-funded (>= new-funding (get funding-required project-data)))
      )
        (map-set conservation-projects { project-id: project-id }
                 (merge project-data { 
                   funding-secured: new-funding,
                   status: (if is-fully-funded STATUS_APPROVED (get status project-data))
                 }))
        true)
    false
  )
)

(define-private (calculate-conservation-impact (project-area uint) (participants uint) (duration uint))
  (let (
    (area-impact (* project-area u10))
    (participant-impact (* participants u5))
    (duration-impact (* duration u2))
  )
    (+ (+ area-impact participant-impact) duration-impact)
  )
)

;; public functions
(define-public (conduct-pollinator-survey (location-name (string-ascii 100)) (latitude int) (longitude int) (bee-population uint) (butterfly-population uint) (other-pollinator-count uint) (habitat-quality uint) (threats-identified (string-ascii 200)) (recommendations (string-ascii 300)))
  (let (
    (new-survey-id (+ (var-get survey-counter) u1))
    (biodiversity-index (calculate-biodiversity-score bee-population butterfly-population other-pollinator-count habitat-quality))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-valid-coordinates latitude longitude) ERR_INVALID_COORDINATES)
    (asserts! (is-valid-health-level habitat-quality) ERR_INVALID_POPULATION)
    
    (map-set pollinator-surveys { survey-id: new-survey-id }
             {
               surveyor: tx-sender,
               location-name: location-name,
               latitude: latitude,
               longitude: longitude,
               survey-date: stacks-block-height,
               bee-population: bee-population,
               butterfly-population: butterfly-population,
               other-pollinator-count: other-pollinator-count,
               biodiversity-index: biodiversity-index,
               habitat-quality: habitat-quality,
               threats-identified: threats-identified,
               recommendations: recommendations
             })
    
    (var-set survey-counter new-survey-id)
    
    ;; Award points for conducting survey
    (unwrap! (award-conservation-reward tx-sender "SURVEY_COMPLETION" none u50 "Pollinator survey completed") ERR_UNAUTHORIZED)
    
    (print { 
      event: "survey-conducted", 
      survey-id: new-survey-id, 
      location: location-name, 
      biodiversity-index: biodiversity-index 
    })
    (ok new-survey-id)
  )
)

(define-public (create-conservation-project (project-name (string-ascii 100)) (target-species (string-ascii 100)) (project-area uint) (funding-required uint) (start-date uint) (end-date uint) (description (string-ascii 300)) (success-metrics (string-ascii 200)))
  (let (
    (new-project-id (+ (var-get project-counter) u1))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (> project-area u0) ERR_INVALID_POPULATION)
    (asserts! (> funding-required u0) ERR_INVALID_POPULATION)
    (asserts! (< start-date end-date) ERR_UNAUTHORIZED)
    
    (map-set conservation-projects { project-id: new-project-id }
             {
               project-name: project-name,
               project-lead: tx-sender,
               target-species: target-species,
               project-area: project-area,
               funding-required: funding-required,
               funding-secured: u0,
               start-date: start-date,
               end-date: end-date,
               status: STATUS_PROPOSED,
               participants: u1,
               description: description,
               success-metrics: success-metrics
             })
    
    (var-set project-counter new-project-id)
    
    (print { 
      event: "project-created", 
      project-id: new-project-id, 
      project-name: project-name, 
      project-lead: tx-sender 
    })
    (ok new-project-id)
  )
)

(define-public (assess-habitat (habitat-type (string-ascii 50)) (size-hectares uint) (native-plant-diversity uint) (water-availability uint) (pesticide-usage uint) (human-disturbance uint) (improvement-suggestions (string-ascii 300)))
  (let (
    (new-habitat-id (+ (var-get habitat-counter) u1))
    (overall-score (calculate-habitat-score native-plant-diversity water-availability pesticide-usage human-disturbance))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (> size-hectares u0) ERR_INVALID_POPULATION)
    (asserts! (<= native-plant-diversity u100) ERR_INVALID_POPULATION)
    (asserts! (<= water-availability u100) ERR_INVALID_POPULATION)
    (asserts! (<= pesticide-usage u100) ERR_INVALID_POPULATION)
    (asserts! (<= human-disturbance u100) ERR_INVALID_POPULATION)
    
    (map-set habitat-assessments { habitat-id: new-habitat-id }
             {
               assessor: tx-sender,
               habitat-type: habitat-type,
               size-hectares: size-hectares,
               native-plant-diversity: native-plant-diversity,
               water-availability: water-availability,
               pesticide-usage: pesticide-usage,
               human-disturbance: human-disturbance,
               overall-score: overall-score,
               assessment-date: stacks-block-height,
               improvement-suggestions: improvement-suggestions
             })
    
    (var-set habitat-counter new-habitat-id)
    
    ;; Reward for habitat assessment
    (if (>= overall-score u70)
        (unwrap! (award-conservation-reward tx-sender "HABITAT_EXCELLENCE" none u100 "High-quality habitat identified") ERR_UNAUTHORIZED)
        (unwrap! (award-conservation-reward tx-sender "HABITAT_ASSESSMENT" none u25 "Habitat assessment completed") ERR_UNAUTHORIZED))
    
    (print { 
      event: "habitat-assessed", 
      habitat-id: new-habitat-id, 
      habitat-type: habitat-type, 
      overall-score: overall-score 
    })
    (ok new-habitat-id)
  )
)

(define-private (calculate-habitat-score (plant-diversity uint) (water uint) (pesticide uint) (disturbance uint))
  (let (
    (positive-factors (+ plant-diversity water))
    (negative-factors (+ pesticide disturbance))
    (base-score (if (> positive-factors negative-factors) 
                    (- positive-factors (/ negative-factors u2))
                    (/ positive-factors u2)))
  )
    (if (> base-score u100) u100 base-score)
  )
)

(define-public (establish-farmer-collaboration (farm-name (string-ascii 100)) (collaboration-type (string-ascii 50)) (pollinator-friendly-practices (string-ascii 200)) (habitat-area-provided uint) (crops-benefited (string-ascii 100)) (compensation uint))
  (let (
    (new-collaboration-id (+ (var-get collaboration-counter) u1))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (> habitat-area-provided u0) ERR_INVALID_POPULATION)
    
    (map-set farmer-collaborations { collaboration-id: new-collaboration-id }
             {
               farmer: tx-sender,
               farm-name: farm-name,
               collaboration-type: collaboration-type,
               pollinator-friendly-practices: pollinator-friendly-practices,
               habitat-area-provided: habitat-area-provided,
               crops-benefited: crops-benefited,
               started-at: stacks-block-height,
               compensation: compensation,
               performance-rating: u0,
               renewal-eligible: true
             })
    
    (var-set collaboration-counter new-collaboration-id)
    
    ;; Reward farmer for collaboration
    (let (
      (reward-amount (* habitat-area-provided u5))
    )
      (unwrap! (award-conservation-reward tx-sender "FARMER_COLLABORATION" none reward-amount "Pollinator-friendly farming practices established") ERR_UNAUTHORIZED)
    )
    
    (print { 
      event: "collaboration-established", 
      collaboration-id: new-collaboration-id, 
      farmer: tx-sender, 
      habitat-area: habitat-area-provided 
    })
    (ok new-collaboration-id)
  )
)

(define-public (track-pollinator-migration (species (string-ascii 50)) (latitude int) (longitude int) (population-size uint) (behavior-notes (string-ascii 200)) (weather-conditions (string-ascii 100)) (migration-direction (string-ascii 20)) (tagged-individuals uint))
  (let (
    (new-tracking-id (+ (var-get tracking-counter) u1))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-valid-coordinates latitude longitude) ERR_INVALID_COORDINATES)
    (asserts! (> population-size u0) ERR_INVALID_POPULATION)
    
    (map-set migration-tracking { tracking-id: new-tracking-id }
             {
               species: species,
               observer: tx-sender,
               observation-date: stacks-block-height,
               latitude: latitude,
               longitude: longitude,
               population-size: population-size,
               behavior-notes: behavior-notes,
               weather-conditions: weather-conditions,
               migration-direction: migration-direction,
               tagged-individuals: tagged-individuals
             })
    
    (var-set tracking-counter new-tracking-id)
    
    ;; Reward for migration tracking
    (unwrap! (award-conservation-reward tx-sender "MIGRATION_TRACKING" none u30 "Migration data recorded") ERR_UNAUTHORIZED)
    
    (print { 
      event: "migration-tracked", 
      tracking-id: new-tracking-id, 
      species: species, 
      population-size: population-size 
    })
    (ok new-tracking-id)
  )
)

(define-public (award-conservation-reward (recipient principal) (achievement-type (string-ascii 100)) (project-id (optional uint)) (reward-amount uint) (notes (string-ascii 200)))
  (let (
    (new-reward-id (+ (var-get reward-counter) u1))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (> reward-amount u0) ERR_INVALID_POPULATION)
    
    (map-set conservation-rewards { reward-id: new-reward-id }
             {
               recipient: recipient,
               achievement-type: achievement-type,
               project-id: project-id,
               reward-amount: reward-amount,
               awarded-at: stacks-block-height,
               verification-status: false,
               verifier: none,
               notes: notes
             })
    
    (var-set reward-counter new-reward-id)
    
    (print { 
      event: "reward-awarded", 
      reward-id: new-reward-id, 
      recipient: recipient, 
      amount: reward-amount 
    })
    (ok new-reward-id)
  )
)

(define-public (verify-conservation-achievement (reward-id uint))
  (let (
    (reward-data (unwrap! (map-get? conservation-rewards { reward-id: reward-id }) ERR_UNAUTHORIZED))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (not (get verification-status reward-data)) ERR_UNAUTHORIZED)
    
    (map-set conservation-rewards { reward-id: reward-id }
             (merge reward-data {
               verification-status: true,
               verifier: (some tx-sender)
             }))
    
    (print { event: "achievement-verified", reward-id: reward-id })
    (ok true)
  )
)

;; read-only functions
(define-read-only (get-survey-info (survey-id uint))
  (map-get? pollinator-surveys { survey-id: survey-id })
)

(define-read-only (get-project-info (project-id uint))
  (map-get? conservation-projects { project-id: project-id })
)

(define-read-only (get-habitat-assessment (habitat-id uint))
  (map-get? habitat-assessments { habitat-id: habitat-id })
)

(define-read-only (get-collaboration-info (collaboration-id uint))
  (map-get? farmer-collaborations { collaboration-id: collaboration-id })
)

(define-read-only (get-migration-data (tracking-id uint))
  (map-get? migration-tracking { tracking-id: tracking-id })
)

(define-read-only (get-reward-info (reward-id uint))
  (map-get? conservation-rewards { reward-id: reward-id })
)

(define-read-only (get-contract-stats)
  {
    total-surveys: (var-get survey-counter),
    total-projects: (var-get project-counter),
    total-habitats: (var-get habitat-counter),
    total-collaborations: (var-get collaboration-counter),
    total-tracking-records: (var-get tracking-counter),
    total-rewards: (var-get reward-counter),
    contract-active: (var-get contract-active)
  }
)

(define-read-only (calculate-regional-biodiversity (lat-center int) (lng-center int) (radius int))
  ;; Simplified calculation for demonstration
  ;; In production, this would analyze all surveys within the radius
  (let (
    (base-biodiversity u50)
    (survey-bonus u25)
  )
    (+ base-biodiversity survey-bonus)
  )
)

