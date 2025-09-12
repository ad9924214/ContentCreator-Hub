;; title: collaborative-content
;; summary: System for creators to collaborate on shared content with revenue splitting

(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-COLLAB (err u301))
(define-constant ERR-ALREADY-JOINED (err u302))
(define-constant ERR-NOT-COLLABORATOR (err u303))
(define-constant ERR-INVALID-SPLIT (err u304))
(define-constant ERR-COLLAB-LOCKED (err u305))
(define-constant ERR-INVALID-STATUS (err u306))

(define-data-var next-collab-id uint u1)
(define-data-var next-proposal-id uint u1)

;; Collaborative project data
(define-map collaborations
  { collab-id: uint }
  {
    title: (string-ascii 128),
    description: (string-utf8 500),
    initiator: principal,
    max-collaborators: uint,
    current-collaborators: uint,
    status: (string-ascii 20),
    created-at: uint,
    deadline: uint,
    total-revenue: uint
  }
)

;; Collaborator details for each project
(define-map collaboration-members
  { collab-id: uint, member: principal }
  {
    creator-id: uint,
    revenue-share: uint,
    contribution-type: (string-ascii 50),
    joined-at: uint,
    status: (string-ascii 20),
    votes-cast: uint
  }
)

;; Content proposals within collaborations
(define-map content-proposals
  { collab-id: uint, proposal-id: uint }
  {
    proposer: principal,
    title: (string-ascii 128),
    description: (string-utf8 500),
    content-url: (string-ascii 256),
    tier-requirement: uint,
    votes-for: uint,
    votes-against: uint,
    voting-deadline: uint,
    status: (string-ascii 20),
    created-at: uint
  }
)

;; Revenue distribution records
(define-map revenue-distributions
  { collab-id: uint }
  {
    total-earned: uint,
    distributed-amount: uint,
    pending-distribution: uint,
    last-distribution: uint,
    distribution-count: uint
  }
)

;; Individual earnings from collaborations
(define-map member-earnings
  { collab-id: uint, member: principal }
  {
    total-earned: uint,
    withdrawn: uint,
    pending-withdrawal: uint,
    last-payment: uint
  }
)

;; Create a new collaborative project
(define-public (create-collaboration 
  (title (string-ascii 128))
  (description (string-utf8 500))
  (max-collaborators uint)
  (deadline uint))
  (let
    (
      (collab-id (var-get next-collab-id))
    )
    
    ;; Validate parameters
    (asserts! (> max-collaborators u1) ERR-INVALID-COLLAB)
    (asserts! (<= max-collaborators u10) ERR-INVALID-COLLAB)
    (asserts! (> deadline stacks-block-height) ERR-INVALID-COLLAB)
    
    ;; Create collaboration
    (map-set collaborations
      { collab-id: collab-id }
      {
        title: title,
        description: description,
        initiator: tx-sender,
        max-collaborators: max-collaborators,
        current-collaborators: u1,
        status: "open",
        created-at: stacks-block-height,
        deadline: deadline,
        total-revenue: u0
      })
    
    ;; Add initiator as first member with 50% share initially
    (map-set collaboration-members
      { collab-id: collab-id, member: tx-sender }
      {
        creator-id: u0,
        revenue-share: u50,
        contribution-type: "initiator",
        joined-at: stacks-block-height,
        status: "active",
        votes-cast: u0
      })
    
    ;; Initialize revenue tracking
    (map-set revenue-distributions
      { collab-id: collab-id }
      {
        total-earned: u0,
        distributed-amount: u0,
        pending-distribution: u0,
        last-distribution: u0,
        distribution-count: u0
      })
    
    (var-set next-collab-id (+ collab-id u1))
    (ok collab-id)
  )
)

;; Join an existing collaboration
(define-public (join-collaboration 
  (collab-id uint)
  (creator-id uint)
  (contribution-type (string-ascii 50)))
  (let
    (
      (collab (unwrap! (map-get? collaborations { collab-id: collab-id }) ERR-INVALID-COLLAB))
      (existing-member (map-get? collaboration-members { collab-id: collab-id, member: tx-sender }))
    )
    
    ;; Validate collaboration is open
    (asserts! (is-eq (get status collab) "open") ERR-COLLAB-LOCKED)
    
    ;; Check if already a member
    (asserts! (is-none existing-member) ERR-ALREADY-JOINED)
    
    ;; Check space available
    (asserts! (< (get current-collaborators collab) (get max-collaborators collab)) ERR-INVALID-COLLAB)
    
    ;; Add member with equal revenue share initially
    (let
      (
        (new-share (/ u100 (+ (get current-collaborators collab) u1)))
      )
      
      (map-set collaboration-members
        { collab-id: collab-id, member: tx-sender }
        {
          creator-id: creator-id,
          revenue-share: new-share,
          contribution-type: contribution-type,
          joined-at: stacks-block-height,
          status: "active",
          votes-cast: u0
        })
      
      ;; Update collaboration member count
      (map-set collaborations
        { collab-id: collab-id }
        (merge collab { current-collaborators: (+ (get current-collaborators collab) u1) }))
      
      (ok true)
    )
  )
)

;; Propose content for the collaboration
(define-public (propose-content 
  (collab-id uint)
  (title (string-ascii 128))
  (description (string-utf8 500))
  (content-url (string-ascii 256))
  (tier-requirement uint))
  (let
    (
      (collab (unwrap! (map-get? collaborations { collab-id: collab-id }) ERR-INVALID-COLLAB))
      (member (unwrap! (map-get? collaboration-members { collab-id: collab-id, member: tx-sender }) 
                       ERR-NOT-COLLABORATOR))
      (proposal-id (var-get next-proposal-id))
      (voting-deadline (+ stacks-block-height u1008)) ;; ~7 days for voting
    )
    
    ;; Validate member status
    (asserts! (is-eq (get status member) "active") ERR-NOT-COLLABORATOR)
    
    ;; Create content proposal
    (map-set content-proposals
      { collab-id: collab-id, proposal-id: proposal-id }
      {
        proposer: tx-sender,
        title: title,
        description: description,
        content-url: content-url,
        tier-requirement: tier-requirement,
        votes-for: u0,
        votes-against: u0,
        voting-deadline: voting-deadline,
        status: "voting",
        created-at: stacks-block-height
      })
    
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

;; Vote on content proposal
(define-public (vote-on-proposal (collab-id uint) (proposal-id uint) (vote-for bool))
  (let
    (
      (proposal (unwrap! (map-get? content-proposals { collab-id: collab-id, proposal-id: proposal-id }) 
                         ERR-INVALID-COLLAB))
      (member (unwrap! (map-get? collaboration-members { collab-id: collab-id, member: tx-sender }) 
                       ERR-NOT-COLLABORATOR))
    )
    
    ;; Validate voting period
    (asserts! (< stacks-block-height (get voting-deadline proposal)) ERR-INVALID-STATUS)
    (asserts! (is-eq (get status proposal) "voting") ERR-INVALID-STATUS)
    (asserts! (is-eq (get status member) "active") ERR-NOT-COLLABORATOR)
    
    ;; Update vote count
    (if vote-for
      (map-set content-proposals
        { collab-id: collab-id, proposal-id: proposal-id }
        (merge proposal { votes-for: (+ (get votes-for proposal) u1) }))
      (map-set content-proposals
        { collab-id: collab-id, proposal-id: proposal-id }
        (merge proposal { votes-against: (+ (get votes-against proposal) u1) })))
    
    ;; Update member vote count
    (map-set collaboration-members
      { collab-id: collab-id, member: tx-sender }
      (merge member { votes-cast: (+ (get votes-cast member) u1) }))
    
    (ok true)
  )
)

;; Distribute revenue among collaborators
(define-public (distribute-revenue (collab-id uint) (total-amount uint))
  (let
    (
      (collab (unwrap! (map-get? collaborations { collab-id: collab-id }) ERR-INVALID-COLLAB))
      (distribution (default-to
        { total-earned: u0, distributed-amount: u0, pending-distribution: u0,
          last-distribution: u0, distribution-count: u0 }
        (map-get? revenue-distributions { collab-id: collab-id })))
    )
    
    ;; Only initiator can trigger distribution initially
    (asserts! (is-eq tx-sender (get initiator collab)) ERR-NOT-AUTHORIZED)
    (asserts! (> total-amount u0) ERR-INVALID-SPLIT)
    
    ;; Update revenue distribution tracking
    (map-set revenue-distributions
      { collab-id: collab-id }
      {
        total-earned: (+ (get total-earned distribution) total-amount),
        distributed-amount: (+ (get distributed-amount distribution) total-amount),
        pending-distribution: u0,
        last-distribution: stacks-block-height,
        distribution-count: (+ (get distribution-count distribution) u1)
      })
    
    ;; Update collaboration total revenue
    (map-set collaborations
      { collab-id: collab-id }
      (merge collab { total-revenue: (+ (get total-revenue collab) total-amount) }))
    
    (ok total-amount)
  )
)

;; Read-only functions
(define-read-only (get-collaboration (collab-id uint))
  (map-get? collaborations { collab-id: collab-id })
)

(define-read-only (get-member-details (collab-id uint) (member principal))
  (map-get? collaboration-members { collab-id: collab-id, member: member })
)

(define-read-only (get-content-proposal (collab-id uint) (proposal-id uint))
  (map-get? content-proposals { collab-id: collab-id, proposal-id: proposal-id })
)

(define-read-only (get-revenue-info (collab-id uint))
  (map-get? revenue-distributions { collab-id: collab-id })
)

(define-read-only (calculate-member-share (collab-id uint) (member principal) (total-revenue uint))
  (let
    (
      (member-data (map-get? collaboration-members { collab-id: collab-id, member: member }))
    )
    (match member-data
      data (ok (/ (* total-revenue (get revenue-share data)) u100))
      ERR-NOT-COLLABORATOR
    )
  )
)
