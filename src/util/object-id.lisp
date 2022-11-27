;; Copyright 2018-Present Modern Interpreters Inc.
;;
;; This Source Code Form is subject to the terms of the Mozilla Public
;; License, v. 2.0. If a copy of the MPL was not distributed with this
;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage #:util/object-id
  (:use #:cl
        #:bknr.datastore)
  (:import-from #:bknr.indices
                #:unique-index)
  (:import-from #:util/store
                #:location-for-oid
                #:defindex)
  (:export #:object-with-oid
	   #:object-with-unindexed-oid
	   #:find-by-oid
	   #:oid
       #:oid-array
       #:creation-time-from-oid))
(in-package #:util/object-id)

(defstruct oid
  "An object to efficiently represent a Mongo Object-ID. As of 11/27/22,
 this isn't being used but will be soon."
  (arr))

(defmethod bknr.datastore::encode-object ((self oid) stream)
  ;; M for MongoId, O is being used!
  (bknr.datastore::%write-tag #\M stream)
  (write-sequence (oid-arr self) stream))

(defmethod bknr.datastore::decode-object ((tag (eql #\M)) stream)
  (let ((arr (make-array 12 :element-type '(unsigned-byte 8))))
    (read-sequence arr stream)
    (make-oid :arr arr)))

(defun %make-oid ()
  (make-oid
   :arr
   (mongoid:oid)))

(defindex +oid-index+ 'unique-index
  :test 'equalp
  :slot-name 'oid)

;;;; reloading this object is bad. I thought I had fixed this, but
;;;; it's still buggy inside of my patched version of bknr.datastore
(defclass object-with-oid (store-object)
  ((oid
    :initarg :oid
    :reader oid-struct-or-array
    :index +oid-index+
    :index-reader %find-by-oid))
  (:metaclass persistent-class))

(defmethod initialize-instance :around ((obj object-with-oid)
                                        &rest args
                                        &key oid
                                        &allow-other-keys)
  (cond
    (oid
     (call-next-method))
    (t
     (apply #'call-next-method obj :oid (%make-oid) args))))

(defmethod oid-array ((self object-with-oid))
  (let ((ret (oid-struct-or-array self)))
    (cond
      ((oid-p ret) (oid-arr ret))
      (t ret))))

(defclass object-with-unindexed-oid (store-object)
  ((oid
    :initform (%make-oid)
    :accessor oid-bytes))
  (:metaclass persistent-class))

(defun find-by-oid (oid &optional type)
  "oid can be an array, a string, or an object of type OID"
  (let* ((arr (if (oid-p oid)
                  (oid-arr oid)
                  (mongoid:oid oid)))
         (obj (or
               (%find-by-oid
                (make-oid :arr arr))
               ;; For backward compatibility
               (%find-by-oid arr))))
    (when type
      (unless (typep obj type)
        (error "Object ~s isn't of type ~s" obj type)))
    obj))

(#+lispworks defconstant
 #-lispworks defparameter +e+ "0123456789abcdef")

(defun fast-oid-str (oid)
  (declare (optimize (speed 3)
                     (debug 0)
                     (safety 0))
           (type (array (unsigned-byte 8))))
  (let ((hex-string (make-string 24)))
    (loop for i fixnum from 0 below 12
          do (let ((out (* 2 i)))
               (multiple-value-bind (top left) (floor (aref oid i) 16)
                 (setf (aref hex-string out)
                       (aref +e+ top))
                 (setf (aref hex-string (1+ out))
                       (aref +e+ left)))))
    hex-string))

;; COPYPASTA from scheduled-jobs
;;;;;;;;;;;;;;;;;;;;;;
;; https://lisptips.com/post/11649360174/the-common-lisp-and-unix-epochs
(defvar *unix-epoch-difference*
  (encode-universal-time 0 0 0 1 1 1970 0))

(defun universal-to-unix-time (universal-time)
  (- universal-time *unix-epoch-difference*))

(defun unix-to-universal-time (unix-time)
  (+ unix-time *unix-epoch-difference*))

(defun get-unix-time ()
  (universal-to-unix-time (get-universal-time)))
;;;;;;;;;;;;;;;;;;;;;;;

(defmethod creation-time-from-oid ((object object-with-oid))
  (let* ((oid-arr (oid-array object))
         (unix (cl-mongo-id:get-timestamp oid-arr)))
    (unix-to-universal-time unix)))

(defmethod is-recent-p ((object object-with-oid) &key (days 14))
  (> (creation-time-from-oid object)
     (- (get-universal-time)
        (* days 24 3600))))

(defgeneric oid (obj))

(defmethod oid (obj)
  (fast-oid-str (oid-array obj)))

(defmethod location-for-oid ((root pathname) (oid oid) &key suffix)
  (location-for-oid
   root
   (oid-arr oid)
   :suffix suffix))
