;; Construct a dependency graph

(require "core")

;; This delimiter must not appear anywhere in node names
(define `D "`")
(define `DD (.. D D))
(define `D_ (.. D " "))
(define `D__ (.. D "  "))

;; 10K nodes should be more than enough
(define `(rest lst) (wordlist 2 9999 lst))


(define `(stick slot)
  (.. (if (filter D slot) " " "|") "  "))


(define `(arrow slot node)
  (if (findstring (.. D node D) slot)
      "+->"
      (stick slot)))


;; Remove empty slots from the *end* of SLOTS
;;
;; Example:
;;    + " 9"                !a! ! ! !b! ! 9
;;    patsubst "!" "! "     !a! !  !  !b! !  !  9
;;    subst "!  " "!!"      !a! !!!!!b! !!!!9
;;    filter                !a! !!!!!b!
;;    subst "!!" "! "       !a! ! ! !b!
;;
(define `(trim-empties slots)
  ;; make empty slots easy to identify
  (define `a (patsubst D D_ (._. slots 9)))
  ;; collapse empty slots with next slot
  (define `b (subst D__ DD a))
  ;; remove terminal "slot"
  (define `c (filter-out "%9" b))
  (subst DD D_ c))

(define `(tte in out)
  (expect (subst "!" D out) (trim-empties (subst "!" D in))))

(tte "!a! ! ! !b! ! !c! ! !"
     "!a! ! ! !b! ! !c!")
(tte "!a! ! ! !b! ! !c!"
     "!a! ! ! !b! ! !c!")
(tte "! ! !"
     "")


;; Return textual representation of all dependencies among NODES
;;
;; FN-PREFIX us used to construct two function names
;;    FN-PREFIXchildren = function: node -> children
;;    FN-PREFIXname = function: node -> name
;; NODES = nodes remaining to be drawn (two lines of text per node).
;;         This must be partially ordered (parents precede children).
;; SLOTS = columns representing parents.
;; OUT = previously rendered lines of text
;;
;; The algorithm does the following for each nod in NODES:
;;   concatenate "sticks" and "arrows" + NODE to OUT
;;   update SLOTS:
;;     remove NODE from every slot's list of pending children
;;     delete trailing empty slots
;;   update NODE to (rest NODES)
;;
(define (Graph_draw fn-prefix nodes ?slots ?out)
  &native
  (define `(get-children node) (native-call (.. fn-prefix "children") node))
  (define `(get-name node) (native-call (.. fn-prefix "name") node))

  (define `node (word 1 nodes))

  ;; Add new slot containing children of NODE, and remove NODE
  ;; from other slots.
  (define `newSlots
    (trim-empties
     (._. (subst (.. D node D) D slots)
          ;; convert list of children to slot format
          (.. D (subst " " "" (addsuffix D (get-children node)))))))

  (define `newOut
    (.. out
        (foreach (slot slots)
          (stick slot))
        "\n"
        (foreach (slot slots)
          (arrow slot node))
        (if slots " ")
        (get-name node) "\n"))

  (if nodes
      ;; Output lines for this node.
      (Graph_draw fn-prefix (rest nodes) newSlots newOut)
      out))


;; test Graph_draw

(define (sample-children node)
  &native
  (define `g
    { 0: [1 2 4],
      1: [3],
      2: [3],
      A: "D C B",
      B: "C E",
      C: "D",
      })

  (dict-get node g))

(define (sample-name node)
  &native
  (if (filter 3 node)
      (.. "<" node ">")
      node))

(expect
 (concat-vec [
              ""
              "0"
              "|  "
              "+-> 1"
              "|   |  "
              "+-> |   2"
              "|   |   |  "
              "|   +-> +-> <3>"
              "|  "
              "+-> 4"
              ""
              ]
             "\n")
 (Graph_draw "sample-" "0 1 2 3 4" ""))


;; Return list of descendants of NODES, ordered such that all parents
;; precede their children.
;;
(define (Graph_trav get-children-fn nodes ?seen)
  &native
  (define `parent
    (word 1 nodes))

  (if parent
      (Graph_trav get-children-fn
            (._. (native-call get-children-fn parent) (rest nodes))
            (._. (filter-out parent seen) parent))
      seen))


(expect
 "A B C D E"
 (Graph_trav "sample-children" "A"))

;; Display a sample graph.

(print (Graph_draw "sample-" (Graph_trav "sample-children" "A")))


;;----------------------------------------------------------------
;; output Make code
;;----------------------------------------------------------------

(define (scam-to-minion fn-name)
  (define `value (native-value fn-name))
  (subst
   ;; use Minion character constants, not SCAM ones
   "$  " "$(\\s)"
   "$ \t" "$(\\t)"
   "$(if ,,,)" "$;"
   "$`" "$$"
   ;; escape for RHS of Make assignment
   "\n" "$(\\n)"
   "#" "\\#"
   ;; a little optimization
   (.. "$(call " fn-name)  "$(call $0"
   value))

(define (export name)
  (print name " = " (scam-to-minion name)))

(export "Graph_trav")
(export "Graph_draw")
