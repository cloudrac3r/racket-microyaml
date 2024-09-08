#lang typed/racket/base
(module+ test
  (require racket/path
           "types/rackunit.rkt"
           "main.rkt")

  (define test-files (directory-list "test" #:build? #t))
  (for ([f test-files]
        #:when (path-has-extension? f #".rktd"))
    (printf "~a~n" f)
    (define parsed (file->yaml (path-replace-extension f #".yaml")))
    (define expected (with-input-from-file f (λ () (read))))
    (check-equal? parsed expected)))
