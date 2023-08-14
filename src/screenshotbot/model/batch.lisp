;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/model/batch
  (:use #:cl)
  (:import-from #:bknr.datastore
                #:persistent-class
                #:store-object)
  (:import-from #:util/store/store
                #:defindex
                #:with-class-validation)
  (:import-from #:util/store/fset-index
                #:fset-set-index
                #:fset-unique-index)
  (:import-from #:bknr.indices
                #:index-get)
  (:import-from #:util/store/object-id
                #:find-by-oid
                #:object-with-oid)
  (:import-from #:screenshotbot/user-api
                #:can-view)
  (:export
   #:find-or-create-batch
   #:batch-items
   #:batch-item-channel))
(in-package :screenshotbot/model/batch)

(defindex +lookup-index+
  'fset-unique-index
  :slots '(%commit %company %repo))

(with-class-validation
  (defclass batch (object-with-oid)
    ((%company :initarg :company
               :reader company)
     (%repo :initarg :repo
            :reader repo)
     (%commit :initarg :commit
              :reader commit))
    (:metaclass persistent-class)
    (:class-indices
     (lookup-index
      :index +lookup-index+
      :slots (%commit %company %repo)))))

(defindex +batch-item-index+
  'fset-set-index
  :slot-name 'batch)

(with-class-validation
  (defclass batch-item (store-object)
    ((batch :initarg :batch
            :reader batch
            :index +batch-item-index+
            :index-reader batch-items)
     (%channel :initarg :channel
               :reader batch-item-channel)
     (%acceptable :initarg :acceptable
                  :reader acceptable)
     (%run :initarg :run
           :reader run)
     (%report :initarg :report
              :reader report))
    (:metaclass persistent-class)))

(defvar *lock* (bt:make-lock))

(defun find-or-create-batch (company repo commit)
  (bt:with-lock-held (*lock*)
    (or
     (index-get +lookup-index+ (list commit company repo))
     (make-instance 'batch
                    :company company
                    :repo repo
                    :commit commit))))


(defun find-batch-item (batch &key channel)
  (fset:do-set (item (batch-items batch))
    (when (eql (batch-item-channel item) channel)
      (return item))))

(defmethod can-view ((self batch) user)
  (can-view (company self) user))
