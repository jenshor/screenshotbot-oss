;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/api/test-finalized-commit
  (:use #:cl
        #:fiveam
        #:fiveam-matchers)
  (:import-from #:screenshotbot/api/finalized-commit
                #:%post-finalized-commit
                #:%parse-body)
  (:import-from #:util/store/store
                #:with-test-store)
  (:import-from #:cl-mock
                #:answer)
  (:import-from #:screenshotbot/testing
                #:with-test-user)
  (:import-from #:screenshotbot/model/finalized-commit
                #:commit-finalized-p
                #:finalized-commit)
  (:local-nicknames (#:dto #:screenshotbot/api/model)))
(in-package :screenshotbot/api/test-finalized-commit)

(util/fiveam:def-suite)

(def-fixture state ()
  (cl-mock:with-mocks ()
    (with-test-store ()
      (&body))))

(test simple-post
  (with-fixture state ()
    (let ((dto (make-instance 'dto:finalized-commit
                              :commit "abcd0000")))
      (answer (%parse-body)
        dto)
      (with-test-user (:logged-in-p t :company company)
        (finishes (%post-finalized-commit))
        (is (eql 1 (length (bknr.datastore:class-instances
                            'finalized-commit))))
        (is-true (commit-finalized-p company "abcd0000"))))))
