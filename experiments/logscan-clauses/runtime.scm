;;; The guile primitive vocabulary: written once, shared by every lips program
;;; on this runtime, never minted. The analogue of nixpkgs on the config axis:
;;; a clause reaches a concrete capability only by naming one of these.

(use-modules (ice-9 rdelim) (json))

(define (read-a-line) (read-line))
(define (end-of-input? x) (eof-object? x))
(define (emit line) (display line) (newline))

(define (die . parts)
  (for-each (lambda (p) (display p (current-error-port))
                        (display " " (current-error-port)))
            parts)
  (newline (current-error-port))
  (exit 1))

;; A pair of (before . after) around the first occurrence of ch, or #f when ch
;; does not occur. The Scheme name for Go's strings.Cut.
(define (string-cut s ch)
  (let loop ((i 0))
    (cond ((>= i (string-length s)) #f)
          ((char=? (string-ref s i) ch)
           (cons (substring s 0 i) (substring s (+ i 1))))
          (else (loop (+ i 1))))))

;; A JSON object as an association list, or #f when the text is not JSON.
(define (json-parse text)
  (catch #t (lambda () (json-string->scm text)) (lambda _ #f)))

(define (field-of record name) (assoc-ref record name))
(define (field-name p) (car p))
(define (field-value p) (cdr p))
