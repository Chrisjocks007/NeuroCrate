;; AI Model Collaboration Platform
;; Stage 2: Adding contribution system with model improvements

;; Constants
(define-constant ERR-NOT-ADMINISTRATOR (err u1))
(define-constant ERR-PLATFORM-OFFLINE (err u2))
(define-constant ERR-INVALID-MODEL (err u3))
(define-constant ERR-MODEL-LOCKED (err u4))
(define-constant ERR-INVALID-PARAMETER (err u5))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u6))
(define-constant ERR-MODEL-EXISTS (err u7))
(define-constant ERR-NOT-AUTHORIZED (err u9))
(define-constant ERR-CONTRIBUTION-NOT-FOUND (err u10))
(define-constant MAX-MODEL-ID u1000) ;; Maximum allowed model ID
(define-constant MIN-REPUTATION-REQUIRED u10) ;; Minimum reputation to register
(define-constant MAX-REPUTATION-INPUT u1000000) ;; Maximum reputation input allowed

;; Data Variables
(define-data-var platform-administrator principal tx-sender)
(define-data-var platform-online bool false)
(define-data-var collaboration-cycle uint u0)
(define-data-var minimum-reputation-threshold uint u100) ;; 100 reputation points minimum

;; AI Model Structure
(define-map ai-models
    uint
    {
        model-name: (string-utf8 128),
        description: (string-utf8 512),
        version-hash: (buff 32),      ;; SHA256 hash of the current model version
        task-domain: (string-utf8 64),
        contributions-open: bool,
        creator: principal,
        total-reputation: uint,
        integrated-contributions: uint ;; Counter of accepted contributions
    }
)

;; Model Contributors Mapping
(define-map model-contributors
    {model-id: uint, contributor: principal}
    {
        reputation-staked: uint
    }
)

;; Researcher Profiles
(define-map researcher-profiles
    principal
    {
        reputation: uint,
        models-contributed: (list 30 uint),
        contributions-submitted: (list 30 uint),
        voting-power: uint
    }
)

;; Contribution Structure
(define-map model-contributions
    uint  ;; contribution-id
    {
        description: (string-utf8 256),
        contribution-hash: (buff 32),
        contributor: principal,
        target-model: uint,
        submitted-in-cycle: uint,
        integrated: bool
    }
)

;; Authorization
(define-private (is-administrator)
    (is-eq tx-sender (var-get platform-administrator)))

;; Data Validation Functions
(define-private (is-valid-hash (hash (buff 32)))
    (> (len hash) u0))

(define-private (is-valid-description (desc (string-utf8 256)))
    (> (len desc) u0))

(define-private (is-valid-reputation (rep uint))
    (and (>= rep MIN-REPUTATION-REQUIRED) (<= rep MAX-REPUTATION-INPUT)))

;; Platform Management Functions
(define-public (activate-platform)
    (begin
        (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
        (var-set platform-online true)
        (var-set collaboration-cycle u0)
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
                contributions-open: true,
                creator: tx-sender,
                total-reputation: (get reputation researcher-profile),
                integrated-contributions: u0
            })
        
        ;; Record researcher as contributor
        (map-set model-contributors 
            {model-id: model-id, contributor: tx-sender}
            {reputation-staked: (get reputation researcher-profile)})
        
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
                contributions-submitted: (list),
                voting-power: initial-reputation
            })
            
        (ok true)))

;; Contribution Submission
(define-public (submit-contribution
    (contribution-id uint)
    (target-model-id uint)
    (description (string-utf8 256))
    (contribution-hash (buff 32)))
    (let (
        (model (unwrap! (map-get? ai-models target-model-id) ERR-INVALID-MODEL))
        (researcher (unwrap! (map-get? researcher-profiles tx-sender) ERR-INSUFFICIENT-REPUTATION))
        )
        
        ;; Check platform status
        (asserts! (var-get platform-online) ERR-PLATFORM-OFFLINE)
        
        ;; Check if model is accepting contributions
        (asserts! (get contributions-open model) ERR-MODEL-LOCKED)
        
        ;; Check that contribution ID doesn't already exist
        (asserts! (is-none (map-get? model-contributions contribution-id)) ERR-INVALID-PARAMETER)
        
        ;; Validate description and hash
        (asserts! (is-valid-description description) ERR-INVALID-PARAMETER)
        (asserts! (is-valid-hash contribution-hash) ERR-INVALID-PARAMETER)
        
        ;; Record the contribution
        (map-set model-contributions contribution-id
            {
                description: description,
                contribution-hash: contribution-hash,
                contributor: tx-sender,
                target-model: target-model-id,
                submitted-in-cycle: (var-get collaboration-cycle),
                integrated: false
            })
        
        ;; Update researcher's submitted contributions
        (map-set researcher-profiles tx-sender
            (merge researcher {
                contributions-submitted: (unwrap! (as-max-len? 
                    (append (get contributions-submitted researcher) contribution-id) u30)
                    ERR-INVALID-PARAMETER)
            }))
        
        (ok true)))

;; Process Contribution (admin only in this version)
(define-public (process-contribution (contribution-id uint) (approve bool))
    (let (
        (contribution (unwrap! (map-get? model-contributions contribution-id) ERR-CONTRIBUTION-NOT-FOUND))
        (model (unwrap! (map-get? ai-models (get target-model contribution)) ERR-INVALID-MODEL))
        (contributor (unwrap! (map-get? researcher-profiles (get contributor contribution)) ERR-INVALID-PARAMETER))
        )
        
        ;; Only administrator can process contributions
        (asserts! (is-administrator) ERR-NOT-AUTHORIZED)
        (asserts! (var-get platform-online) ERR-PLATFORM-OFFLINE)
        
        ;; Ensure contribution hasn't already been integrated
        (asserts! (not (get integrated contribution)) ERR-MODEL-LOCKED)
        
        ;; Process the contribution based on approval
        (if approve
            (begin
                ;; Update contribution status
                (map-set model-contributions contribution-id
                    (merge contribution {integrated: true}))
                
                ;; Update model data
                (map-set ai-models (get target-model contribution)
                    (merge model {
                        version-hash: (get contribution-hash contribution),
                        integrated-contributions: (+ (get integrated-contributions model) u1)
                    }))
                
                ;; Add contributor to model contributors if not already
                (match (map-get? model-contributors 
                        {model-id: (get target-model contribution), contributor: (get contributor contribution)})
                    existing-contribution
                    true
                    ;; Add new contributor
                    (map-set model-contributors 
                        {model-id: (get target-model contribution), contributor: (get contributor contribution)}
                        {reputation-staked: (get reputation contributor)}))
                
                ;; Update model's total reputation
                (map-set ai-models (get target-model contribution)
                    (merge model {
                        total-reputation: (+ (get total-reputation model) (get reputation contributor))
                    }))
                
                ;; Reward contributor with reputation boost
                (map-set researcher-profiles (get contributor contribution)
                    (merge contributor {
                        reputation: (+ (get reputation contributor) u25),
                        voting-power: (+ (get voting-power contributor) u10)
                    }))
                
                (ok true))
            (ok false)))) ;; No action if rejected

;; Change Model Contribution Status
(define-public (set-model-contributions-status (model-id uint) (open bool))
    (let (
        (model (unwrap! (map-get? ai-models model-id) ERR-INVALID-MODEL))
        )
        
        ;; Check platform status
        (asserts! (var-get platform-online) ERR-PLATFORM-OFFLINE)
        
        ;; Only creator or admin can change status
        (asserts! (or (is-eq tx-sender (get creator model)) (is-administrator)) ERR-NOT-AUTHORIZED)
        
        ;; Update model status
        (map-set ai-models model-id
            (merge model {contributions-open: open}))
        
        (ok true)))

;; Read-only functions
(define-read-only (get-model-details (model-id uint))
    (map-get? ai-models model-id))

(define-read-only (get-researcher-profile (researcher principal))
    (map-get? researcher-profiles researcher))

(define-read-only (get-contribution-details (contribution-id uint))
    (map-get? model-contributions contribution-id))

(define-read-only (get-platform-metrics)
    {
        online: (var-get platform-online),
        collaboration-cycle: (var-get collaboration-cycle),
        minimum-reputation: (var-get minimum-reputation-threshold)
    })

(define-public (update-minimum-reputation (new-minimum uint))
    (begin
        (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
        ;; Validate new threshold is within acceptable range
        (asserts! (and (>= new-minimum MIN-REPUTATION-REQUIRED) (<= new-minimum MAX-REPUTATION-INPUT)) ERR-INVALID-PARAMETER)
        (var-set minimum-reputation-threshold new-minimum)
        (ok true)))

(define-public (advance-collaboration-cycle)
    (begin
        (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
        (asserts! (var-get platform-online) ERR-PLATFORM-OFFLINE)
        (var-set collaboration-cycle (+ (var-get collaboration-cycle) u1))
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