(defpackage :screenshotbot/api/test-core
  (:use #:cl
        #:fiveam)
  (:import-from #:screenshotbot/api/core
                #:result
                #:api-error
                #:error-result-message
                #:error-result-stacktrace
                #:with-error-handling
                #:with-api-key
                #:defapi)
  (:import-from #:cl-mock
                #:if-called
                #:answer
                #:with-mocks)
  (:import-from #:fiveam-matchers/core
                #:assert-that
                #:equal-to)
  (:import-from #:fiveam-matchers/described-as
                #:described-as)
  (:import-from #:fiveam-matchers/strings
                #:contains-string)
  (:import-from #:util/json-mop
                #:json-mop-to-string)
  (:local-nicknames (#:a #:alexandria)))
(in-package :screenshotbot/api/test-core)


(util/fiveam:def-suite)

(defapi (%dummy-1 :uri "/api/dummy") ()
  "OK")

(test returns
  (is (equal "OK" (%dummy-1))))

(defapi (%dummy-2 :uri "/api/dummy-2") (name)
  (format nil "OK ~a" name))

(test simple-param
  (is (equal "OK zoidberg"
             (%dummy-2 :name "zoidberg"))))

(defapi (%dummy-with-int :uri "/api/dummy-2") ((name :parameter-type 'integer))
  (format nil "OK ~d" name))

(test dummy-with-int
  (is (equal "OK 3"
             (%dummy-with-int :name 3))))

(define-condition my-error (error)
  ())

(test with-api-key-for-parameters
  (with-mocks ()
    (answer (hunchentoot:authorization) nil)
    (answer (hunchentoot:parameter "api-key")  "foo")
    (answer (hunchentoot:parameter "api-secret-key") "bar")
    (with-api-key (key secret)
      (is (equal "foo" key))
      (is (equal "bar" secret)))))

(test with-api-key-for-authorization
  (with-mocks ()
    (answer (hunchentoot:authorization)
      (values "foo" "bar"))
    (with-api-key (key secret)
      (is (equal "foo" key))
      (is (equal "bar" secret)))))

(test internal-error-gets-logged
  (with-mocks ()
    (let ((calledp nil))
      (if-called 'sentry-client:capture-exception
                 (lambda (e)
                   (setf calledp t)))
      (let ((message
              (with-error-handling ()
                (error 'my-error))))

        #+lispworks
        (assert-that (error-result-stacktrace message)
                     (contains-string "FIVEAM" ))
        (assert-that (error-result-message message)
                     (contains-string "Internal error"))
        (assert-that calledp
                     (described-as
                         "capture-exception should've been called"
                       (equal-to t)))))))


(test api-error-is-propagated-but-not-logged
  (with-mocks ()
    (let ((calledp nil))
      (if-called 'sentry-client:capture-exception
                 (lambda (e)
                   (setf calledp t)))
      (let ((message
              (with-error-handling ()
                (error 'api-error :message "bleh bleh"))))

        #+lispworks
        (assert-that (error-result-stacktrace message)
                     (contains-string "FIVEAM" ))
        (assert-that (error-result-message message)
                     (equal-to "bleh bleh"))
        (assert-that calledp
                     (described-as
                         "capture-exception should not be called"
                       (equal-to nil)))))))


(test api-result-can-be-encoded
  (assert-that (json-mop-to-string (make-instance 'result :success t))
               (contains-string "success")))
