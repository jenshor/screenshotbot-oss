;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :util/store/store-migrations
  (:use #:cl)
  (:import-from #:easy-macros
                #:def-easy-macro)
  (:import-from #:alexandria
                #:when-let
                #:assoc-value)
  (:import-from #:bknr.datastore
                #:deftransaction)
  (:import-from #:util/store/store-version
                #:*snapshot-store-version*
                #:*store-version*)
  (:export
   #:def-store-migration
   #:run-migrations))
(in-package :util/store/store-migrations)

(defclass migration ()
  ((version :initarg :version)
   (name :initarg :name
         :reader name)
   (body :initarg :body
         :reader body)))

(defvar *migrations* nil)

(def-easy-macro def-store-migration (name &key version &fn fn)
  (setf
   (assoc-value *migrations* version)
   (make-instance 'migration
                  :version version
                  :name name
                  :body fn)))

(deftransaction set-snapshot-version (version)
  (setf *snapshot-store-version* version))

(defun run-migration-for-version (version)
  (when-let ((migration (assoc-value *migrations* version)))
    (log:info "Running migration: ~a" (name migration))
    (funcall (body migration))))

(defun bump-version ()
  (let ((version *snapshot-store-version*))
    (assert (< version *store-version*))
    (let ((version (1+ version)))
      (run-migration-for-version version)
      (set-snapshot-version version))))

(defun run-migrations ()
  (util/store:safe-snapshot
   (format nil "Before running migrations (current version: ~a)" *snapshot-store-version*))
  (loop while (< *snapshot-store-version* *store-version*)
        do
           (progn
             (log:info "Current store version is ~a" *snapshot-store-version*)
             (bump-version)))
  (util/store:safe-snapshot
   (format nil "After running migrations (current version: ~a)" *snapshot-store-version*)))

(def-store-migration ("Dummy migration for version test" :version 2)
  (log:info "Nothing to do in this migration"))
