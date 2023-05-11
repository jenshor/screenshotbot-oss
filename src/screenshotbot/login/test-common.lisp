;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/login/test-common
  (:use #:cl
        #:fiveam)
  (:import-from #:screenshotbot/installation
                #:multi-org-feature
                #:installation
                #:*installation*)
  (:import-from #:screenshotbot/model/company
                #:company
                #:prepare-singleton-company
                #:get-singleton-company)
  (:import-from #:screenshotbot/user-api
                #:user
                #:current-company)
  (:import-from #:util/store
                #:with-test-store)
  (:import-from #:screenshotbot/model/user
                #:user-personal-company
                #:make-user)
  (:import-from #:screenshotbot/login/common
                #:most-recent-company
                #:guess-best-company)
  (:import-from #:screenshotbot/model/recorder-run
                #:recorder-run)
  (:import-from #:bknr.datastore
                #:with-transaction)
  (:local-nicknames (#:a #:alexandria)))
(in-package :screenshotbot/login/test-common)


(util/fiveam:def-suite)

(def-fixture state ()
  (with-test-store ()
    (cl-mock:with-mocks ()
      (&body))))

(test current-company-for-common
  (with-fixture state ()
    (cl-mock:answer
        (auth:session-value :company)
      nil)
    (let ((*installation* (make-instance 'installation)))
      (prepare-singleton-company)
      (is-true (get-singleton-company *installation*))
      (is-true (guess-best-company nil (make-instance 'user))))))

(defclass multi-org (multi-org-feature
                     installation)
  ())

(test current-company-for-multi-org
  (with-fixture state ()
    (let* ((*installation* (make-instance 'multi-org))
           (user (make-user))
           (company (user-personal-company user)))
      (is (eql company (guess-best-company company user)) ))) ())


(test most-recent-company
  (with-fixture state ()
    (let ((company-1 (make-instance 'company)))
      (is (eql nil (most-recent-company (list company-1))))
      (let ((run (make-instance 'recorder-run
                     :screenshot-map nil
                     :company company-1)))
        (is (eql company-1 (most-recent-company (list company-1))))))))
