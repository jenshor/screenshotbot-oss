;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(uiop:define-package :screenshotbot/model/view
  (:use #:cl
        #:screenshotbot/user-api
        #:alexandria)
  (:import-from #:screenshotbot/server
                #:no-access-error
                #:error-user
                #:error-obj)
  (:import-from #:screenshotbot/model/company
                #:company)
  (:export
   #:can-view
   #:can-view!
   #:can-public-view
   #:is-user-id-same
   #:can-edit!
   #:can-edit))
(in-package :screenshotbot/model/view)

;; This file adds logic to check if a specific object can be viewed by
;; the given user

(defgeneric can-view (obj user))

(defgeneric can-public-view (obj))

(defmethod print-object ((e no-access-error) out)
  (format out "User ~S can't access ~S" (error-user e) (error-obj e)))

(defun is-user-id-same (obj top-user)
  (let ((company (company obj)))
    (loop for my-company in (user-companies top-user)
          if (eql my-company company)
            do (return t))))

(defun can-view! (&rest objects)
  (let ((user (current-user)))
    (dolist (obj objects)
      (unless (or
               (can-public-view obj)
               (and user
                    (can-view obj user)))
        (restart-case
            (error 'no-access-error
                    :user user
                    :obj obj)
          (give-access-anyway ()
            nil))))))

(defmethod can-view :around (obj (user user))
  (or
   (call-next-method)
   ;; super-admins can access everything
   (adminp user)))

(defmethod can-edit! (&rest objects)
  (let ((user (current-user)))
    (dolist (obj objects)
      (unless (can-edit obj user)
        (error 'no-access-error :user user :obj obj)))))

(defmethod can-edit (obj user)
  nil)

(defmethod can-edit :around (obj user)
  (and
   user
   (can-view obj user)
   (call-next-method)))

(defmethod can-public-view (obj)
  nil)
