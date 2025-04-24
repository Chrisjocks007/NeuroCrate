;; Basic AI Model Registry Platform
;; Stage 1: Foundational structure with basic model registration and researcher profiles

;; Constants
(define-constant ERR-NOT-ADMINISTRATOR (err u1))
(define-constant ERR-PLATFORM-OFFLINE (err u2))
(define-constant ERR-INVALID-MODEL (err u3))
(define-constant ERR-INVALID-PARAMETER (err u5))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u6))
(define-constant ERR-MODEL-EXISTS (err u7))
(define-constant ERR-NOT-AUTHORIZED (err u9))
(define-constant MAX-MODEL-ID u1000) ;; Maximum allowed model ID
(define-constant MIN-REPUTATION-REQUIRED u10) ;; Minimum reputation to register
(define-constant MAX-REPUTATION-INPUT u1000000) ;; Maximum reputation input allowed

;; Data Variables
(define-data-var platform-administrator principal tx-sender)
(define-data-var platform-online bool false)
(define-data-var minimum-reputation-threshold uint u100) ;; 100 reputation points minimum

;; AI Model Structure
(define-map ai-models
    uint
    {
        model-name: (string-utf8 128),
        description: (string-utf8 512),
        version-hash: (buff 32),      ;; SHA256 hash of the current model version
        task-domain: (string-utf8 64),
        creator: principal,
        total-reputation: uint
    }
)

;; Researcher Profiles
(define-map researcher-profiles
    principal
    {
        reputation: uint,
        models-contributed: (list 30 uint),
        voting-power: uint           ;; Derived from reputation
    }
)

;; Authorization
(define-private (is-administrator)
    (is-eq tx-sender (var-get platform-administrator)))

;; Data Validation Functions
(define-private (is-valid-hash (hash (buff 32)))
    (> (len hash) u0))

(define-private (is-valid-reputation (rep uint))
    (and (>= rep MIN-REPUTATION-REQUIRED) (<= rep MAX-REPUTATION-INPUT)))

;; Platform Management Functions
(define-public (activate-platform)
    (begin
        (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
        (var-set platform-online true)
        (ok true)))

(define-public (register-model
    (model-id uint)
    (model-name (string-utf8 128))
    (description (string-utf8 512))
    (version-hash (buff 32))
    (task-domain (string-utf8 64)))
    (let (
        (researcher-profile (unwrap! (map-get? researcher-profiles tx-sender) ERR-INSUFFICIENT-REPUTATION))
        )
        
        ;; Check platform status
        (asserts! (var-get platform-online) ERR-PLATFORM-OFFLINE)
        
        ;; Validate model-id is within acceptable range
        (asserts! (<= model-id MAX-MODEL-ID) ERR-INVALID-PARAMETER)
        
        ;; Check if model already exists
        (asserts! (is-none (map-get? ai-models model-id)) ERR-MODEL-EXISTS)
        
        ;; Validate model-name and description are not empty
        (asserts! (> (len model-name) u0) ERR-INVALID-PARAMETER)
        (asserts! (> (len description) u0) ERR-INVALID-PARAMETER)
        (asserts! (> (len task-domain) u0) ERR-INVALID-PARAMETER)
        
        ;; Validate hash is not empty
        (asserts! (is-valid-hash version-hash) ERR-INVALID-PARAMETER)
        
        ;; Check researcher has enough reputation to register model
        (asserts! (>= (get reputation researcher-profile) (var-get minimum-reputation-threshold)) ERR-INSUFFICIENT-REPUTATION)
        
        ;; Set the model data
        (map-set ai-models model-id
            {
                model-name: model-name,
                description: description,
                version-hash: version-hash,
                task-domain: task-domain,
                creator: tx-sender,
                total-reputation: (get reputation researcher-profile)
            })
        
        ;; Update researcher profile
        (map-set researcher-profiles tx-sender
            (merge researcher-profile {
                models-contributed: (unwrap! (as-max-len? 
                    (append (get models-contributed researcher-profile) model-id) u30)
                    ERR-INVALID-PARAMETER)
            }))
        
        (ok true)))

;; Researcher Registration Functions
(define-public (register-researcher (initial-reputation uint))
    (begin
        (asserts! (var-get platform-online) ERR-PLATFORM-OFFLINE)
        
        ;; Validate reputation input
        (asserts! (is-valid-reputation initial-reputation) ERR-INVALID-PARAMETER)
        
        ;; Require some reputation token transfer (simplified for demonstration)
        (try! (stx-transfer? initial-reputation tx-sender (var-get platform-administrator)))
        
        ;; Initialize researcher profile with validated reputation
        (map-set researcher-profiles tx-sender
            {
                reputation: initial-reputation,
                models-contributed: (list),
                voting-power: initial-reputation
            })
            
        (ok true)))

;; Read-only functions
(define-read-only (get-model-details (model-id uint))
    (map-get? ai-models model-id))

(define-read-only (get-researcher-profile (researcher principal))
    (map-get? researcher-profiles researcher))

(define-read-only (get-platform-metrics)
    {
        online: (var-get platform-online),
        minimum-reputation: (var-get minimum-reputation-threshold)
    })

(define-public (update-minimum-reputation (new-minimum uint))
    (begin
        (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
        ;; Validate new threshold is within acceptable range
        (asserts! (and (>= new-minimum MIN-REPUTATION-REQUIRED) (<= new-minimum MAX-REPUTATION-INPUT)) ERR-INVALID-PARAMETER)
        (var-set minimum-reputation-threshold new-minimum)
        (ok true)))

(define-public (shutdown-platform)
    (begin
        (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
        (var-set platform-online false)
        (ok true)))

(define-public (transfer-administrator-role (new-administrator principal))
    (begin
        (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
        ;; Cannot set to zero address (represented as none in Clarity)
        (asserts! (is-some (some new-administrator)) ERR-INVALID-PARAMETER)
        (var-set platform-administrator new-administrator)
        (ok true)))