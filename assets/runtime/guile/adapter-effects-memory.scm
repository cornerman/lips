;;; In-memory adapter, effect contracts: the SAME four names, backed by lists.
;;; Linking this instead of the guile one runs the whole program offline, with
;;; no process, no stdin and no VM. Mutation lives here, in the shell, never in
;;; the minted core.
(define pending-lines '())
(define emitted-lines '())
(define end-of-input-token 'end-of-input)

(define (feed-lines lines)
  (set! pending-lines lines)
  (set! emitted-lines '()))

(define (emitted) (reverse emitted-lines))

(define (read-a-line)
  (cond ((null? pending-lines) end-of-input-token)
        (else (let ((line (car pending-lines)))
                (set! pending-lines (cdr pending-lines))
                line))))

(define (end-of-input? x) (eq? x end-of-input-token))
(define (emit line) (set! emitted-lines (cons line emitted-lines)))
(define (die message subject) (throw 'died message subject))
