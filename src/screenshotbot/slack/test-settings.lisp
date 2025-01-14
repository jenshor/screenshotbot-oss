;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/slack/test-settings
  (:use #:cl
        #:alexandria
        #:bknr.datastore
        #:fiveam
        #:screenshotbot/model
        #:screenshotbot/slack/core
        #:screenshotbot/slack/settings
        #:screenshotbot/login/common)
  (:import-from #:util/store
                #:with-test-store)
  (:import-from #:util/testing
                #:with-fake-request)
  (:import-from #:screenshotbot/installation
                #:*installation*
                #:installation
                #:multi-org-feature))
(in-package :screenshotbot/slack/test-settings)

(util/fiveam:def-suite)

(defclass my-installation (multi-org-feature
                           installation)
  ())

(def-fixture state ()
  (let ((*installation* (make-instance 'my-installation)))
   (with-test-store ()
     (with-fake-request ()
       (let* ((company (make-instance 'company))
              (token (make-instance 'slack-token
                                     :access-token "foo"
                                     :company company
                                     :ts 34)))
         (setf (auth:request-account hunchentoot:*request*)
               company)
         (&body))))))

(test posting-when-nothing-is-available ()
  (with-fixture state ()
    (catch 'hunchentoot::handler-done
      (post-settings-slack
       "#general"
       t))
    (is (eql token (access-token (default-slack-config company))))))
