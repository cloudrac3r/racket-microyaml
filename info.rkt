#lang info
(define collection "microyaml")
(define version "1.1")
(define deps '("base" "typed-racket-lib" "rackunit-lib"))
(define build-deps '("racket-doc" "scribble-lib" "typed-racket-doc" "sandbox-lib"))
(define scribblings '(("scribblings/microyaml.scrbl")))
(define license 'BSD-3-Clause)
