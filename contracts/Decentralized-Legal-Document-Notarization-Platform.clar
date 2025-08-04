(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOTARY-EXISTS (err u101))
(define-constant ERR-NOTARY-NOT-FOUND (err u102))
(define-constant ERR-DOCUMENT-EXISTS (err u103))
(define-constant ERR-INVALID-STATUS (err u104))
(define-constant ERR-DOCUMENT-EXPIRED (err u105))
(define-constant ERR-INVALID-EXPIRY (err u106))

(define-data-var contract-owner principal tx-sender)

(define-map notaries
  { notary-id: principal }
  {
    name: (string-ascii 50),
    license-number: (string-ascii 20),
    active: bool
  }
)

(define-map documents 
  { document-hash: (buff 32) }
  {
    owner: principal,
    notary: (optional principal),
    timestamp: uint,
    status: (string-ascii 20),
    attestation-id: (optional uint),
    expiry-block: (optional uint)
  }
)

(define-non-fungible-token attestation uint)

(define-data-var attestation-nonce uint u0)

(define-read-only (get-notary (notary-id principal))
  (map-get? notaries { notary-id: notary-id })
)

(define-read-only (get-document (document-hash (buff 32)))
  (map-get? documents { document-hash: document-hash })
)

(define-public (register-notary (name (string-ascii 50)) (license-number (string-ascii 20)))
  (let ((notary-exists (get-notary tx-sender)))
    (asserts! (is-none notary-exists) ERR-NOTARY-EXISTS)
    (ok (map-set notaries
      { notary-id: tx-sender }
      {
        name: name,
        license-number: license-number,
        active: true
      }
    ))
  )
)

(define-public (upload-document (document-hash (buff 32)))
  (let ((doc-exists (get-document document-hash)))
    (asserts! (is-none doc-exists) ERR-DOCUMENT-EXISTS)
    (ok (map-set documents
      { document-hash: document-hash }
      {
        owner: tx-sender,
        notary: none,
        timestamp: burn-block-height,
        status: "PENDING",
        attestation-id: none,
        expiry-block: none
      }
    ))
  )
)

(define-public (attest-document (document-hash (buff 32)))
  (let (
    (notary (get-notary tx-sender))
    (document (get-document document-hash))
    (new-id (+ (var-get attestation-nonce) u1))
  )
    (asserts! (is-some notary) ERR-NOT-AUTHORIZED)
    (asserts! (is-some document) ERR-DOCUMENT-EXISTS)
    (asserts! (get active (unwrap-panic notary)) ERR-NOT-AUTHORIZED)
    
    (try! (nft-mint? attestation new-id tx-sender))
    (var-set attestation-nonce new-id)
    
    (ok (map-set documents
      { document-hash: document-hash }
      {
        owner: (get owner (unwrap-panic document)),
        notary: (some tx-sender),
        timestamp: burn-block-height,
        status: "ATTESTED",
        attestation-id: (some new-id),
        expiry-block: (get expiry-block (unwrap-panic document))
      }
    ))
  )
)

(define-public (deactivate-notary (notary-id principal))
  (let ((existing-notary (get-notary notary-id)))
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-some existing-notary) ERR-NOTARY-NOT-FOUND)
    
    (ok (map-set notaries
      { notary-id: notary-id }
      (merge (unwrap-panic existing-notary)
        { active: false }
      )
    ))
  )
)

(define-public (upload-document-with-expiry (document-hash (buff 32)) (expiry-blocks uint))
  (let ((doc-exists (get-document document-hash))
        (expiry-block (+ burn-block-height expiry-blocks)))
    (asserts! (is-none doc-exists) ERR-DOCUMENT-EXISTS)
    (asserts! (> expiry-blocks u0) ERR-INVALID-EXPIRY)
    (ok (map-set documents
      { document-hash: document-hash }
      {
        owner: tx-sender,
        notary: none,
        timestamp: burn-block-height,
        status: "PENDING",
        attestation-id: none,
        expiry-block: (some expiry-block)
      }
    ))
  )
)

(define-read-only (is-document-expired (document-hash (buff 32)))
  (let ((document (get-document document-hash)))
    (match document
      doc-data (match (get expiry-block doc-data)
        expiry (>= burn-block-height expiry)
        false
      )
      false
    )
  )
)

(define-read-only (get-document-status (document-hash (buff 32)))
  (let ((document (get-document document-hash)))
    (match document
      doc-data (if (is-document-expired document-hash)
        "EXPIRED"
        (get status doc-data)
      )
      "NOT_FOUND"
    )
  )
)

(define-public (verify-document (document-hash (buff 32)))
  (let ((document (get-document document-hash)))
    (asserts! (is-some document) ERR-DOCUMENT-EXISTS)
    (asserts! (not (is-document-expired document-hash)) ERR-DOCUMENT-EXPIRED)
    (ok true)
  )
)