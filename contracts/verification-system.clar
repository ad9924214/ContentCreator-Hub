(define-constant ERR-UNAUTHORIZED-VERIFIER (err u200))
(define-constant ERR-ALREADY-VERIFIED (err u201))
(define-constant ERR-INVALID-VERIFICATION-TYPE (err u202))
(define-constant ERR-VERIFICATION-EXPIRED (err u203))
(define-constant ERR-INVALID-REPUTATION-SCORE (err u204))

(define-data-var verification-authority principal tx-sender)

(define-map verified-creators
  { creator-id: uint }
  {
    verification-type: (string-ascii 20),
    verified-by: principal,
    verified-at: uint,
    expires-at: uint,
    reputation-score: uint,
    verification-document: (string-ascii 256)
  }
)

(define-map verifier-permissions
  { verifier: principal }
  {
    can-verify: bool,
    verification-types: (list 5 (string-ascii 20)),
    added-at: uint
  }
)

(define-map creator-reputation
  { creator-id: uint }
  {
    base-score: uint,
    subscriber-rating: uint,
    content-quality: uint,
    activity-score: uint,
    final-score: uint,
    last-updated: uint
  }
)

(define-public (set-verification-authority (new-authority principal))
  (begin
    (asserts! (is-eq tx-sender (var-get verification-authority)) ERR-UNAUTHORIZED-VERIFIER)
    (var-set verification-authority new-authority)
    (ok true)
  )
)

(define-public (add-verifier (verifier principal) (verification-types (list 5 (string-ascii 20))))
  (begin
    (asserts! (is-eq tx-sender (var-get verification-authority)) ERR-UNAUTHORIZED-VERIFIER)
    (map-set verifier-permissions
      { verifier: verifier }
      {
        can-verify: true,
        verification-types: verification-types,
        added-at: stacks-block-height
      }
    )
    (ok true)
  )
)

(define-public (verify-creator 
    (creator-id uint) 
    (verification-type (string-ascii 20)) 
    (duration uint)
    (reputation-score uint)
    (verification-document (string-ascii 256))
  )
  (let
    ((verifier-data (unwrap! (map-get? verifier-permissions { verifier: tx-sender }) ERR-UNAUTHORIZED-VERIFIER))
     (existing-verification (map-get? verified-creators { creator-id: creator-id }))
     (expires-at (+ stacks-block-height duration)))
    
    (asserts! (get can-verify verifier-data) ERR-UNAUTHORIZED-VERIFIER)
    (asserts! (is-none existing-verification) ERR-ALREADY-VERIFIED)
    (asserts! (and (>= reputation-score u0) (<= reputation-score u100)) ERR-INVALID-REPUTATION-SCORE)
    
    (map-set verified-creators
      { creator-id: creator-id }
      {
        verification-type: verification-type,
        verified-by: tx-sender,
        verified-at: stacks-block-height,
        expires-at: expires-at,
        reputation-score: reputation-score,
        verification-document: verification-document
      }
    )
    
    (unwrap-panic (update-creator-reputation creator-id reputation-score))
    (ok true)
  )
)

(define-public (revoke-verification (creator-id uint))
  (let
    ((verification-data (unwrap! (map-get? verified-creators { creator-id: creator-id }) ERR-ALREADY-VERIFIED))
     (verifier-data (unwrap! (map-get? verifier-permissions { verifier: tx-sender }) ERR-UNAUTHORIZED-VERIFIER)))
    
    (asserts! (or 
      (is-eq tx-sender (get verified-by verification-data))
      (is-eq tx-sender (var-get verification-authority))
    ) ERR-UNAUTHORIZED-VERIFIER)
    
    (map-delete verified-creators { creator-id: creator-id })
    (ok true)
  )
)

(define-public (update-creator-reputation (creator-id uint) (new-base-score uint))
  (let
    ((current-rep (default-to 
      { base-score: u50, subscriber-rating: u50, content-quality: u50, activity-score: u50, final-score: u50, last-updated: u0 }
      (map-get? creator-reputation { creator-id: creator-id })))
     (final-score (/ (+ new-base-score (get subscriber-rating current-rep) (get content-quality current-rep) (get activity-score current-rep)) u4)))
    
    (asserts! (and (>= new-base-score u0) (<= new-base-score u100)) ERR-INVALID-REPUTATION-SCORE)
    
    (map-set creator-reputation
      { creator-id: creator-id }
      {
        base-score: new-base-score,
        subscriber-rating: (get subscriber-rating current-rep),
        content-quality: (get content-quality current-rep),
        activity-score: (get activity-score current-rep),
        final-score: final-score,
        last-updated: stacks-block-height
      }
    )
    (ok final-score)
  )
)

(define-public (update-subscriber-rating (creator-id uint) (rating uint))
  (let
    ((current-rep (default-to 
      { base-score: u50, subscriber-rating: u50, content-quality: u50, activity-score: u50, final-score: u50, last-updated: u0 }
      (map-get? creator-reputation { creator-id: creator-id })))
     (final-score (/ (+ (get base-score current-rep) rating (get content-quality current-rep) (get activity-score current-rep)) u4)))
    
    (asserts! (and (>= rating u0) (<= rating u100)) ERR-INVALID-REPUTATION-SCORE)
    
    (map-set creator-reputation
      { creator-id: creator-id }
      {
        base-score: (get base-score current-rep),
        subscriber-rating: rating,
        content-quality: (get content-quality current-rep),
        activity-score: (get activity-score current-rep),
        final-score: final-score,
        last-updated: stacks-block-height
      }
    )
    (ok final-score)
  )
)

(define-public (update-content-quality (creator-id uint) (quality-score uint))
  (let
    ((current-rep (default-to 
      { base-score: u50, subscriber-rating: u50, content-quality: u50, activity-score: u50, final-score: u50, last-updated: u0 }
      (map-get? creator-reputation { creator-id: creator-id })))
     (final-score (/ (+ (get base-score current-rep) (get subscriber-rating current-rep) quality-score (get activity-score current-rep)) u4)))
    
    (asserts! (and (>= quality-score u0) (<= quality-score u100)) ERR-INVALID-REPUTATION-SCORE)
    
    (map-set creator-reputation
      { creator-id: creator-id }
      {
        base-score: (get base-score current-rep),
        subscriber-rating: (get subscriber-rating current-rep),
        content-quality: quality-score,
        activity-score: (get activity-score current-rep),
        final-score: final-score,
        last-updated: stacks-block-height
      }
    )
    (ok final-score)
  )
)

(define-public (update-activity-score (creator-id uint) (activity-score uint))
  (let
    ((current-rep (default-to 
      { base-score: u50, subscriber-rating: u50, content-quality: u50, activity-score: u50, final-score: u50, last-updated: u0 }
      (map-get? creator-reputation { creator-id: creator-id })))
     (final-score (/ (+ (get base-score current-rep) (get subscriber-rating current-rep) (get content-quality current-rep) activity-score) u4)))
    
    (asserts! (and (>= activity-score u0) (<= activity-score u100)) ERR-INVALID-REPUTATION-SCORE)
    
    (map-set creator-reputation
      { creator-id: creator-id }
      {
        base-score: (get base-score current-rep),
        subscriber-rating: (get subscriber-rating current-rep),
        content-quality: (get content-quality current-rep),
        activity-score: activity-score,
        final-score: final-score,
        last-updated: stacks-block-height
      }
    )
    (ok final-score)
  )
)

(define-read-only (get-creator-verification (creator-id uint))
  (map-get? verified-creators { creator-id: creator-id })
)

(define-read-only (is-creator-verified (creator-id uint))
  (let
    ((verification-data (map-get? verified-creators { creator-id: creator-id })))
    (if (is-some verification-data)
      (> (get expires-at (unwrap-panic verification-data)) stacks-block-height)
      false
    )
  )
)

(define-read-only (get-creator-reputation-score (creator-id uint))
  (let
    ((reputation-data (map-get? creator-reputation { creator-id: creator-id })))
    (if (is-some reputation-data)
      (ok (get final-score (unwrap-panic reputation-data)))
      (ok u50)
    )
  )
)

(define-read-only (get-verification-authority)
  (var-get verification-authority)
)

(define-read-only (get-verifier-permissions (verifier principal))
  (map-get? verifier-permissions { verifier: verifier })
)

(define-read-only (get-creator-reputation-details (creator-id uint))
  (map-get? creator-reputation { creator-id: creator-id })
)

(define-read-only (get-verified-creators-by-type (verification-type (string-ascii 20)))
  (ok "Feature requires iteration over maps - implement with off-chain indexing")
)
