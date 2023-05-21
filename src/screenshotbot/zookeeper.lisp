;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/zookeeper
  (:use #:cl)
  (:import-from #:easy-macros
                #:def-easy-macro))
(in-package :screenshotbot/zookeeper)

(fli:register-module :zookeeper
                     :file-name "libzookeeper_mt.so")

(fli:define-c-struct z-handle-t)

(fli:define-c-struct string-vector
    (count :int32)
  (data (:pointer (:pointer :char))))

(fli:define-foreign-function (deallocate-string-vector "deallocate_String_vector")
    ((sv (:pointer string-vector)))
  :result-type :int)

(fli:define-foreign-function (allocate-string-vector "allocate_String_vector")
  ()
  :result-type (:pointer string-vector))


(defvar *next-id* 1)

(defvar *lock* (bt:make-recursive-lock))

(defvar *zks* (make-hash-table)
  "Mapping from pointer addresses to zk objects")

(defclass zk ()
  ((state :initarg :state
          :reader zk-state)
   (connected-cv :initform (bt:make-condition-variable)
                 :reader connected-cv)
   (handle :initarg :handle
           :accessor handle)))

(defun zhandle-to-zk (zzh)
  (bt:with-recursive-lock-held (*lock*)
    (gethash (fli:pointer-address zzh) *zks*)))

(fli:define-foreign-converter zk () object
  :foreign-type '(:pointer :void)
  :foreign-to-lisp `(zhandle-to-zk ,object)
  :lisp-to-foreign `(handle ,object))

(defun sym (name)
  (fli:dereference
   (fli:make-pointer :symbol-name (str:replace-all "-" "_" (string name))
                     :type :int)))

(defun zoo-connected-state ()
  (sym :zoo-connected-state))


(fli:define-foreign-callable ("sb_zookeeper_watcher_cb"
                              :result-type :void)
    ((zk zk)
     (type :int)
     (state :int)
     (path (:pointer :char))
     (context :pointer))
  (declare (ignore path context type))
  (cond
    ((and
      zk
      (eql state (sym :zoo-connected-state)))
     (log:info "Connected for ~a" zk)
     (bt:with-recursive-lock-held (*lock*)
       (bt:condition-notify (connected-cv zk))))
    (t
     (log:warn "Got notification for unknown zookeeper instance"))))

(fli:define-foreign-function zookeeper-init
    ((host (:reference-pass :ef-mb-string))
     (watcher-fn :pointer)
     (recv-timeout :int)
     (context :pointer)
     (flags :int))
  :result-type (:pointer z-handle-t))

(fli:define-foreign-callable "sb_zookeeper_aget_cb"
    ((rc :int)
     (result (:pointer string-vector))
     (zk zk))
  (log:info "Got an aget_child callback on ~S, ~a" zk rc)
  (get-children-results zk (loop for i below (fli:foreign-slot-value result 'count)
                                 collect (fli:convert-from-foreign-string
                                          (fli:dereference
                                           (fli:foreign-slot-value result 'data)
                                           :index i)))))

(defmethod get-children-results ((zk zk) results)
  (log:info "Got results: ~S" results))

(fli:define-foreign-function zoo-aget-children
    ((zk zk)
     (path (:reference-pass :ef-mb-string))
     (watch :int)
     (callback :pointer)
     (context zk)))

(defun get-children (zk path)
  (zoo-aget-children zk
                     path
                     0
                     (fli:make-pointer :symbol-name "sb_zookeeper_aget_cb")
                     zk))

(def-easy-macro with-zookeeper (&binding zk &key host
                                         (recv-timeout 30000)
                                         (flags 0)
                                         &fn fn)
  (let ((zk (make-instance 'zk))
        zhandle-t)
    (bt:with-recursive-lock-held (*lock*)
      (setf zhandle-t (zookeeper-init
                        host
                        (fli:make-pointer :symbol-name "sb_zookeeper_watcher_cb")
                        recv-timeout
                        nil ;; context
                        flags))
      (log:info "Got zhandle: ~a ~a" zhandle-t (bt:current-thread))
      (setf (gethash (fli:pointer-address zhandle-t)
                     *zks*)
            zk)
      (setf (handle zk) zhandle-t)
      (bt:condition-wait (connected-cv zk) *lock*))
    (unwind-protect
         (funcall fn zk)
      (log:info "Closing out zookeeper")
      (bt:with-recursive-lock-held (*lock*)
       (remhash (fli:pointer-address zhandle-t) *zks*)))))


#+nil
(zookeeper-init "192.168.1.143:2181" (fli:make-pointer :symbol-name "sb_zookeeper_watcher_cb") 3000 nil 0)

#+nil
(with-zookeeper (zk :host "192.168.1.143:2181")
  (log:info "hello")
  (get-children zk "/"))
