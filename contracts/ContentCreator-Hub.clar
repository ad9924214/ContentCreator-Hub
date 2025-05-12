;; title: ContentCreator-Hub
;; version: 1.0
;; summary: Decentralized Patreon-style platform for content creators
;; description: A platform that allows creators to set up multi-tier subscriptions, schedule content, and view analytics. Subscribers can access exclusive content by meeting token requirements.

;; traits


;; token definitions
;; (Using SIP-010 compliant tokens for subscriptions)

;; constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-TIER (err u101))
(define-constant ERR-ALREADY-SUBSCRIBED (err u102))
(define-constant ERR-NOT-SUBSCRIBED (err u103))
(define-constant ERR-INVALID-CONTENT (err u104))
(define-constant ERR-INSUFFICIENT-TOKENS (err u105))

;; data vars
(define-data-var next-creator-id uint u1)
(define-data-var next-content-id uint u1)

;; data maps
;; Creator profiles
(define-map creators
  { creator-id: uint }
  {
    principal: principal,
    name: (string-ascii 64),
    description: (string-utf8 500),
    total-subscribers: uint,
    created-at: uint
  }
)

;; Creator tiers
(define-map subscription-tiers
  { creator-id: uint, tier-id: uint }
  {
    name: (string-ascii 64),
    description: (string-utf8 500),
    token-contract: principal,
    token-amount: uint,
    duration-days: uint
  }
)

;; Subscriber data
(define-map subscriptions
  { subscriber: principal, creator-id: uint }
  {
    tier-id: uint,
    expires-at: uint,
    auto-renew: bool
  }
)

;; Content items
(define-map content-items
  { content-id: uint }
  {
    creator-id: uint,
    title: (string-ascii 128),
    description: (string-utf8 1000),
    content-url: (string-ascii 256),
    min-tier-id: uint,
    publish-at: uint,
    created-at: uint
  }
)

;; Analytics - views per content
(define-map content-views
  { content-id: uint }
  { view-count: uint }
)

;; Analytics - subscribers per creator per tier
(define-map tier-analytics
  { creator-id: uint, tier-id: uint }
  { subscriber-count: uint }
)

;; public functions
;; Creator management
(define-public (register-creator (name (string-ascii 64)) (description (string-utf8 500)))
  (let
    ((creator-id (var-get next-creator-id)))
    (map-set creators
      { creator-id: creator-id }
      {
        principal: tx-sender,
        name: name,
        description: description,
        total-subscribers: u0,
        created-at: stacks-block-height
      }
    )
    (var-set next-creator-id (+ creator-id u1))
    (ok creator-id)
  )
)

(define-public (update-creator-profile (creator-id uint) (name (string-ascii 64)) (description (string-utf8 500)))
  (let
    ((creator-data (unwrap! (map-get? creators { creator-id: creator-id }) ERR-INVALID-TIER)))
    (asserts! (is-eq tx-sender (get principal creator-data)) ERR-NOT-AUTHORIZED)
    (map-set creators
      { creator-id: creator-id }
      (merge creator-data { name: name, description: description })
    )
    (ok true)
  )
)

;; Tier management
(define-public (create-subscription-tier 
    (creator-id uint) 
    (tier-id uint) 
    (name (string-ascii 64)) 
    (description (string-utf8 500))
    (token-contract principal)
    (token-amount uint)
    (duration-days uint)
  )
  (let
    ((creator-data (unwrap! (map-get? creators { creator-id: creator-id }) ERR-INVALID-TIER)))
    (asserts! (is-eq tx-sender (get principal creator-data)) ERR-NOT-AUTHORIZED)
    (map-set subscription-tiers
      { creator-id: creator-id, tier-id: tier-id }
      {
        name: name,
        description: description,
        token-contract: token-contract,
        token-amount: token-amount,
        duration-days: duration-days
      }
    )
    (ok true)
  )
)

;; Subscription management
(define-public (subscribe-to-creator (creator-id uint) (tier-id uint) (auto-renew bool) (token-contract principal))
  (let
    ((creator-data (unwrap! (map-get? creators { creator-id: creator-id }) ERR-INVALID-TIER))
     (tier-data (unwrap! (map-get? subscription-tiers { creator-id: creator-id, tier-id: tier-id }) ERR-INVALID-TIER))
     (existing-sub (map-get? subscriptions { subscriber: tx-sender, creator-id: creator-id }))
     (token-amount (get token-amount tier-data))
     (duration (get duration-days tier-data))
     (expires-at (+ stacks-block-height (* duration u144))) ;; ~144 blocks per day
     (tier-stats (default-to { subscriber-count: u0 } (map-get? tier-analytics { creator-id: creator-id, tier-id: tier-id }))))
    
    ;; Check if already subscribed
    (asserts! (is-none existing-sub) ERR-ALREADY-SUBSCRIBED)
    
    ;; Check if token contract matches
    (asserts! (is-eq token-contract (get token-contract tier-data)) ERR-INVALID-TIER)
    
    ;; Transfer tokens from subscriber to creator
    
    ;; Update subscription
    (map-set subscriptions
      { subscriber: tx-sender, creator-id: creator-id }
      {
        tier-id: tier-id,
        expires-at: expires-at,
        auto-renew: auto-renew
      }
    )
    
    ;; Update analytics
    (map-set tier-analytics
      { creator-id: creator-id, tier-id: tier-id }
      { subscriber-count: (+ (get subscriber-count tier-stats) u1) }
    )
    
    ;; Update creator total subscribers
    (map-set creators
      { creator-id: creator-id }
      (merge creator-data { total-subscribers: (+ (get total-subscribers creator-data) u1) })
    )
    
    (ok expires-at)
  )
)

(define-public (renew-subscription (creator-id uint) (token-contract principal))
  (let
    ((sub-data (unwrap! (map-get? subscriptions { subscriber: tx-sender, creator-id: creator-id }) ERR-NOT-SUBSCRIBED))
     (tier-id (get tier-id sub-data))
     (tier-data (unwrap! (map-get? subscription-tiers { creator-id: creator-id, tier-id: tier-id }) ERR-INVALID-TIER))
     (creator-data (unwrap! (map-get? creators { creator-id: creator-id }) ERR-INVALID-TIER))
     (token-amount (get token-amount tier-data))
     (duration (get duration-days tier-data))
     (expires-at (+ stacks-block-height (* duration u144))))
        
    ;; Update subscription
    (map-set subscriptions
      { subscriber: tx-sender, creator-id: creator-id }
      (merge sub-data { expires-at: expires-at })
    )
    
    (ok expires-at)
  )
)

(define-public (cancel-subscription (creator-id uint))
  (let
    ((sub-data (unwrap! (map-get? subscriptions { subscriber: tx-sender, creator-id: creator-id }) ERR-NOT-SUBSCRIBED))
     (tier-id (get tier-id sub-data))
     (tier-stats (default-to { subscriber-count: u0 } (map-get? tier-analytics { creator-id: creator-id, tier-id: tier-id })))
     (creator-data (unwrap! (map-get? creators { creator-id: creator-id }) ERR-INVALID-TIER)))
    
    ;; Update subscription
    (map-delete subscriptions { subscriber: tx-sender, creator-id: creator-id })
    
    ;; Update analytics
    (map-set tier-analytics
      { creator-id: creator-id, tier-id: tier-id }
      { subscriber-count: (- (get subscriber-count tier-stats) u1) }
    )
    
    ;; Update creator total subscribers
    (map-set creators
      { creator-id: creator-id }
      (merge creator-data { total-subscribers: (- (get total-subscribers creator-data) u1) })
    )
    
    (ok true)
  )
)

;; Content management
(define-public (create-content 
    (creator-id uint) 
    (title (string-ascii 128)) 
    (description (string-utf8 1000))
    (content-url (string-ascii 256))
    (min-tier-id uint)
    (publish-at uint)
  )
  (let
    ((creator-data (unwrap! (map-get? creators { creator-id: creator-id }) ERR-INVALID-TIER))
     (content-id (var-get next-content-id)))
    
    ;; Verify creator
    (asserts! (is-eq tx-sender (get principal creator-data)) ERR-NOT-AUTHORIZED)
    
    ;; Verify tier exists
    (asserts! (is-some (map-get? subscription-tiers { creator-id: creator-id, tier-id: min-tier-id })) ERR-INVALID-TIER)
    
    ;; Create content
    (map-set content-items
      { content-id: content-id }
      {
        creator-id: creator-id,
        title: title,
        description: description,
        content-url: content-url,
        min-tier-id: min-tier-id,
        publish-at: publish-at,
        created-at: stacks-block-height
      }
    )
    
    ;; Initialize views
    (map-set content-views
      { content-id: content-id }
      { view-count: u0 }
    )
    
    ;; Increment content ID
    (var-set next-content-id (+ content-id u1))
    
    (ok content-id)
  )
)

(define-public (view-content (content-id uint))
  (let
    ((content (unwrap! (map-get? content-items { content-id: content-id }) ERR-INVALID-CONTENT))
     (creator-id (get creator-id content))
     (min-tier-id (get min-tier-id content))
     (publish-at (get publish-at content))
     (sub-data (map-get? subscriptions { subscriber: tx-sender, creator-id: creator-id }))
     (views (default-to { view-count: u0 } (map-get? content-views { content-id: content-id }))))
    
    ;; Check if content is published
    (asserts! (<= publish-at stacks-block-height) ERR-INVALID-CONTENT)
    
    ;; Check if subscriber has access
    (asserts! (or 
      ;; Creator can always view their content
      (is-eq tx-sender (get principal (unwrap! (map-get? creators { creator-id: creator-id }) ERR-INVALID-TIER)))
      ;; Subscriber has required tier
      (and 
        (is-some sub-data) 
        (>= (get tier-id (unwrap! sub-data ERR-NOT-SUBSCRIBED)) min-tier-id)
        (>= (get expires-at (unwrap! sub-data ERR-NOT-SUBSCRIBED)) stacks-block-height)
      )
    ) ERR-NOT-AUTHORIZED)
    
    ;; Update view count
    (map-set content-views
      { content-id: content-id }
      { view-count: (+ (get view-count views) u1) }
    )
    
    (ok (get content-url content))
  )
)

;; read only functions
(define-read-only (get-creator-profile (creator-id uint))
  (map-get? creators { creator-id: creator-id })
)

(define-read-only (get-subscription-tier (creator-id uint) (tier-id uint))
  (map-get? subscription-tiers { creator-id: creator-id, tier-id: tier-id })
)

(define-read-only (get-subscription-status (subscriber principal) (creator-id uint))
  (map-get? subscriptions { subscriber: subscriber, creator-id: creator-id })
)

(define-read-only (get-content-details (content-id uint))
  (map-get? content-items { content-id: content-id })
)

(define-read-only (get-content-views (content-id uint))
  (default-to { view-count: u0 } (map-get? content-views { content-id: content-id }))
)

(define-read-only (get-tier-subscribers (creator-id uint) (tier-id uint))
  (default-to { subscriber-count: u0 } (map-get? tier-analytics { creator-id: creator-id, tier-id: tier-id }))
)

(define-read-only (can-access-content (subscriber principal) (content-id uint))
  (let
    ((content (unwrap! (map-get? content-items { content-id: content-id }) false))
     (creator-id (get creator-id content))
     (min-tier-id (get min-tier-id content))
     (publish-at (get publish-at content))
     (sub-data (map-get? subscriptions { subscriber: subscriber, creator-id: creator-id })))
    
    (and
      ;; Content is published
      (<= publish-at stacks-block-height)
      ;; Subscriber has access
      (or 

        (and 
          (is-some sub-data) 
          (>= (get tier-id (unwrap! sub-data false)) min-tier-id)
          (>= (get expires-at (unwrap! sub-data false)) stacks-block-height)
        )
      )
    )
  )
)

;; Add to constants
(define-constant ERR-COMMENT-NOT-FOUND (err u106))

;; Add new data map for comments
(define-map content-comments
  { comment-id: uint, content-id: uint }
  {
    author: principal,
    text: (string-utf8 500),
    created-at: uint
  }
)

;; Add data var for comment IDs
(define-data-var next-comment-id uint u1)

;; Add function to create comments
(define-public (add-comment (content-id uint) (text (string-utf8 500)))
  (let
    ((comment-id (var-get next-comment-id))
     (content (unwrap! (map-get? content-items { content-id: content-id }) ERR-INVALID-CONTENT)))
    
    ;; Check if content exists and is published
    (asserts! (<= (get publish-at content) stacks-block-height) ERR-INVALID-CONTENT)
    
    (map-set content-comments
      { comment-id: comment-id, content-id: content-id }
      {
        author: tx-sender,
        text: text,
        created-at: stacks-block-height
      }
    )
    (var-set next-comment-id (+ comment-id u1))
    (ok comment-id)
  )
)


;; Add to constants
(define-constant ERR-INVALID-RATING (err u107))

;; Add new data map for ratings
(define-map content-ratings
  { content-id: uint }
  {
    total-rating: uint,
    rating-count: uint,
    average-rating: uint
  }
)

;; Add function to rate content
(define-public (rate-content (content-id uint) (rating uint))
  (let
    ((content (unwrap! (map-get? content-items { content-id: content-id }) ERR-INVALID-CONTENT))
     (current-ratings (default-to { total-rating: u0, rating-count: u0, average-rating: u0 } 
                     (map-get? content-ratings { content-id: content-id }))))
    
    ;; Validate rating (1-5)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
    
    (map-set content-ratings
      { content-id: content-id }
      {
        total-rating: (+ (get total-rating current-ratings) rating),
        rating-count: (+ (get rating-count current-ratings) u1),
        average-rating: (/ (+ (get total-rating current-ratings) rating) 
                         (+ (get rating-count current-ratings) u1))
      }
    )
    (ok true)
  )
)


;; Add new data map for tips
(define-map creator-tips
  { creator-id: uint }
  {
    total-tips: uint,
    tip-count: uint
  }
)

;; Add function to send tips
(define-public (send-tip (creator-id uint) (amount uint) (token-contract principal))
  (let
    ((creator-data (unwrap! (map-get? creators { creator-id: creator-id }) ERR-INVALID-TIER))
     (tip-data (default-to { total-tips: u0, tip-count: u0 } 
               (map-get? creator-tips { creator-id: creator-id }))))
    
    ;; Update tip statistics
    (map-set creator-tips
      { creator-id: creator-id }
      {
        total-tips: (+ (get total-tips tip-data) amount),
        tip-count: (+ (get tip-count tip-data) u1)
      }
    )
    (ok true)
  )
)


;; Add new data map for revenue tracking
(define-map creator-revenue
  { creator-id: uint }
  {
    total-earnings: uint,
    subscription-revenue: uint,
    tip-revenue: uint,
    last-payout: uint
  }
)

;; Add function to track revenue
(define-public (track-creator-earnings (creator-id uint) (amount uint) (revenue-type (string-ascii 20)))
  (let
    ((revenue-data (default-to { total-earnings: u0, subscription-revenue: u0, 
                               tip-revenue: u0, last-payout: u0 }
                  (map-get? creator-revenue { creator-id: creator-id }))))
    
    (map-set creator-revenue
      { creator-id: creator-id }
      (merge revenue-data 
        {
          total-earnings: (+ (get total-earnings revenue-data) amount),
          subscription-revenue: (if (is-eq revenue-type "subscription")
                                  (+ (get subscription-revenue revenue-data) amount)
                                  (get subscription-revenue revenue-data)),
          tip-revenue: (if (is-eq revenue-type "tip")
                          (+ (get tip-revenue revenue-data) amount)
                          (get tip-revenue revenue-data))
        }
      )
    )
    (ok true)
  )
)


;; Add new data map for scheduled content
(define-map content-schedule
  { creator-id: uint }
  {
    upcoming-contents: (list 20 uint),
    next-publish-height: uint
  }
)

;; Add function to schedule content
(define-public (schedule-content (creator-id uint) (content-id uint) (publish-height uint))
  (let
    ((schedule-data (default-to { upcoming-contents: (list ), next-publish-height: u0 }
                   (map-get? content-schedule { creator-id: creator-id }))))
    
    (map-set content-schedule
      { creator-id: creator-id }
      {
        upcoming-contents: (unwrap! (as-max-len? 
       (append (get upcoming-contents schedule-data) content-id)
                                    u20)
                                  ERR-NOT-AUTHORIZED),
        next-publish-height: publish-height
      }
    )
    (ok true)
  )
)


;; Add new data map for notifications
(define-map subscriber-notifications
  { subscriber: principal }
  {
    notifications: (list 50 {
      content-id: uint,
      creator-id: uint,
      notification-type: (string-ascii 20),
      created-at: uint,
      read: bool
    })
  }
)

;; Add function to create notification
(define-public (create-notification (subscriber principal) (content-id uint) 
    (creator-id uint) (notification-type (string-ascii 20)))
  (let
    ((current-notifications (default-to { notifications: (list ) }
        (map-get? subscriber-notifications { subscriber: subscriber }))))
    
    (map-set subscriber-notifications
      { subscriber: subscriber }
      {
        notifications: (unwrap! (as-max-len? 
          (append (get notifications current-notifications)
            {
              content-id: content-id,
              creator-id: creator-id,
              notification-type: notification-type,
              created-at: stacks-block-height,
              read: false
            })
          u50)
        ERR-NOT-AUTHORIZED)
      }
    )
    (ok true)
  )
)


(define-constant ERR-INVALID-COLLABORATION (err u108))
(define-constant ERR-ALREADY-COLLABORATING (err u109))

(define-map collaborations
  { collaboration-id: uint }
  {
    primary-creator: uint,
    collaborator: uint,
    revenue-split: uint,
    start-height: uint,
    end-height: uint,
    status: (string-ascii 20)
  }
)

(define-data-var next-collaboration-id uint u1)

(define-public (create-collaboration 
    (primary-creator-id uint)
    (collaborator-id uint)
    (revenue-split uint)
    (duration uint)
  )
  (let
    ((collaboration-id (var-get next-collaboration-id))
     (primary-creator (unwrap! (map-get? creators { creator-id: primary-creator-id }) ERR-INVALID-TIER))
     (end-height (+ stacks-block-height duration)))
    
    (asserts! (is-eq tx-sender (get principal primary-creator)) ERR-NOT-AUTHORIZED)
    (asserts! (<= revenue-split u100) ERR-INVALID-COLLABORATION)
    
    (map-set collaborations
      { collaboration-id: collaboration-id }
      {
        primary-creator: primary-creator-id,
        collaborator: collaborator-id,
        revenue-split: revenue-split,
        start-height: stacks-block-height,
        end-height: end-height,
        status: "active"
      }
    )
    
    (var-set next-collaboration-id (+ collaboration-id u1))
    (ok collaboration-id)
  )
)


(define-constant ERR-INVALID-BUNDLE (err u110))
(define-constant ERR-BUNDLE-LIMIT-REACHED (err u111))

(define-map content-bundles
  { bundle-id: uint }
  {
    creator-id: uint,
    name: (string-ascii 64),
    description: (string-utf8 500),
    content-ids: (list 10 uint),
    price: uint,
    valid-until: uint
  }
)

(define-data-var next-bundle-id uint u1)

(define-public (create-content-bundle
    (creator-id uint)
    (name (string-ascii 64))
    (description (string-utf8 500))
    (content-ids (list 10 uint))
    (price uint)
    (duration uint)
  )
  (let
    ((bundle-id (var-get next-bundle-id))
     (creator-data (unwrap! (map-get? creators { creator-id: creator-id }) ERR-INVALID-TIER))
     (valid-until (+ stacks-block-height duration)))
    
    (asserts! (is-eq tx-sender (get principal creator-data)) ERR-NOT-AUTHORIZED)
    
    (map-set content-bundles
      { bundle-id: bundle-id }
      {
        creator-id: creator-id,
        name: name,
        description: description,
        content-ids: content-ids,
        price: price,
        valid-until: valid-until
      }
    )
    
    (var-set next-bundle-id (+ bundle-id u1))
    (ok bundle-id)
  )
)