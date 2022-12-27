;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/sdk/version-check
  (:use #:cl)
  (:import-from #:screenshotbot/api/model
                #:decode-json
                #:version-number
                #:version
                #:*api-version*)
  (:import-from #:easy-macros
                #:def-easy-macro)
  (:import-from #:util/request
                #:http-request)
  (:import-from #:screenshotbot/sdk/common-flags
                #:*hostname*)
  (:import-from #:util/health-check
                #:def-health-check)
  (:local-nicknames (#:a #:alexandria))
  (:export
   #:with-version-check))
(in-package :screenshotbot/sdk/version-check)

(defvar *remote-version* *api-version*)

(defun remote-supports-basic-auth-p ()
  "Prior to this version, the auth was passed as http parameters. That
wasn't great for security since it might mean the plain-text secret
might get logged in the webserver logs."
  (>= *remote-version* 2))

(defun get-version (hostname)
  (log:info "Getting remote version")
  (multiple-value-bind (body ret)
      (http-request
       (format nil "~a/api/version" hostname)
       :want-string t)
    (let ((version (cond
                     ((eql 200 ret)
                      (decode-json body 'version))
                     (t
                      (log:warn "/api/version responded 404, this is probably because of running an old version of OSS Screenshotbot service")
                      (make-instance 'version :version 1)))))
      (version-number version))))

(def-easy-macro with-version-check (&fn fn)
  (let ((*remote-version* (get-version *hostname*)))
    (when (/= *remote-version* *api-version*)
      (log:warn "Server is running API version ~a, but this client uses version ~a. ~%

This is most likely supported, however, it's more likely to have
bugs. If you're using OSS Screenshotbot, we suggest upgrading.
"
                *remote-version*
                *api-version*))
    (funcall fn)))


(def-health-check verify-can-decode-json ()
  (eql 10 (version-number (decode-json "{\"version\":10}" 'version))))