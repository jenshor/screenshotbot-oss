(defpackage :screenshotbot/pro/bitbucket/test-audit-log
  (:use #:cl
        #:fiveam)
  (:import-from #:screenshotbot/pro/bitbucket/audit-log
                #:audit-log-error
                #:parse-error-response
                #:audit-log)
  (:import-from #:util/store
                #:with-test-store)
  (:import-from #:screenshotbot/pro/bitbucket/core
                #:bitbucket-error)
  (:local-nicknames (#:a #:alexandria)))
(in-package :screenshotbot/pro/bitbucket/test-audit-log)


(util/fiveam:def-suite)

(def-fixture state ()
  (with-test-store ()
    (&body)))

(test test-parses-error-correctly
  (with-fixture state ()
   (let ((response (uiop:read-file-string
                    (asdf:system-relative-pathname
                     :screenshotbot "bitbucket/error-response-1.json")))
         (audit-log (make-instance 'audit-log)))
     (signals bitbucket-error
      (parse-error-response
       response
       500
       audit-log))
     (is (equal
          "key: Ensure this value has at most 40 characters (it has 44)."
          (audit-log-error audit-log))))))
