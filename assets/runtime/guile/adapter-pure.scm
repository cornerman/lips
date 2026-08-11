;;; guile adapter, pure contracts. Names packages where a package exists; the
;;; only hand-written piece is the one the vocabulary genuinely lacks.
(use-modules (json))                    ; guile-json provides json-string->scm

(define (json-parse text)
  (catch #t (lambda () (json-string->scm text)) (lambda _ #f)))

;; Go has strings.Cut; R7RS-small has nothing, so this is the gap a runtime
;; without the capability makes somebody fill.
(define (string-cut s ch)
  (let loop ((i 0))
    (cond ((>= i (string-length s)) #f)
          ((char=? (string-ref s i) ch)
           (cons (substring s 0 i) (substring s (+ i 1))))
          (else (loop (+ i 1))))))

(define (field-of record name) (assoc-ref record name))
(define (field-name p) (car p))
(define (field-value p) (cdr p))

;; The generator is specified in assets/runtime/scheme/contracts, not chosen
;; here, so that every runtime steps identically. Guile's exact integers make
;; the recurrence exact; nothing rounds.
(define (random-step seed)
  (let ((next (modulo (+ (* 1664525 seed) 1013904223) 4294967296)))
    (cons (quotient (* next 1000) 4294967296) next)))
