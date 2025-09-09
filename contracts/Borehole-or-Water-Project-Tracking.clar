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
(define-constant err-not-funder (err u200))
(define-constant err-vote-not-found (err u201))
(define-constant err-already-voted (err u202))
(define-constant err-vote-ended (err u203))
(define-constant err-insufficient-votes (err u204))

(define-map project-votes
    { vote-id: uint }
    {
        project-id: uint,
        title: (string-ascii 100),
        description: (string-ascii 300),
        proposer: principal,
        start-height: uint,
        end-height: uint,
        total-votes: uint,
        yes-votes: uint,
        status: (string-ascii 20),
    }
)

(define-map voter-records
    {
        vote-id: uint,
        voter: principal,
    }
    {
        vote-weight: uint,
        choice: bool,
    }
)

(define-data-var vote-counter uint u0)

(define-public (create-vote
        (project-id uint)
        (title (string-ascii 100))
        (description (string-ascii 300))
        (duration uint)
    )
    (let (
            (vote-id (+ (var-get vote-counter) u1))
            (project (unwrap! (map-get? projects { project-id: project-id }) err-not-found))
            (funder-info (unwrap!
                (map-get? project-funders {
                    project-id: project-id,
                    funder: tx-sender,
                })
                err-not-funder
            ))
        )
        (map-set project-votes { vote-id: vote-id } {
            project-id: project-id,
            title: title,
            description: description,
            proposer: tx-sender,
            start-height: burn-block-height,
            end-height: (+ burn-block-height duration),
            total-votes: u0,
            yes-votes: u0,
            status: "active",
        })
        (var-set vote-counter vote-id)
        (ok vote-id)
    )
)

(define-public (cast-vote
        (vote-id uint)
        (choice bool)
    )
    (let (
            (vote (unwrap! (map-get? project-votes { vote-id: vote-id })
                err-vote-not-found
            ))
            (project-id (get project-id vote))
            (funder-info (unwrap!
                (map-get? project-funders {
                    project-id: project-id,
                    funder: tx-sender,
                })
                err-not-funder
            ))
            (vote-weight (get amount funder-info))
        )
        (asserts! (< burn-block-height (get end-height vote)) err-vote-ended)
        (asserts!
            (is-none (map-get? voter-records {
                vote-id: vote-id,
                voter: tx-sender,
            }))
            err-already-voted
        )
        (map-set voter-records {
            vote-id: vote-id,
            voter: tx-sender,
        } {
            vote-weight: vote-weight,
            choice: choice,
        })
        (map-set project-votes { vote-id: vote-id }
            (merge vote {
                total-votes: (+ (get total-votes vote) vote-weight),
                yes-votes: (if choice
                    (+ (get yes-votes vote) vote-weight)
                    (get yes-votes vote)
                ),
            })
        )
        (ok true)
    )
)

(define-public (finalize-vote (vote-id uint))
    (let ((vote (unwrap! (map-get? project-votes { vote-id: vote-id }) err-vote-not-found)))
        (asserts! (>= burn-block-height (get end-height vote)) err-vote-ended)
        (asserts! (is-eq (get status vote) "active") err-invalid-status)
        (map-set project-votes { vote-id: vote-id }
            (merge vote { status: (if (> (* (get yes-votes vote) u2) (get total-votes vote))
                "passed"
                "failed"
            ) }
            ))
        (ok true)
    )
)

(define-read-only (get-vote (vote-id uint))
    (ok (unwrap! (map-get? project-votes { vote-id: vote-id }) err-vote-not-found))
)

(define-read-only (get-voter-choice
        (vote-id uint)
        (voter principal)
    )
    (ok (unwrap!
        (map-get? voter-records {
            vote-id: vote-id,
            voter: voter,
        })
        err-not-found
    ))
)
(define-constant err-insufficient-funds (err u300))
(define-constant err-release-not-ready (err u301))
(define-constant err-already-released (err u302))
(define-constant err-dispute-period (err u303))

(define-map fund-releases
    { release-id: uint }
    {
        project-id: uint,
        milestone-id: uint,
        amount: uint,
        release-height: uint,
        status: (string-ascii 20),
        dispute-end-height: uint,
        released-amount: uint,
    }
)

(define-map project-escrow
    { project-id: uint }
    {
        total-escrowed: uint,
        total-released: uint,
        dispute-count: uint,
    }
)

(define-map fund-disputes
    {
        release-id: uint,
        disputer: principal,
    }
    {
        reason: (string-ascii 200),
        dispute-height: uint,
        resolved: bool,
    }
)

(define-data-var release-counter uint u0)
(define-constant dispute-period u144)
(define-constant min-dispute-amount u1000000)

(define-public (schedule-fund-release
        (project-id uint)
        (milestone-id uint)
        (amount uint)
        (delay-blocks uint)
    )
    (let (
            (release-id (+ (var-get release-counter) u1))
            (project (unwrap! (map-get? projects { project-id: project-id }) err-not-found))
            (milestone (unwrap!
                (map-get? milestones {
                    project-id: project-id,
                    milestone-id: milestone-id,
                })
                err-not-found
            ))
            (escrow (default-to {
                total-escrowed: u0,
                total-released: u0,
                dispute-count: u0,
            }
                (map-get? project-escrow { project-id: project-id })
            ))
        )
        (asserts! (is-eq tx-sender (get owner project)) err-owner-only)
        (asserts! (is-eq (get status milestone) "completed") err-invalid-status)
        (asserts!
            (<= amount
                (- (get current-amount project) (get total-released escrow))
            )
            err-insufficient-funds
        )
        (map-set fund-releases { release-id: release-id } {
            project-id: project-id,
            milestone-id: milestone-id,
            amount: amount,
            release-height: (+ burn-block-height delay-blocks),
            status: "scheduled",
            dispute-end-height: (+ burn-block-height delay-blocks dispute-period),
            released-amount: u0,
        })
        (map-set project-escrow { project-id: project-id }
            (merge escrow { total-escrowed: (+ (get total-escrowed escrow) amount) })
        )
        (var-set release-counter release-id)
        (ok release-id)
    )
)

(define-public (execute-fund-release (release-id uint))
    (let (
            (release (unwrap! (map-get? fund-releases { release-id: release-id })
                err-not-found
            ))
            (project (unwrap! (map-get? projects { project-id: (get project-id release) })
                err-not-found
            ))
            (escrow (unwrap!
                (map-get? project-escrow { project-id: (get project-id release) })
                err-not-found
            ))
        )
        (asserts! (>= burn-block-height (get release-height release))
            err-release-not-ready
        )
        (asserts! (>= burn-block-height (get dispute-end-height release))
            err-dispute-period
        )
        (asserts! (is-eq (get status release) "scheduled") err-already-released)
        (try! (as-contract (stx-transfer? (get amount release) tx-sender (get owner project))))
        (map-set fund-releases { release-id: release-id }
            (merge release {
                status: "released",
                released-amount: (get amount release),
            })
        )
        (map-set project-escrow { project-id: (get project-id release) }
            (merge escrow { total-released: (+ (get total-released escrow) (get amount release)) })
        )
        (ok true)
    )
)

(define-public (dispute-fund-release
        (release-id uint)
        (reason (string-ascii 200))
    )
    (let (
            (release (unwrap! (map-get? fund-releases { release-id: release-id })
                err-not-found
            ))
            (project-id (get project-id release))
            (funder-info (unwrap!
                (map-get? project-funders {
                    project-id: project-id,
                    funder: tx-sender,
                })
                err-not-funder
            ))
        )
        (asserts! (< burn-block-height (get dispute-end-height release))
            err-dispute-period
        )
        (asserts! (>= (get amount funder-info) min-dispute-amount)
            err-insufficient-funds
        )
        (asserts! (is-eq (get status release) "scheduled") err-invalid-status)
        (map-set fund-disputes {
            release-id: release-id,
            disputer: tx-sender,
        } {
            reason: reason,
            dispute-height: burn-block-height,
            resolved: false,
        })
        (map-set fund-releases { release-id: release-id }
            (merge release { status: "disputed" })
        )
        (ok true)
    )
)

(define-public (resolve-dispute
        (release-id uint)
        (approve bool)
    )
    (let ((release (unwrap! (map-get? fund-releases { release-id: release-id })
            err-not-found
        )))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq (get status release) "disputed") err-invalid-status)
        (map-set fund-releases { release-id: release-id }
            (merge release { status: (if approve
                "scheduled"
                "cancelled"
            ) }
            ))
        (ok true)
    )
)

(define-read-only (get-fund-release (release-id uint))
    (ok (unwrap! (map-get? fund-releases { release-id: release-id }) err-not-found))
)

(define-read-only (get-project-escrow (project-id uint))
    (ok (default-to {
        total-escrowed: u0,
        total-released: u0,
        dispute-count: u0,
    }
        (map-get? project-escrow { project-id: project-id })
    ))
)

(define-read-only (get-dispute
        (release-id uint)
        (disputer principal)
    )
    (ok (unwrap!
        (map-get? fund-disputes {
            release-id: release-id,
            disputer: disputer,
        })
        err-not-found
    ))
)

(define-constant err-update-not-found (err u400))
(define-constant err-already-verified (err u401))
(define-constant err-invalid-update-status (err u402))

(define-map project-updates
    { update-id: uint }
    {
        project-id: uint,
        title: (string-ascii 100),
        content: (string-ascii 500),
        media-url: (string-ascii 200),
        posted-height: uint,
        poster: principal,
        verification-count: uint,
        verification-weight: uint,
        status: (string-ascii 20),
    }
)

(define-map update-verifications
    {
        update-id: uint,
        verifier: principal,
    }
    {
        weight: uint,
        verified-height: uint,
        authentic: bool,
    }
)

(define-data-var update-counter uint u0)
(define-constant min-verification-threshold u500000)

(define-public (post-project-update
        (project-id uint)
        (title (string-ascii 100))
        (content (string-ascii 500))
        (media-url (string-ascii 200))
    )
    (let (
            (update-id (+ (var-get update-counter) u1))
            (project (unwrap! (map-get? projects { project-id: project-id }) err-not-found))
        )
        (asserts! (is-eq tx-sender (get owner project)) err-owner-only)
        (map-set project-updates { update-id: update-id } {
            project-id: project-id,
            title: title,
            content: content,
            media-url: media-url,
            posted-height: burn-block-height,
            poster: tx-sender,
            verification-count: u0,
            verification-weight: u0,
            status: "unverified",
        })
        (var-set update-counter update-id)
        (ok update-id)
    )
)

(define-public (verify-project-update
        (update-id uint)
        (authentic bool)
    )
    (let (
            (update (unwrap! (map-get? project-updates { update-id: update-id })
                err-update-not-found
            ))
            (project-id (get project-id update))
            (funder-info (unwrap!
                (map-get? project-funders {
                    project-id: project-id,
                    funder: tx-sender,
                })
                err-not-funder
            ))
            (verification-weight (get amount funder-info))
        )
        (asserts!
            (is-none (map-get? update-verifications {
                update-id: update-id,
                verifier: tx-sender,
            }))
            err-already-verified
        )
        (asserts! (>= verification-weight min-verification-threshold)
            err-insufficient-funds
        )
        (map-set update-verifications {
            update-id: update-id,
            verifier: tx-sender,
        } {
            weight: verification-weight,
            verified-height: burn-block-height,
            authentic: authentic,
        })
        (let ((new-weight (if authentic
                (+ (get verification-weight update) verification-weight)
                (get verification-weight update)
            )))
            (map-set project-updates { update-id: update-id }
                (merge update {
                    verification-count: (+ (get verification-count update) u1),
                    verification-weight: new-weight,
                    status: (if (and authentic (>= new-weight
                            (/
                                (*
                                    (get current-amount
                                        (unwrap!
                                            (map-get? projects { project-id: project-id })
                                            err-not-found
                                        ))
                                    u10
                                )
                                u100
                            )))
                        "verified"
                        (get status update)
                    ),
                })
            )
        )
        (ok true)
    )
)

(define-public (flag-update-disputed (update-id uint))
    (let (
            (update (unwrap! (map-get? project-updates { update-id: update-id })
                err-update-not-found
            ))
            (project-id (get project-id update))
            (funder-info (unwrap!
                (map-get? project-funders {
                    project-id: project-id,
                    funder: tx-sender,
                })
                err-not-funder
            ))
        )
        (asserts! (>= (get amount funder-info) min-dispute-amount)
            err-insufficient-funds
        )
        (asserts! (not (is-eq (get status update) "disputed"))
            err-invalid-update-status
        )
        (map-set project-updates { update-id: update-id }
            (merge update { status: "disputed" })
        )
        (ok true)
    )
)

(define-read-only (get-project-update (update-id uint))
    (ok (unwrap! (map-get? project-updates { update-id: update-id })
        err-update-not-found
    ))
)

(define-read-only (get-update-verification
        (update-id uint)
        (verifier principal)
    )
    (ok (unwrap!
        (map-get? update-verifications {
            update-id: update-id,
            verifier: verifier,
        })
        err-not-found
    ))
)

(define-read-only (get-update-counter)
    (ok (var-get update-counter))
)

(define-constant err-invalid-rating (err u500))
(define-constant err-already-rated (err u501))
(define-constant err-project-not-completed (err u502))
(define-constant min-rating-threshold u100000)

(define-map project-ratings
    {
        project-id: uint,
        rater: principal,
    }
    {
        rating: uint,
        weight: uint,
        rating-height: uint,
    }
)

(define-map project-rating-stats
    { project-id: uint }
    {
        total-rating-weight: uint,
        weighted-rating-sum: uint,
        rating-count: uint,
        average-rating: uint,
    }
)

(define-map owner-reputation
    { owner: principal }
    {
        total-projects: uint,
        total-weighted-rating: uint,
        total-weight: uint,
        reputation-score: uint,
    }
)

(define-public (rate-project
        (project-id uint)
        (rating uint)
    )
    (let (
            (project (unwrap! (map-get? projects { project-id: project-id }) err-not-found))
            (funder-info (unwrap!
                (map-get? project-funders {
                    project-id: project-id,
                    funder: tx-sender,
                })
                err-not-funder
            ))
            (rating-weight (get amount funder-info))
            (project-owner (get owner project))
        )
        (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
        (asserts! (is-eq (get status project) "completed")
            err-project-not-completed
        )
        (asserts! (>= rating-weight min-rating-threshold) err-insufficient-funds)
        (asserts!
            (is-none (map-get? project-ratings {
                project-id: project-id,
                rater: tx-sender,
            }))
            err-already-rated
        )
        (map-set project-ratings {
            project-id: project-id,
            rater: tx-sender,
        } {
            rating: rating,
            weight: rating-weight,
            rating-height: burn-block-height,
        })
        (let (
                (current-stats (default-to {
                    total-rating-weight: u0,
                    weighted-rating-sum: u0,
                    rating-count: u0,
                    average-rating: u0,
                }
                    (map-get? project-rating-stats { project-id: project-id })
                ))
                (new-weight-sum (+ (get total-rating-weight current-stats) rating-weight))
                (new-rating-sum (+ (get weighted-rating-sum current-stats)
                    (* rating rating-weight)
                ))
                (new-average (/ new-rating-sum new-weight-sum))
            )
            (map-set project-rating-stats { project-id: project-id } {
                total-rating-weight: new-weight-sum,
                weighted-rating-sum: new-rating-sum,
                rating-count: (+ (get rating-count current-stats) u1),
                average-rating: new-average,
            })
            (let (
                    (current-reputation (default-to {
                        total-projects: u0,
                        total-weighted-rating: u0,
                        total-weight: u0,
                        reputation-score: u0,
                    }
                        (map-get? owner-reputation { owner: project-owner })
                    ))
                    (updated-weight (+ (get total-weight current-reputation) rating-weight))
                    (updated-rating-sum (+ (get total-weighted-rating current-reputation)
                        (* rating rating-weight)
                    ))
                    (new-reputation-score (if (> updated-weight u0)
                        (/ updated-rating-sum updated-weight)
                        u0
                    ))
                )
                (map-set owner-reputation { owner: project-owner } {
                    total-projects: (+ (get total-projects current-reputation) u1),
                    total-weighted-rating: updated-rating-sum,
                    total-weight: updated-weight,
                    reputation-score: new-reputation-score,
                })
            )
        )
        (ok true)
    )
)

(define-public (batch-rate-projects (ratings (list 10 {
    project-id: uint,
    rating: uint,
})))
    (ok (map rate-single-project ratings))
)

(define-private (rate-single-project (rating-data {
    project-id: uint,
    rating: uint,
}))
    (rate-project (get project-id rating-data) (get rating rating-data))
)

(define-read-only (get-project-rating (project-id uint))
    (ok (default-to {
        total-rating-weight: u0,
        weighted-rating-sum: u0,
        rating-count: u0,
        average-rating: u0,
    }
        (map-get? project-rating-stats { project-id: project-id })
    ))
)

(define-read-only (get-owner-reputation (owner principal))
    (ok (default-to {
        total-projects: u0,
        total-weighted-rating: u0,
        total-weight: u0,
        reputation-score: u0,
    }
        (map-get? owner-reputation { owner: owner })
    ))
)

(define-read-only (get-funder-project-rating
        (project-id uint)
        (rater principal)
    )
    (ok (unwrap!
        (map-get? project-ratings {
            project-id: project-id,
            rater: rater,
        })
        err-not-found
    ))
)

(define-read-only (calculate-trust-score
        (owner principal)
        (min-projects uint)
    )
    (let (
            (reputation (unwrap! (map-get? owner-reputation { owner: owner }) err-not-found))
            (project-count (get total-projects reputation))
            (rep-score (get reputation-score reputation))
        )
        (ok (if (>= project-count min-projects)
            (* rep-score (/ project-count (+ project-count u1)))
            (/ rep-score u2)
        ))
    )
)
