(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-status (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-project-exists (err u104))

(define-map projects
    { project-id: uint }
    {
        name: (string-ascii 100),
        location: (string-ascii 100),
        target-amount: uint,
        current-amount: uint,
        status: (string-ascii 20),
        owner: principal,
        start-height: uint,
        completion-height: uint,
    }
)

(define-map milestones
    {
        project-id: uint,
        milestone-id: uint,
    }
    {
        description: (string-ascii 200),
        amount: uint,
        status: (string-ascii 20),
        proof-url: (string-ascii 200),
        completion-height: uint,
    }
)

(define-map project-funders
    {
        project-id: uint,
        funder: principal,
    }
    { amount: uint }
)

(define-data-var project-counter uint u0)

(define-public (create-project
        (name (string-ascii 100))
        (location (string-ascii 100))
        (target-amount uint)
    )
    (let ((project-id (+ (var-get project-counter) u1)))
        (asserts! (> target-amount u0) err-invalid-amount)
        (asserts! (is-none (map-get? projects { project-id: project-id }))
            err-project-exists
        )
        (map-set projects { project-id: project-id } {
            name: name,
            location: location,
            target-amount: target-amount,
            current-amount: u0,
            status: "active",
            owner: tx-sender,
            start-height: burn-block-height,
            completion-height: u0,
        })
        (var-set project-counter project-id)
        (ok project-id)
    )
)

(define-public (add-milestone
        (project-id uint)
        (milestone-id uint)
        (description (string-ascii 200))
        (amount uint)
    )
    (let ((project (unwrap! (map-get? projects { project-id: project-id }) err-not-found)))
        (asserts! (is-eq tx-sender (get owner project)) err-owner-only)
        (map-insert milestones {
            project-id: project-id,
            milestone-id: milestone-id,
        } {
            description: description,
            amount: amount,
            status: "pending",
            proof-url: "",
            completion-height: u0,
        })
        (ok true)
    )
)

(define-public (fund-project
        (project-id uint)
        (amount uint)
    )
    (let ((project (unwrap! (map-get? projects { project-id: project-id }) err-not-found)))
        (asserts! (is-eq (get status project) "active") err-invalid-status)
        (try! (stx-transfer? amount tx-sender contract-owner))
        (map-set projects { project-id: project-id }
            (merge project { current-amount: (+ (get current-amount project) amount) })
        )
        (map-set project-funders {
            project-id: project-id,
            funder: tx-sender,
        } { amount: (default-to u0
            (get amount
                (map-get? project-funders {
                    project-id: project-id,
                    funder: tx-sender,
                })
            )) }
        )
        (ok true)
    )
)

(define-public (complete-milestone
        (project-id uint)
        (milestone-id uint)
        (proof-url (string-ascii 200))
    )
    (let (
            (project (unwrap! (map-get? projects { project-id: project-id }) err-not-found))
            (milestone (unwrap!
                (map-get? milestones {
                    project-id: project-id,
                    milestone-id: milestone-id,
                })
                err-not-found
            ))
        )
        (asserts! (is-eq tx-sender (get owner project)) err-owner-only)
        (asserts! (is-eq (get status milestone) "pending") err-invalid-status)
        (map-set milestones {
            project-id: project-id,
            milestone-id: milestone-id,
        }
            (merge milestone {
                status: "completed",
                proof-url: proof-url,
                completion-height: burn-block-height,
            })
        )
        (ok true)
    )
)

(define-public (complete-project (project-id uint))
    (let ((project (unwrap! (map-get? projects { project-id: project-id }) err-not-found)))
        (asserts! (is-eq tx-sender (get owner project)) err-owner-only)
        (asserts! (is-eq (get status project) "active") err-invalid-status)
        (map-set projects { project-id: project-id }
            (merge project {
                status: "completed",
                completion-height: burn-block-height,
            })
        )
        (ok true)
    )
)

(define-read-only (get-project (project-id uint))
    (ok (unwrap! (map-get? projects { project-id: project-id }) err-not-found))
)

(define-read-only (get-milestone
        (project-id uint)
        (milestone-id uint)
    )
    (ok (unwrap!
        (map-get? milestones {
            project-id: project-id,
            milestone-id: milestone-id,
        })
        err-not-found
    ))
)

(define-read-only (get-funder-amount
        (project-id uint)
        (funder principal)
    )
    (ok (unwrap!
        (map-get? project-funders {
            project-id: project-id,
            funder: funder,
        })
        err-not-found
    ))
)
