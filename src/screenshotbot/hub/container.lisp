;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/hub/container
  (:use #:cl)
  (:local-nicknames (#:a #:alexandria)))
(in-package :screenshotbot/hub/container)

(defclass container ()
  ((cid :accessor container-id
        :initarg :container-id)))
(defmethod print-object ((self container) out)
  (format out "#<CONTAINER ~a>" (str:substring 0 8 (container-id self))))

(defun run* (args &key (output 'string))
  (uiop:run-program
   (mapcar (lambda (x)
             (if (pathnamep x) (namestring x) x))
           args)
   :error-output *standard-output*
   :output output))

(defun make-container (image &key port)
  (let ((args (list image)))
    (let ((container-id  (run*
                          (list* "docker" "run" "-d" args))))
      (make-instance 'container
                      :container-id (str:trim container-id)))))


(defmethod container-stop ((self container))
  (run* (list "docker" "stop" (container-id self))))
