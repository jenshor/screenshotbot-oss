;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/sdk/test-version-check
  (:use #:cl
        #:fiveam)
  (:import-from #:screenshotbot/sdk/version-check
                #:*remote-version*
                #:with-version-check
                #:get-version)
  (:import-from #:util/request
                #:http-request)
  (:import-from #:cl-mock
                #:answer)
  (:local-nicknames (#:a #:alexandria)))
(in-package :screenshotbot/sdk/test-version-check)


(util/fiveam:def-suite)

(test get-version
  (cl-mock:with-mocks ()
    (answer (http-request "https://api.screenshotbot.io/api/version"
                          :want-string t)
      (values "{\"version\":1}" 200))
    (is (eql 1 (get-version "https://api.screenshotbot.io")))))

(test get-version-404
  (cl-mock:with-mocks ()
    #+nil(answer (http-request "https://www.google.com/api/version"
                          :want-string t)
      "{\"version\":1}")
    (is (eql 1 (get-version "https://www.google.com")))))

(test with-version-check
  (cl-mock:with-mocks ()
    (answer (get-version "https://api.screenshotbot.io")
      189)
    (let ((ans))
      (with-version-check ()
       (setf ans *remote-version*))
      (is (eql 189 ans)))))