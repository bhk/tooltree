(require "core")


;; graph.trav: return a partially ordered list of all nodes descending
;; from `list`.
;;
;; list = list of nodes to traverse (nil => visiting a node)
;; getChildren = name of function to get children of a node
;; parents = ancestors of `list` or `node`
;; node = When non-nil, the name of a node to be visited.
;; visited = expanded, ordered result from some subset of nodes
;;
(define (graph.trav list getChildren parents node visited)
  (cond
   ;; List: expand rest of list, then handle first node
   (list (graph.trav "" getChildren parents (word 1 list)
                     (graph.trav (rest list) getChildren parents "" visited)))

   ;; Cycle?
   ((filter node parents)
    (concat "CYCLE" (subst " " ":" parents) ":" node
            " " visited))

   ;; Node: visit children (if not already in `visited`)
   ((filter-out visited node)
    (concat node " "
            (graph.trav (call getChildren node)
                        getChildren
                        (concat parents " " node)
                        ""
                        visited)))
   ;; Done
   (else visited)))

;; Tests


(define graph
  (bind "a" "d c b"
  (bind "b" "c e"
  (bind "c" "d"))))

(define (get-children node)
  (get node graph))

(expect
 "a b c d e "
 (graph.trav "a" "get-children"))


(define graph
  (bind "a" "d c b"
  (bind "b" "c e"
  (bind "c" "d"
  (bind "d" "a")))))

(expect
 "a b c d CYCLE:a:b:c:d:a e "
 (graph.trav "a" "get-children"))

(print "graph.trav = " graph.trav)
