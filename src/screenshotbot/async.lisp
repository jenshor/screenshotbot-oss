;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/async
  (:use #:cl)
  (:import-from #:easy-macros
                #:def-easy-macro)
  (:import-from #:server
                #:*shutdown-hooks*)
  (:import-from #:util/threading
                #:make-thread
                #:max-pool)
  (:import-from #:lparallel.promise
                #:promise)
  (:local-nicknames (#:a #:alexandria))
  (:export
   #:define-channel
   #:with-screenshotbot-kernel
   #:sb/future
   #:*magick-pool*))
(in-package :screenshotbot/async)

(defvar *kernel* nil)

(defvar *magick-pool* nil)

(defun reinit-pool ()
  (setf *magick-pool* (make-instance 'max-pool :max (serapeum:count-cpus :default 4))))

(reinit-pool)

#+lispworks
(lw:define-action "When starting image" "Reset magick pool"
  #'reinit-pool)

(defvar *kernel-lock* (bt:make-lock))

(defvar *channel-lock* (bt:make-lock))

(defun async-kernel ()
  "Lazily create the kernel if not already created"
  (util:or-setf
   *kernel*
   (lparallel:make-kernel 20 :name "screenshotbot-kernel")
   :thread-safe t
   :lock *kernel-lock*))

(defun make-channel (&rest args)
  (let ((lparallel:*kernel* (async-kernel)))
    (apply #'lparallel:make-channel args)))

(def-easy-macro with-screenshotbot-kernel (&fn fn)
  "Bind lparallel:*kernel* to the screenshotbot kernel"
  (let ((lparallel:*kernel* (async-kernel)))
    (funcall fn)))

(defmacro define-channel (name &rest args)
  "Define a symbol-macro that lazily evaulates to a valid channel,
 creating the kernel if required."
  (let ((var (intern (format nil "*~a-VAR*" (string name))))
        (fun (intern (format nil "~a-CREATOR" (string name)))))
    `(progn
       (defvar ,var nil)
       (defun ,fun ()
         (util:or-setf
          ,var
          (with-screenshotbot-kernel ()
           (lparallel:make-channel ,@args))
          :thread-safe t
          :lock *channel-lock*))
       (define-symbol-macro ,name
           (,fun)))))

(def-easy-macro sb/future (&fn fn)
  (with-screenshotbot-kernel ()
    (lparallel:future
      (funcall fn))))

(defun shutdown ()
  "Safely shutdown the kernel. Called from server/setup.lisp."
  (when *kernel*
    (with-screenshotbot-kernel ()
      (log:info "Shutting down: screenshotbot lparallel kernel")
      (lparallel:end-kernel :wait t)
      (setf *kernel* nil)
      (log:info "Done: screenshotbot lparallel kernel"))))

(pushnew 'shutdown *shutdown-hooks*)

(def-easy-macro magick-future (&fn fn)
  (let ((promise (lparallel:promise)))
    (prog1
        promise
      (make-thread
       (lambda ()
         (lparallel:fulfill promise (fn)))
       :pool *magick-pool*))))
