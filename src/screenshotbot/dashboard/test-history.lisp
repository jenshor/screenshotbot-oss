;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(pkg:define-package :screenshotbot/dashboard/test-history
    (:use #:cl
          #:alexandria
          #:fiveam
          #:../screenshot-api
          #:../factory)
  (:import-from #:./history
                #:render-history)
  (:import-from #:util/testing
                #:with-fake-request)
  (:import-from #:screenshotbot/screenshot-api
                #:get-screenshot-history))

(util/fiveam:def-suite)

(defclass my-screenshot (test-screenshot)
  ())

(defmethod screenshot-image ((screenshot my-screenshot))
  (make-instance 'test-image))

(test simple-render-history
  (cl-mock:with-mocks ()
    (cl-mock:if-called 'get-screenshot-history
                        (lambda (channel screenshot-name)
                          (values
                           (list (make-instance 'my-screenshot
                                             :name "one")
                             (make-instance 'my-screenshot
                                             :name "one")
                             (make-instance 'my-screenshot
                                             :name "one"))
                           (list (make-instance 'test-recorder-run
                                                 :commit "one")
                                 (make-instance 'test-recorder-run
                                                 :commit "two")
                                 (make-instance 'test-recorder-run
                                                 :commit "three")))))
    (with-fake-request ()
      (auth:with-sessions ()
        (render-history
         :screenshot-name "foo"
         :channel (make-instance 'test-channel))))) ()
  (pass))
