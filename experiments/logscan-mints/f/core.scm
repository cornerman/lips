;; @from logscan.lips:1
(define (main) (emit-all (scan (parse-spec (arguments)))))

;; @from logscan.lips:1
(define (scan spec) (let ((line (read-a-line))) (cond ((end-of-input? line) (list)) ((keep? line spec) (cons line (scan spec))) (else (scan spec)))))

;; @from logscan.lips:2
(define (keep? line spec) (let ((record (json-parse line))) (and record (matches? record spec))))

;; @from logscan.lips:2
(define (matches? record spec) (cond ((null? spec) #t) ((equal? (field-of record (car (car spec))) (cdr (car spec))) (matches? record (cdr spec))) (else #f)))

;; @from logscan.lips:2
(define (parse-pair arg) (let ((cut (string-cut arg #\=))) (if cut cut (die "argument is not field=value:" arg))))

;; @from logscan.lips:2
(define (parse-spec args) (if (null? args) (list) (cons (parse-pair (car args)) (parse-spec (cdr args)))))

;; @from logscan.lips:3
(define (emit-all lines) (cond ((null? lines) (list)) (else (let ((ignored (emit (car lines)))) (cons (car lines) (emit-all (cdr lines)))))))
