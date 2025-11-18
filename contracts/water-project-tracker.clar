;; Water Project Tracker Smart Contract
;; Tracks borehole and water project registration, progress, and completion

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-PROJECT-NOT-FOUND (err u101))
(define-constant ERR-PROJECT-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-STATUS (err u103))
(define-constant ERR-INVALID-BUDGET (err u104))
(define-constant ERR-ALREADY-COMPLETED (err u105))
(define-constant ERR-INVALID-LOCATION (err u106))
(define-constant ERR-INVALID-RATING (err u107))
(define-constant ERR-PROJECT-NOT-COMPLETED (err u108))

;; Project status constants
(define-constant STATUS-PLANNING u0)
(define-constant STATUS-DRILLING u1)
(define-constant STATUS-TESTING u2)
(define-constant STATUS-COMPLETED u3)

;; Data variables
(define-data-var project-counter uint u0)
(define-data-var contract-owner principal tx-sender)

;; Data maps
(define-map project-registry
  { project-id: uint }
  {
    name: (string-ascii 100),
    location: (string-ascii 200),
    budget: uint,
    owner: principal,
    created-at: uint,
    project-type: (string-ascii 50),
  }
)

(define-map project-status
  { project-id: uint }
  {
    status: uint,
    updated-at: uint,
    updated-by: principal,
    completion-date: (optional uint),
    validation-notes: (optional (string-ascii 500)),
  }
)

(define-map project-milestones
  {
    project-id: uint,
    milestone: uint,
  }
  {
    description: (string-ascii 200),
    completed: bool,
    completion-date: (optional uint),
  }
)

(define-map project-ratings
  {
    project-id: uint,
    reviewer: principal,
  }
  {
    rating: uint,
    feedback: (string-ascii 500),
  }
)

;; Private functions
(define-private (is-valid-status (status uint))
  (or
    (is-eq status STATUS-PLANNING)
    (or
      (is-eq status STATUS-DRILLING)
      (or
        (is-eq status STATUS-TESTING)
        (is-eq status STATUS-COMPLETED)
      )
    )
  )
)

(define-private (is-project-owner
    (project-id uint)
    (caller principal)
  )
  (match (map-get? project-registry { project-id: project-id })
    project (is-eq (get owner project) caller)
    false
  )
)

(define-private (is-contract-owner (caller principal))
  (is-eq caller (var-get contract-owner))
)

(define-private (is-project-completed (project-id uint))
  (let ((status-info (map-get? project-status { project-id: project-id })))
    (match status-info
      some-status (is-eq (get status some-status) STATUS-COMPLETED)
      false
    )
  )
)

;; Public functions

;; Register a new water project
(define-public (register-project
    (name (string-ascii 100))
    (location (string-ascii 200))
    (budget uint)
    (project-type (string-ascii 50))
  )
  (let ((project-id (+ (var-get project-counter) u1)))
    (asserts! (> (len name) u0) ERR-INVALID-LOCATION)
    (asserts! (> (len location) u0) ERR-INVALID-LOCATION)
    (asserts! (> budget u0) ERR-INVALID-BUDGET)

    ;; Note: Duplicate checking can be implemented at application level if needed

    ;; Register the project
    (map-set project-registry { project-id: project-id } {
      name: name,
      location: location,
      budget: budget,
      owner: tx-sender,
      created-at: block-height,
      project-type: project-type,
    })

    ;; Initialize project status
    (map-set project-status { project-id: project-id } {
      status: STATUS-PLANNING,
      updated-at: block-height,
      updated-by: tx-sender,
      completion-date: none,
      validation-notes: none,
    })

    ;; Update counter
    (var-set project-counter project-id)
    (ok project-id)
  )
)

;; Update project status
(define-public (update-status
    (project-id uint)
    (new-status uint)
  )
  (let (
      (project (unwrap! (map-get? project-registry { project-id: project-id })
        ERR-PROJECT-NOT-FOUND
      ))
      (current-status-info (unwrap! (map-get? project-status { project-id: project-id })
        ERR-PROJECT-NOT-FOUND
      ))
    )
    ;; Validate caller is project owner or contract owner
    (asserts!
      (or
        (is-project-owner project-id tx-sender)
        (is-contract-owner tx-sender)
      )
      ERR-UNAUTHORIZED
    )

    ;; Validate status
    (asserts! (is-valid-status new-status) ERR-INVALID-STATUS)

    ;; Check if already completed
    (asserts! (not (is-eq (get status current-status-info) STATUS-COMPLETED))
      ERR-ALREADY-COMPLETED
    )

    ;; Update status
    (map-set project-status { project-id: project-id }
      (merge current-status-info {
        status: new-status,
        updated-at: block-height,
        updated-by: tx-sender,
      })
    )
    (ok true)
  )
)

;; Record project completion with validation
(define-public (record-completion
    (project-id uint)
    (validation-notes (string-ascii 500))
  )
  (let (
      (project (unwrap! (map-get? project-registry { project-id: project-id })
        ERR-PROJECT-NOT-FOUND
      ))
      (current-status-info (unwrap! (map-get? project-status { project-id: project-id })
        ERR-PROJECT-NOT-FOUND
      ))
    )
    ;; Validate caller
    (asserts!
      (or
        (is-project-owner project-id tx-sender)
        (is-contract-owner tx-sender)
      )
      ERR-UNAUTHORIZED
    )

    ;; Check if already completed
    (asserts! (not (is-eq (get status current-status-info) STATUS-COMPLETED))
      ERR-ALREADY-COMPLETED
    )

    ;; Update to completed status
    (map-set project-status { project-id: project-id }
      (merge current-status-info {
        status: STATUS-COMPLETED,
        updated-at: block-height,
        updated-by: tx-sender,
        completion-date: (some block-height),
        validation-notes: (some validation-notes),
      })
    )
    (ok true)
  )
)

;; Add milestone to project
(define-public (add-milestone
    (project-id uint)
    (milestone-id uint)
    (description (string-ascii 200))
  )
  (let ((project (unwrap! (map-get? project-registry { project-id: project-id })
      ERR-PROJECT-NOT-FOUND
    )))
    ;; Validate caller
    (asserts!
      (or
        (is-project-owner project-id tx-sender)
        (is-contract-owner tx-sender)
      )
      ERR-UNAUTHORIZED
    )

    ;; Add milestone
    (map-set project-milestones {
      project-id: project-id,
      milestone: milestone-id,
    } {
      description: description,
      completed: false,
      completion-date: none,
    })
    (ok true)
  )
)

;; Complete milestone
(define-public (complete-milestone
    (project-id uint)
    (milestone-id uint)
  )
  (let (
      (project (unwrap! (map-get? project-registry { project-id: project-id })
        ERR-PROJECT-NOT-FOUND
      ))
      (milestone-info (unwrap!
        (map-get? project-milestones {
          project-id: project-id,
          milestone: milestone-id,
        })
        ERR-PROJECT-NOT-FOUND
      ))
    )
    ;; Validate caller
    (asserts!
      (or
        (is-project-owner project-id tx-sender)
        (is-contract-owner tx-sender)
      )
      ERR-UNAUTHORIZED
    )

    ;; Complete milestone
    (map-set project-milestones {
      project-id: project-id,
      milestone: milestone-id,
    }
      (merge milestone-info {
        completed: true,
        completion-date: (some block-height),
      })
    )
    (ok true)
  )
)

(define-public (rate-project
    (project-id uint)
    (rating uint)
    (feedback (string-ascii 500))
  )
  (let (
      (project (unwrap! (map-get? project-registry { project-id: project-id })
        ERR-PROJECT-NOT-FOUND
      ))
      (completed (is-project-completed project-id))
      (valid-min (>= rating u1))
      (valid-max (<= rating u5))
    )
    (begin
      (asserts! completed ERR-PROJECT-NOT-COMPLETED)
      (asserts! (and valid-min valid-max) ERR-INVALID-RATING)
      (map-set project-ratings {
        project-id: project-id,
        reviewer: tx-sender,
      } {
        rating: rating,
        feedback: feedback,
      })
      (ok true)
    )
  )
)

;; Read-only functions

;; Get project information
(define-read-only (get-project-info (project-id uint))
  (match (map-get? project-registry { project-id: project-id })
    project (some project)
    none
  )
)

;; Get project status
(define-read-only (get-project-status (project-id uint))
  (match (map-get? project-status { project-id: project-id })
    status (some status)
    none
  )
)

;; Get milestone information
(define-read-only (get-milestone-info
    (project-id uint)
    (milestone-id uint)
  )
  (match (map-get? project-milestones {
    project-id: project-id,
    milestone: milestone-id,
  })
    milestone (some milestone)
    none
  )
)

(define-read-only (get-project-rating-by-reviewer
    (project-id uint)
    (reviewer principal)
  )
  (match (map-get? project-ratings {
    project-id: project-id,
    reviewer: reviewer,
  })
    rating (some rating)
    none
  )
)

;; Get current project counter
(define-read-only (get-project-counter)
  (var-get project-counter)
)

;; Get contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; Note: Duplicate checking removed to avoid interdependent functions
;; This can be implemented at the application layer if needed

;; Get status name as string
(define-read-only (get-status-name (status uint))
  (if (is-eq status STATUS-PLANNING)
    "Planning"
    (if (is-eq status STATUS-DRILLING)
      "Drilling"
      (if (is-eq status STATUS-TESTING)
        "Testing"
        (if (is-eq status STATUS-COMPLETED)
          "Completed"
          "Unknown"
        )
      )
    )
  )
)
