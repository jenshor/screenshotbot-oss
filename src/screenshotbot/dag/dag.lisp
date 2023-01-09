;; Copyright 2018-Present Modern Interpreters Inc.
;;
;; This Source Code Form is subject to the terms of the Mozilla Public
;; License, v. 2.0. If a copy of the MPL was not distributed with this
;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(in-package :dag)

(define-condition node-already-exists (error)
  ())

(defvar *magic* (flex:string-to-octets "bdag" :external-format :latin1))

(defclass commit ()
  ((sha :initarg :sha
        :accessor sha)
   (author :initarg :author
           :initform nil
           :accessor author)
   (parents :initarg :parents
            :initform nil
            :accessor parents
            :documentation "array of shas")))

(defmacro pp (x)
  `(let ((y ,x))
     ;;(log:info "Got ~S for ~S" y ',x)
     y))

(defun commit-node-id (x)
  "The node id used for cl-graph queries."
  (check-type x string)
  (assert (> (length x) 0))
  (assert x)
  (let ((arr
          (ironclad:hex-string-to-byte-array x)))
    (let ((ret 0))
      (loop for i across arr do
        (setf ret
              (+ (ash ret 8) i)))
      ret)))

(defclass dag ()
  ((digraph :initform (make-instance 'graph:digraph)
            :accessor digraph)
   (commits :initform (make-hash-table :test 'equal)
            :accessor commit-map)
   (pathname :initarg :pathname
             :documentation "For debugging only")))

(defmethod ordered-commits ((dag dag))
  (let ((sorted (safe-topological-sort (digraph dag))))
    (loop for id in sorted
          collect (gethash id (commit-map dag)))))

(defmethod get-commit ((dag dag) (sha string))
  (let ((id (commit-node-id sha)))
    (log:debug "Commit id for ~a is ~a" sha id)
    (gethash id (commit-map dag))))

(defmethod bfs-search ((dag dag) start end)
  (let ((seen (make-hash-table :test 'equal))
        (queue nil))
    (setf (gethash start seen) t)
    (push start queue)
    (loop while queue do
      (let ((next (pop queue)))
        (when (equal (commit-node-id end)
                     (commit-node-id next))
          (return-from bfs-search t))
        (loop for parent in (alexandria:if-let (commit (get-commit dag next))
                              (parents commit)
                              (progn
                                (log:info "Commit ~a not in graph" next)
                                nil))
              do
                 (unless (gethash parent seen)
                   (setf (gethash parent seen) t)
                   (push parent queue)))))
    nil))

(defmethod ancestorp ((dag dag) (sha-old string) (sha-new string))
  (bfs-search
   dag
   sha-new
   sha-old))

(defmethod add-commit ((dag dag) (commit  commit))
  (assert commit)
  (let ((map (commit-map dag))
        (node-id (commit-node-id (sha commit))))
    (cond
      ((gethash node-id map)
       (error 'node-already-exists))
      (t
       (setf
        (gethash node-id map)
        commit)
       (graph:add-node (digraph dag) node-id)
       (loop for p in (parents commit) do
         (progn
           #+nil(log:info "adding edge from: ~S to ~S" node-id
                          (commit-node-id p))
           (assert (numberp node-id))
           (assert (numberp (commit-node-id p)))
           (graph:add-edge (digraph dag) (list
                                          node-id
                                          (commit-node-id p)))))))))

(defmethod safe-topological-sort (digraph)
  "This is modified from GRAPH. Sadly that library uses recursion for
some of their graph algorithms, which doesn't work nicely for a 'deep'
tree. This version uses the Kahn's algorithm instead of DFS"
  (declare (optimize (speed 3) (debug 0)))
  (let* ((rL nil)
         (out-degrees (make-hash-table)))
    (loop for x in (graph::nodes digraph) do
          (setf (gethash x out-degrees) (length (graph::neighbors digraph x))))

    (let ((S (loop for x being the hash-keys of out-degrees
                   if (eql 0 (gethash x out-degrees))
                     collect x)))
      (loop while S do
        (progn
          (let ((n (pop S)))
            (push n rL)
            (dolist (m (graph::precedents digraph n))
              (decf (gethash m out-degrees))
              (assert (>= (gethash m out-degrees) 0))
              (when (eql (gethash m out-degrees) 0)
                (push m S)))))))
    rL))


(defmethod write-to-stream ((dag dag) stream &key (format :json))
  (let ((sorted-nodes (reverse (safe-topological-sort (digraph dag))))
        (commit-map (commit-map dag)))
    (ecase format
      (:json
       (json:encode-json
        `((:commits .
                    ,(loop for node-id in sorted-nodes
                           collect
                           (let ((commit (gethash node-id commit-map)))
                             (unless commit
                               (error "Could not find node for id ~a" node-id))
                             `((:sha . ,(sha commit))
                               (:author . ,(author commit))
                               (:parents . ,(parents commit))))))
          (:dummy . "0"))
        stream))
      (:binary
       (write-sequence
        *magic*
        stream)
       (write-byte 0 stream)
       (let ((version 1))
         (write-byte version stream))
       (encode-integer (length sorted-nodes) stream)
       (dolist (node-id sorted-nodes)
         (let ((commit (gethash node-id commit-map)))
           ;; TODO: can be further optimized to use integers, but this
           ;; should do for now
           (encode (sha commit) stream)
           (encode (author commit) stream)
           (encode (parents commit) stream))))))
  (finish-output stream))

(defun read-from-stream (stream &key (format :json))
  (let ((dag (make-instance 'dag :pathname (or
                                            (ignore-errors
                                             (pathname stream))
                                            "Stream not pointing to file"))))
    (ecase format
     (:json
      (let ((data (json:decode-json stream)))
        (loop for commit in (assoc-value data :commits) do
          (add-commit dag
                      (apply 'make-instance 'commit
                             (alist-plist commit))))
        dag))
     (:binary
      (let ((magic (make-array 4 :element-type '(unsigned-byte 8))))
        (read-sequence magic stream)
        (assert (equalp magic *magic*)))
      ;; version
      (read-byte stream)
      (let ((version (read-byte stream)))
        (assert (= 1 version)))
      (let ((length (decode stream)))
        (dotimes (i length)
          (let ((sha (decode stream))
                (author (decode stream))
                (parents (decode stream)))
            (add-commit dag
                        (make-instance 'commit
                                       :sha sha
                                       :author author
                                       :parents parents)))))
      dag))))

(defmethod merge-dag ((dag dag) (from-dag dag))
  (dolist (node-id (safe-topological-sort (digraph from-dag)))
    (unless (gethash node-id (commit-map dag))
      (let ((commit (gethash node-id (commit-map from-dag))))
        (assert commit)
        (add-commit dag commit)
        (assert (gethash node-id (commit-map dag)))))))
