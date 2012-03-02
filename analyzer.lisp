(ql:quickload "xmls")                   ;TODO: document quicklisp as a dependency

(defpackage :unmake
  (:use :common-lisp))
(in-package :unmake)

(defun to-sexpr (cbf-file)
  "Parse a file in the Common Build Format and return an sexpr representing
  the dependency tree contained therein."
  (with-open-file (cbf-str cbf-file :direction :input)
    (let ((cbf-sexpr (xmls:parse cbf-str)))
      (cddr cbf-sexpr) ;discards <build> stuff, which isn't useful to us
      )))

(defun munge-rule (rule)
  "Takes the sexpr structure of a rule as generated by XMLS and munges it into
  a much more useful format, such that we can build a reasonable alist or hash
  for the whole shebang."
  (labels
    ((rule-name (rule)
       (intern (car (cdaadr rule))))
     (dep-name (dep)
       (intern (caddr dep)))
     (rule-deps (rule)
       (mapcar #'dep-name (cddr rule))))

    (cons (rule-name rule) (list (rule-deps rule)))))

(defun to-alist (cbf-sexpr)
  (mapcar #'munge-rule cbf-sexpr))

(defun to-hash (cbf-sexpr)
  (let ((spine (make-hash-table)))
    (mapc (lambda (rule)
            (setf (gethash (car (munge-rule rule)) spine)
                  (cdr (munge-rule rule)))) cbf-sexpr)
    spine ))

(defun count-rules (cbf-sexpr)
  "Returns the number of rules defined in the dependency tree represented by
  cbf-sexpr"
  (if (eq cbf-sexpr nil) 0
    (+ 1 (count-rules (cdr cbf-sexpr)))))

(defun depth-first-traverse (alist)
  "Performs a DFT (more accurately an exploration) of the given alist, returning
  a cons of (cyclicp . build-order)
  where cyclicp represents whether the dependency graph represented by alist
  contains any cycles, and build-order is a list representing what you'd expect."
  (let ((head (caar alist))
        (visited   (make-hash-table))
        (previsit  (make-hash-table))
        (postvisit (make-hash-table))
        (tick 0))
    (labels
      ((cycles-present-p ()
         "Check whether our graph contains any cycles"
         (let ((cyclicp nil)
               (files (mapcar #'car alist)))
               (mapc (lambda (file) ;for each file, check if its deps have a back edge
                 (mapc (lambda (dep)
                         (if (and (< (gethash dep  previsit) ;back edge
                                     (gethash file previsit))
                                  (> (gethash dep  postvisit)
                                     (gethash file postvisit)))
                           (setf cyclicp t)))
                       (cadr (assoc file alist))))
               files)
         cyclicp))
       (explore (node)
         "The explore algorithm for topo-sorting and cycle detection.
                cf. DPV's 'Algorithms' p. 95 for reference."
         (setf (gethash node visited) t)
         (setf (gethash node previsit) (incf tick))
         (mapc (lambda (u)
                 (if (eq t (gethash u visited))
                   nil
                   (explore u)))
               (cadr (assoc node alist)))
         (setf (gethash node postvisit) (incf tick))
         nil)
       (build-order (postvisit-hash)
         "Generate an optimal build order via the postorder from our depth-first
                    traversal, and filter out files that don't need to be built."
         (let ((keys (loop for key being the hash-keys of postvisit-hash
                           collect key)))
           (remove-if ;nb. "all" is a magic target we can safely discard
             (lambda (file) (or (eq (cadr (assoc file alist)) nil) (eq file '|all|)))
             (sort keys #'< :key (lambda (file) (gethash file postvisit-hash)))))))
    (explore head)
  (cons (cycles-present-p) (list (build-order postvisit))))))

(defun analyze (cbf-file)
  "Analyze and report on the properties of a Common Build Format file"
  (if (eq cbf-file nil) (setf cbf-file "cbf.xml"))
  (let ((cbf-sexpr (to-sexpr cbf-file)))
    (format t "Report for the build system described in ~a: ~&" cbf-file)
    (format t "    Number of rules: ~d ~&" (count-rules cbf-sexpr))
    (let ((dft-result (depth-first-traverse (to-alist cbf-sexpr))))
      (format t "    Build graph is ~a ~&"
              (if (car dft-result)
                "cyclic :("
                "acyclic :)"))
      (format t "    Optimal build order is ~a ~&"
              (if (car dft-result)
                "nonexistent"
                (cdr dft-result))))))
