;; @from logscan.lips:1
(define (main) (scan (parse-spec (arguments))))

;; @from logscan.lips:1
(define (scan spec) (let ((line (read-a-line))) (cond ((end-of-input? line) #t) ((keep? (json-parse line) spec) (print-kept line) (scan spec)) (else (scan spec)))))

;; @from logscan.lips:2
(define (keep? record spec) (cond ((not record) #f) ((null? spec) #t) ((equal? (field-of record (car (car spec))) (cdr (car spec))) (keep? record (cdr spec))) (else #f)))

;; @from logscan.lips:2
(define (parse-pair arg) (let ((cut (string-cut arg #\=))) (cond ((not cut) (die "argument is not field=value:" arg)) (else cut))))

;; @from logscan.lips:2
(define (parse-spec args) (cond ((null? args) (quote ())) (else (cons (parse-pair (car args)) (parse-spec (cdr args))))))

;; @from logscan.lips:3
(define (print-kept line) (emit line))

;; @from logscan.lips:5
(define (filter-lines lines spec) (cond ((null? lines) (quote ())) ((keep? (json-parse (car lines)) spec) (cons (car lines) (filter-lines (cdr lines) spec))) (else (filter-lines (cdr lines) spec))))
