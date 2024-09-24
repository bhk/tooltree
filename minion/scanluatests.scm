;; Scan Lua unit tests for dependencies
;;
;; Output list of "M = D1 D2 ...", where M identifies a unit test named
;; M_q.lua which should depend on a successful result of running tests
;; D1_q.lua and D2_q.lua, etc..

(require "core")
(require "io")

;; Return list of modules used by FILE
(define (used file)
  &public
  (define `src
    (subst "'" "\""
           (promote (filter-out "--%" (subst "\n" " " (read-lines file))))))
  (define `mods
    (subst ">" ""
           "\"" ""
           (filter ">>>%"
                   (subst "require \"" ">>>" src))))
  (filter-out (patsubst "%.lua" "%" file) mods))

;; Return a list of modules used transitively.
(define (used-rec file)
  &public
  (foreach (m (used file))
    (._. m (used-rec (.. m ".lua")))))


(define (deps-of file)
  &public
  (define `requires
    (uniq (used-rec file)))
  (filter-out (patsubst "%_q.lua" "%" file) requires))

(define testmods
  &public
  (patsubst "%_q.lua" "%" (wildcard "*_q.lua")))

(define (showdeps)
  (for (m testmods)
    (print m " = " (filter (deps-of (.. m "_q.lua")) testmods))))

(showdeps)
