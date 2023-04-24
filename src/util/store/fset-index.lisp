;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :util/store/fset-index
  (:use #:cl)
  (:import-from #:bknr.indices
                #:index-reinitialize)
  (:import-from #:bknr.indices
                #:index-add)
  (:import-from #:bknr.indices
                #:index-get)
  (:import-from #:bknr.indices
                #:index-clear)
  (:import-from #:bknr.indices
                #:index-remove)
  (:import-from #:bknr.indices
                #:index-values)
  (:export
   #:fset-set-index
   #:fset-unique-index))
(in-package :util/store/fset-index)

(defclass abstract-fset-index ()
  ((slot-name :initarg :slots
              :reader %slots)
   (map :initform (fset:empty-map)
        :accessor %map)))

(defmacro update-map (self (map) &body expr)
  `(atomics:atomic-update
    (slot-value ,self 'map)
    (lambda (,map)
      ,@expr)))

(defun %slot-name (self)
  (car (%slots self)))

(defmethod index-reinitialize ((new-index abstract-fset-index)
                               (old-index abstract-fset-index))
  (update-map new-index (map)
    (declare (ignore map))
    (%map old-index))
  new-index)


(defclass fset-unique-index (abstract-fset-index)
  ())

(defclass fset-set-index (abstract-fset-index)
  ((map :initform (fset:empty-map (fset:empty-set)))))

(defmethod index-add :around ((self abstract-fset-index) obj)
  (when (slot-boundp obj (%slot-name self))
    (call-next-method)))

(defmethod index-add ((self fset-unique-index)
                      obj)
  (update-map self (map)
    (fset:with map
               (slot-value obj (%slot-name self))
               obj)))

(defmethod index-add ((self fset-set-index)
                      obj)
  (let ((key (slot-value obj (%slot-name self))))
    (update-map self (map)
      (fset:with map
                 key
                 (fset:with
                  (fset:lookup map key)
                  obj)))))

(defmethod index-get ((self abstract-fset-index) key)
  (fset:lookup (%map self) key))

(defmethod index-clear ((self abstract-fset-index))
  (update-map self (map)
    (declare (ignore map))
    (fset:empty-map)))

(defmethod index-clear ((self fset-set-index))
  (update-map self (map)
    (declare (ignore map))
    (fset:empty-map (fset:empty-set))))

(defmethod index-remove ((self fset-unique-index)
                         obj)
  (update-map self (map)
    (fset:less map
               (slot-value obj (%slot-name self)))))

(defmethod index-remove ((self fset-set-index) obj)
  (let ((key (slot-value obj (%slot-name self))))
    (update-map self (map)
      (fset:with map
                 key
                 (fset:less
                  (fset:lookup map key)
                  obj)))))


(defmethod index-values ((self abstract-fset-index))
  (labels ((build-values (map result)
             (cond
               ((fset:empty? map)
                result)
               (t
                (multiple-value-bind (key val) (fset:arb map)
                  (build-values
                   (fset:less map key)
                   (fset:union
                    (%index-values-for-key self val)
                    result)))))))
    (fset:convert 'list (build-values (%map self) (fset:empty-set)))))

(defmethod %index-values-for-key ((self fset-unique-index) val)
  (fset:with (fset:empty-set) val))

(defmethod %index-values-for-key ((self fset-set-index) val)
  val)
