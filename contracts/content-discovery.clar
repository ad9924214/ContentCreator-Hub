;; Content Discovery Engine
;; Provides personalized content recommendations, trending systems, and discovery features

;; Error constants
(define-constant ERR-INVALID-CATEGORY (err u300))
(define-constant ERR-PREFERENCE-NOT-FOUND (err u301))
(define-constant ERR-INVALID-SEARCH-PARAMS (err u302))
(define-constant ERR-TRENDING-CALCULATION-FAILED (err u303))
(define-constant ERR-RECOMMENDATION-FAILED (err u304))

;; Data variables for tracking system metrics
(define-data-var total-interactions uint u0)
(define-data-var trending-window-blocks uint u1008) ;; ~7 days worth of blocks
(define-data-var recommendation-decay-factor uint u95) ;; 95% - preference decay rate

;; Content categories for better discovery
(define-map content-categories
  { content-id: uint }
  {
    primary-category: (string-ascii 32),
    secondary-categories: (list 5 (string-ascii 32)),
    tags: (list 10 (string-ascii 24)),
    language: (string-ascii 8),
    target-audience: (string-ascii 16)
  }
)

;; User interaction tracking for personalization
(define-map user-interactions
  { user: principal, content-id: uint }
  {
    interaction-type: (string-ascii 16), ;; "view", "like", "comment", "share"
    interaction-count: uint,
    first-interaction: uint,
    last-interaction: uint,
    engagement-score: uint
  }
)

;; User preference profiles learned from interactions
(define-map user-preferences
  { user: principal }
  {
    preferred-categories: (list 10 (string-ascii 32)),
    category-scores: (list 10 uint),
    preferred-creators: (list 20 uint),
    content-freshness-preference: uint, ;; 0-100: preference for new vs established content
    interaction-frequency: uint,
    last-updated: uint
  }
)

;; Content trending metrics
(define-map content-trending
  { content-id: uint }
  {
    trending-score: uint,
    view-velocity: uint, ;; views per block
    engagement-rate: uint,
    share-count: uint,
    trending-since: uint,
    peak-score: uint
  }
)

;; Discovery feed configurations
(define-map discovery-feeds
  { user: principal }
  {
    feed-type: (string-ascii 16), ;; "trending", "personalized", "following", "mixed"
    last-generated: uint,
    feed-content: (list 50 uint),
    refresh-frequency: uint
  }
)

;; Search index for content discovery
(define-map search-index
  { search-term: (string-ascii 64) }
  {
    matching-content: (list 100 uint),
    search-count: uint,
    last-searched: uint
  }
)

;; Content recommendation scores
(define-map content-recommendations
  { user: principal, content-id: uint }
  {
    recommendation-score: uint,
    reason-code: (string-ascii 32), ;; "trending", "similar-interest", "creator-follow"
    calculated-at: uint,
    confidence-level: uint
  }
)

;; Track content interaction for trending calculations
(define-public (record-content-interaction 
    (content-id uint) 
    (interaction-type (string-ascii 16))
    (engagement-weight uint)
  )
  (let
    ((existing-interaction (map-get? user-interactions { user: tx-sender, content-id: content-id }))
     (current-interactions (var-get total-interactions))
     (interaction-score (+ engagement-weight u10)))
    
    ;; Update or create user interaction record
    (map-set user-interactions
      { user: tx-sender, content-id: content-id }
      (if (is-some existing-interaction)
        (let ((current (unwrap-panic existing-interaction)))
          {
            interaction-type: interaction-type,
            interaction-count: (+ (get interaction-count current) u1),
            first-interaction: (get first-interaction current),
            last-interaction: stacks-block-height,
            engagement-score: (+ (get engagement-score current) interaction-score)
          })
        {
          interaction-type: interaction-type,
          interaction-count: u1,
          first-interaction: stacks-block-height,
          last-interaction: stacks-block-height,
          engagement-score: interaction-score
        }
      )
    )
    
    ;; Update global interaction counter
    (var-set total-interactions (+ current-interactions u1))
    
    ;; Trigger trending score update
    (unwrap! (update-trending-score content-id) ERR-TRENDING-CALCULATION-FAILED)
    
    ;; Update user preferences based on interaction
    (unwrap! (update-user-preferences tx-sender content-id interaction-type) ERR-PREFERENCE-NOT-FOUND)
    
    (ok true)
  )
)

;; Categorize content for better discovery
(define-public (categorize-content
    (content-id uint)
    (primary-category (string-ascii 32))
    (secondary-categories (list 5 (string-ascii 32)))
    (tags (list 10 (string-ascii 24)))
    (language (string-ascii 8))
    (target-audience (string-ascii 16))
  )
  (begin
    ;; Validate that content exists (this would typically check the main contract)
    (asserts! (> content-id u0) ERR-INVALID-CATEGORY)
    
    (map-set content-categories
      { content-id: content-id }
      {
        primary-category: primary-category,
        secondary-categories: secondary-categories,
        tags: tags,
        language: language,
        target-audience: target-audience
      }
    )
    
    ;; Update search index for new categories and tags
    (unwrap! (update-search-index primary-category content-id) ERR-INVALID-SEARCH-PARAMS)
    
    (ok true)
  )
)

;; Update trending score based on recent interactions
(define-public (update-trending-score (content-id uint))
  (let
    ((current-trending (default-to 
      { trending-score: u0, view-velocity: u0, engagement-rate: u0, share-count: u0, trending-since: stacks-block-height, peak-score: u0 }
      (map-get? content-trending { content-id: content-id })))
     (trending-window (var-get trending-window-blocks))
     (recent-cutoff (- stacks-block-height trending-window))
     ;; Calculate velocity based on recent interactions (simplified calculation)
     (velocity-score (calculate-velocity content-id recent-cutoff))
     (new-trending-score (+ velocity-score (/ (get engagement-rate current-trending) u2))))
    
    (map-set content-trending
      { content-id: content-id }
      {
        trending-score: new-trending-score,
        view-velocity: velocity-score,
        engagement-rate: (get engagement-rate current-trending),
        share-count: (get share-count current-trending),
        trending-since: (if (> new-trending-score (get trending-score current-trending))
                          stacks-block-height
                          (get trending-since current-trending)),
        peak-score: (if (> new-trending-score (get peak-score current-trending))
                      new-trending-score
                      (get peak-score current-trending))
      }
    )
    
    (ok new-trending-score)
  )
)

;; Generate personalized content recommendations
(define-public (generate-recommendations (user principal) (max-recommendations uint))
  (let
    ((user-prefs (map-get? user-preferences { user: user }))
     (recommendation-list (create-recommendation-list user max-recommendations)))
    
    (if (is-some user-prefs)
      (begin
        ;; Create personalized feed based on preferences
        (map-set discovery-feeds
          { user: user }
          {
            feed-type: "personalized",
            last-generated: stacks-block-height,
            feed-content: recommendation-list,
            refresh-frequency: u144 ;; ~1 day
          }
        )
        (ok recommendation-list)
      )
      ;; Return trending content for new users
      (ok (get-trending-content max-recommendations))
    )
  )
)

;; Update user preferences based on interactions
(define-public (update-user-preferences 
    (user principal) 
    (content-id uint) 
    (interaction-type (string-ascii 16))
  )
  (let
    ((current-prefs (default-to 
      { 
        preferred-categories: (list "general"),
        category-scores: (list u50),
        preferred-creators: (list ),
        content-freshness-preference: u50,
        interaction-frequency: u0,
        last-updated: stacks-block-height
      }
      (map-get? user-preferences { user: user })))
     (content-category (map-get? content-categories { content-id: content-id }))
     (decay-factor (var-get recommendation-decay-factor)))
    
    (if (is-some content-category)
      (let
        ((category (get primary-category (unwrap-panic content-category)))
         (updated-frequency (+ (get interaction-frequency current-prefs) u1)))
        
        (map-set user-preferences
          { user: user }
          {
            preferred-categories: (update-category-preference 
              (get preferred-categories current-prefs) category),
            category-scores: (update-category-scores 
              (get category-scores current-prefs) u10),
            preferred-creators: (get preferred-creators current-prefs),
            content-freshness-preference: (get content-freshness-preference current-prefs),
            interaction-frequency: updated-frequency,
            last-updated: stacks-block-height
          }
        )
        (ok true)
      )
      (ok false)
    )
  )
)

;; Search content by various parameters
(define-public (search-content 
    (search-term (string-ascii 64))
    (category-filter (optional (string-ascii 32)))
    (language-filter (optional (string-ascii 8)))
    (max-results uint)
  )
  (let
    ((search-results (get-search-results search-term category-filter language-filter max-results)))
    
    ;; Update search index
    (unwrap! (update-search-index search-term u0) ERR-INVALID-SEARCH-PARAMS)
    
    (ok search-results)
  )
)

;; Helper function to calculate content velocity
(define-private (calculate-velocity (content-id uint) (since-block uint))
  (let
    ((base-velocity u10)) ;; Simplified calculation
    base-velocity
  )
)

;; Helper function to create recommendation list
(define-private (create-recommendation-list (user principal) (max-count uint))
  (let
    ((sample-recommendations (list u1 u2 u3 u4 u5))) ;; Simplified - would be more complex
    sample-recommendations
  )
)

;; Helper function to get trending content
(define-private (get-trending-content (max-count uint))
  (let
    ((trending-list (list u1 u2 u3))) ;; Simplified - would calculate from trending scores
    trending-list
  )
)

;; Helper function to update category preferences
(define-private (update-category-preference 
    (current-categories (list 10 (string-ascii 32))) 
    (new-category (string-ascii 32))
  )
  (if (is-eq (len current-categories) u0)
    (list new-category)
    current-categories ;; Simplified - would actually update the list
  )
)

;; Helper function to update category scores
(define-private (update-category-scores 
    (current-scores (list 10 uint)) 
    (score-boost uint)
  )
  (if (is-eq (len current-scores) u0)
    (list score-boost)
    current-scores ;; Simplified - would actually update scores
  )
)

;; Helper function to update search index
(define-private (update-search-index (term (string-ascii 64)) (content-id uint))
  (let
    ((current-index (default-to 
      { matching-content: (list ), search-count: u0, last-searched: u0 }
      (map-get? search-index { search-term: term }))))
    
    (map-set search-index
      { search-term: term }
      {
        matching-content: (get matching-content current-index),
        search-count: (+ (get search-count current-index) u1),
        last-searched: stacks-block-height
      }
    )
    (ok true)
  )
)

;; Helper function to get search results
(define-private (get-search-results 
    (term (string-ascii 64))
    (category-filter (optional (string-ascii 32)))
    (language-filter (optional (string-ascii 8)))
    (max-results uint)
  )
  (let
    ((search-data (map-get? search-index { search-term: term })))
    (if (is-some search-data)
      (get matching-content (unwrap-panic search-data))
      (list ) ;; Empty list if no results
    )
  )
)

;; Read-only functions for querying discovery data

(define-read-only (get-content-category (content-id uint))
  (map-get? content-categories { content-id: content-id })
)

(define-read-only (get-user-preferences (user principal))
  (map-get? user-preferences { user: user })
)

(define-read-only (get-content-trending-data (content-id uint))
  (map-get? content-trending { content-id: content-id })
)

(define-read-only (get-user-discovery-feed (user principal))
  (map-get? discovery-feeds { user: user })
)

(define-read-only (get-content-recommendation (user principal) (content-id uint))
  (map-get? content-recommendations { user: user, content-id: content-id })
)

(define-read-only (get-trending-window-blocks)
  (var-get trending-window-blocks)
)

(define-read-only (get-total-platform-interactions)
  (var-get total-interactions)
)

(define-read-only (get-search-statistics (term (string-ascii 64)))
  (map-get? search-index { search-term: term })
)

