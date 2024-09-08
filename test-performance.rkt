#lang typed/racket/base/optional
(module+ test
  (require racket/path
           "types/rackunit.rkt"
           "main.rkt")

  (for* ([f '("test/saltern.yaml" "test/femboy_music_FRAGILE.yaml")]
         [m (list file->yaml file->yaml/string)])
    (printf "~a - ~a~n" f m)
    (with-handlers ([exn:fail? (λ ([e : exn]) (displayln (exn-message e)))])
      (void (time (m f))))))
