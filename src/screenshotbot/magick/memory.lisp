;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/magick/memory
  (:use #:cl)
  (:local-nicknames (#:a #:alexandria))
  (:export
   #:update-magick-memory-methods))
(in-package :screenshotbot/magick/memory)

(defclass allocation-info ()
  ((size :initarg :size)))

(defvar *allocs* (make-hash-table))

(fli:define-foreign-function (%malloc "malloc")
  ((size :size-t))
  :result-type (:pointer :void))

(fli:define-foreign-function (%realloc "realloc")
  ((ptr (:pointer :void))
   (size :size-t))
  :result-type (:pointer :void))

(fli:define-foreign-function (%free "free")
  ((ptr (:pointer :void)))
  :result-type :void)


(defun add-info (mem size)
  (setf (gethash (fli:pointer-address mem) *allocs*)
        (make-instance 'allocation-info
                        :size size)))

(defun malloc (size)
  (log:debug "Allocation ~d" size)
  (let ((mem (%malloc size)))
    (add-info mem size)
    mem))

(fli:define-foreign-callable ("screenshotbot_malloc" :result-type (:pointer :void))
    ((size :size-t))
  (malloc size))

(defun clear-info (ptr)
  (remhash (fli:pointer-address ptr) *allocs*))

(defun free (ptr)
  (log:debug "Freeing ~a" ptr)
  (clear-info ptr)
  (%free ptr))

(fli:define-foreign-callable ("screenshotbot_free" :result-type :void)
    ((ptr (:pointer :void)))
  (free size))

(defun realloc (ptr size)
  (log:info "Realloc ~d" size)
  (let ((ret (%realloc ptr size)))
    (clear-info ptr)
    (add-info ret size)
    ret))

(fli:define-foreign-callable ("screenshotbot_realloc" :result-type :void)
    ((ptr (:pointer :void))
     (size :size-t))
  (realloc ptr size))

(fli:define-foreign-function (set-magick-memory-methods
                              "SetMagickMemoryMethods")
    ((acquire-memory-handler (:pointer :void))
     (resize-memory-handler (:pointer :void))
     (destroy-memory-handler (:pointer :void)))
  :result-type :void)

(defun update-magick-memory-methods ()
  (flet ((ptr (name)
           (let ((ret (fli:make-pointer :symbol-name name)))
             (assert (not (fli:null-pointer-p ret)))
             ret)))
    (set-magick-memory-methods
     (ptr "screenshotbot_malloc")
     (ptr "screenshotbot_realloc")
     (ptr "screenshotbot_free"))))