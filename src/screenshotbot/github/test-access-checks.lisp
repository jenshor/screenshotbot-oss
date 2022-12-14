;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(uiop:define-package :screenshotbot/github/test-access-checks
  (:use #:cl
        #:fiveam
        #:screenshotbot/github/access-checks
        #:screenshotbot/user-api)
  (:import-from #:screenshotbot/github/access-checks
                #:get-repo-stars
                #:repo-string-identifier)
  (:import-from #:util/mock-recording
                #:track
                #:with-recording))
(in-package :screenshotbot/github/test-access-checks)

(util/fiveam:def-suite)

#-sbcl ;; java
(test simple-creation
  (finishes
    (github-client)))


(test github-repo-commit-link
  (is (equal
       "https://github.com/tdrhq/web/commit/abcd12"
       (commit-link
        (make-instance 'github-repo
                        :link "https://github.com/tdrhq/web")
        "abcd12")))
  (is (equal
       "https://github.com/tdrhq/web/commit/abcd12"
       (commit-link
        (make-instance 'github-repo
                        :link "https://github.com/tdrhq/web.git")
        "abcd12")))
  (is (equal
       "https://github.com/tdrhq/web/commit/abcd12"
       (commit-link
        (make-instance 'github-repo
                        :link "git@github.com:tdrhq/web")
        "abcd12")))
  (is (equal
       "https://github.com/tdrhq/web/commit/abcd12"
       (commit-link
        (make-instance 'github-repo
                        :link "git@github.com:tdrhq/web.git")
        "abcd12"))))

(test repo-string-identifier
  (is (equal "tdrhq/fast-example"
             (repo-string-identifier "https://github.com/tdrhq/fast-example")))
  (is (equal "tdrhq/fast-example"
             (repo-string-identifier "git@github.com.com:tdrhq/fast-example")))
  (is (equal "tdrhq/fast-example"
             (repo-string-identifier "git@github.com.com:tdrhq/fast-example.git"))))

(test get-repo-stars ()
  (with-recording ((asdf:system-relative-pathname :screenshotbot "github/fixture/get-repo-stars.rec"))
    (track 'github-api-request :skip-args '(2))
    (is (equal (list 42 2)
               (multiple-value-list
                (get-repo-stars "tdrhq" "slite"))))))
