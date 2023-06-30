;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :test-auth
  (:use :cl
   :fiveam)
  (:import-from :util/testing
                :with-fake-request)
  (:import-from :auth
                #:generate-session-token
                #:csrf-token
   :fix-cookie-domain
   #+windows
   :read-windows-seed)
  (:import-from #:util/store
                #:with-test-store)
  (:export))
(in-package :test-auth)

(def-suite* :test-auth)

(def-fixture state ()
  (cl-mock:with-mocks ()
   (with-test-store ()
     (with-fake-request ()
       (&body)))))

(test auth-simple-test
  (with-fixture state ()
    (auth:with-sessions ()
      (is-true (auth:current-session))
      (is (equal (auth:current-session)
                 (auth:current-session))))))

(test simple-key-val
  (with-fixture state ()
    (auth:with-sessions ()
      (setf (auth:session-value :name)  33)
      (is (equal 33 (auth:session-value :name)))
      (setf (auth:session-value :name) 44)
      (is (equal 44 (auth:session-value :name))))))

#+windows
(test read-windows-seed
  (is-true (read-windows-seed)))

(test fix-cookie-domain
  (is (equal "foo.com" (fix-cookie-domain "foo.com")))
  (is (equal "localhost" (fix-cookie-domain "localhost")))
  (is (equal "192.168.1.119" (fix-cookie-domain "192.168.1.119")))
  ;; We used to map www.foo.com to foo.com, but that logic is hard to
  ;; maintain
  (is (equal "www.foo.com" (fix-cookie-domain "www.foo.com")))
  (is (equal "192.168.1.120" (fix-cookie-domain "192.168.1.120"))))

(test csrf-token
  (with-fixture state ()
    (auth:with-sessions ()
     (cl-mock:answer (generate-session-token) "foobar"
       "bad")
      (is (equal "foobar" (auth:csrf-token)))
      (is (equal "foobar" (auth:csrf-token))))))
