;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/sdk/main
  (:use #:cl)
  (:import-from #:screenshotbot/sdk/help
                #:help)
  (:import-from #:screenshotbot/sdk/sdk
                #:chdir-for-bin)
  (:import-from #:util/threading
                #:maybe-log-sentry
                #:*warning-count*
                #:with-extras
                #:*extras*
                #:funcall-with-sentry-logs)
  (:import-from #:screenshotbot/sdk/version-check
                #:*client-version*
                #:with-version-check)
  (:import-from #:util/health-check
                #:def-health-check
                #:run-health-checks)
  (:import-from #:easy-macros
                #:def-easy-macro)
  (:import-from #:screenshotbot/sdk/failed-run
                #:mark-failed)
  (:import-from #:screenshotbot/sdk/unchanged-run
                #:mark-unchanged-run)
  (:import-from #:screenshotbot/sdk/finalized-commit
                #:finalize-commit)
  (:import-from #:screenshotbot/sdk/api-context
                #:api-context
                #:desktop-api-context)
  (:import-from #:screenshotbot/sdk/hostname
                #:api-hostname)
  (:import-from #:screenshotbot/sdk/env
                #:make-env-reader)
  (:import-from #:screenshotbot/sdk/common-flags
                #:define-flag)
  (:import-from #:com.google.flag
                #:parse-command-line)
  (:local-nicknames (#:a #:alexandria)
                    (#:flags #:screenshotbot/sdk/flags)
                    (#:e #:screenshotbot/sdk/env)
                    (#:sdk #:screenshotbot/sdk/sdk)
                    (#:static #:screenshotbot/sdk/static)
                    (#:firebase #:screenshotbot/sdk/firebase))
  ;; TODO: delete
  (:import-from #:screenshotbot/sdk/common-flags
                #:*api-key*
                #:*hostname*
                #:*api-secret*)
  (:export
   #:main))
(in-package :screenshotbot/sdk/main)

(define-flag *api-key*
  :selector "api-key"
  :default-value nil
  :type (or null string)
  :help "Screenshotbot API Key. Defaults to $SCREENSHOTBOT_API_KEY.")

(define-flag *api-secret*
  :selector "api-secret"
  :default-value nil
  :type (or null string)
  :help "Screenshotbot API Secret. Defaults to $SCREENSHOTBOT_API_SECRET")

(define-flag *hostname*
  :selector "api-hostname"
  :default-value ""
  :type string
  :help "Screenshotbot API Endpoint"
  :documentation "Only used for Enterprise or Open Source users, Defaults to `https://api.screenshotbot.io` or $SCREENSHOTBOT_API_HOSTNAME")


(def-easy-macro with-defaults (&binding api-context &fn fn)
  (sdk:parse-org-defaults)
  (let ((api-context (make-api-context)))
    (with-version-check (api-context)
      (funcall fn api-context))))

(defun emptify (s)
  "If the string is empty, return nil"
  (if (str:emptyp s) nil s))


(defun make-api-context ()
  (let ((env (make-env-reader)))
    (cond
      (flags:*desktop*
       (make-instance 'desktop-api-context))
      (t
       (let ((key (or (emptify *api-key*)
                      (e:api-key env)))
             (secret (or (emptify *api-secret*)
                         (e:api-secret env))))
         (when (str:emptyp key)
           (error "No --api-key provided"))
         (when(str:emptyp secret)
           (error "No --api-secret provided"))
         (let ((hostname (api-hostname
                          :hostname (or (emptify *hostname*)
                                        (emptify (e:api-hostname env))
                                        "https://api.screenshotbot.io"))))
           (log:debug "Using hostname: ~a" hostname)
           (make-instance 'api-context
                          :key key
                          :secret secret
                          :hostname hostname)))))))

(defun %main (&optional (argv #+lispworks system:*line-arguments-list*
                              #-lispworks (uiop:command-line-arguments)))
  (log:config :sane :immediate-flush t)
  (log:config :info)

  (log:info "Screenshotbot SDK v~a" *client-version*)
  (let ((unrecognized  (parse-command-line (cdr argv))))
    (when flags:*verbose*
      (log:config :debug))
    (log:debug "Run this in interactive shell: ~S"
               `(progn
                  (chdir-for-bin ,(uiop:getcwd))
                  (%main ',argv)))
    (cond
      (unrecognized
       (format t "Unrecognized arguments: ~a~%" (Str:join " " unrecognized))
       (help)
       (uiop:quit 1))
      (flags:*help*
       (help))
      (flags:*versionp*
       ;; We've already printed the version by this point
       nil)
      (flags:*self-test*
       (uiop:quit (if (run-health-checks) 0 1)))
      (flags:*mark-failed*
       (with-defaults (api-context)
         (mark-failed api-context)))
      (flags:*unchanged-from*
       (with-defaults (api-context)
         (mark-unchanged-run api-context)))
      (flags:*ios-multi-dir*
       (sdk:parse-org-defaults)
       (sdk:run-ios-multi-dir-toplevel))
      (flags:*static-website*
       (with-defaults (api-context)
         ;; TODO: use context here
         (static:record-static-website flags:*static-website*)))
      (flags:*firebase-output*
       (firebase:with-firebase-output (flags:*firebase-output*)
         (with-defaults (api-context)
           (sdk:run-prepare-directory-toplevel api-context))))
      (flags:*finalize*
       (with-defaults (api-context)
         (finalize-commit api-context)))
      (t
       (with-defaults (api-context)
         (sdk:run-prepare-directory-toplevel api-context))))))

(def-easy-macro with-sentry (&key (on-error (lambda ()
                                              (uiop:quit 1)))
                                  (dry-run nil)
                                  (stream
                                   #+lispworks
                                   (system:make-stderr-stream)
                                   #-lispworks
                                   *standard-output*)
                                  &fn fn)
  #-screenshotbot-oss
  (sentry-client:initialize-sentry-client
   sentry:*dsn* :client-class 'sentry:delivered-client)
  (with-extras (("api_hostname" *hostname*)
                ("api_id"  *api-key*)
                ("features" *features*)
                ("channel" flags:*channel*)
                ("build-url" flags:*build-url*)
                ("hostname" (uiop:hostname))
                #+lispworks
                ("openssl-version" (comm:openssl-version)))
   (let ((error-handler (lambda (e)
                          (format stream "~%~a~%~%" e)
                          #+lispworks
                          (dbg:output-backtrace (if flags:*verbose* :bug-form :brief)
                                                :stream stream)
                          #-lispworks
                          (trivial-backtrace:print-backtrace e stream)
                          (unless dry-run
                            #-screenshotbot-oss
                            (util/threading:log-sentry e))
                          (funcall on-error))))
     (let ((*warning-count* 0))
       (handler-bind (#+lispworks
                      (error error-handler))
         ;; We put the warning handler inside here, so that if an
         ;; error happens in the warning handler, we can log that.
         (handler-bind (#+lispworks
                        (warning #'maybe-log-sentry))
          (funcall fn)))))))

(defun main (&rest args)
  (uiop:setup-command-line-arguments)

  (with-sentry ()
    (apply '%main args))

  #-sbcl
  (log4cl::exit-hook)
  (uiop:quit 0))

#-screenshotbot-oss
(def-health-check sentry-logger ()
  (let ((out-stream (make-string-output-stream)))
    (restart-case
        (with-sentry (:on-error (lambda ()
                                  (invoke-restart 'expected))
                      :stream out-stream
                      :dry-run t)
          (error "health-check for sdk"))
     (expected ()
       nil))
    (assert (cl-ppcre:scan ".*RUN-HEALTH-CHECKS.*"
                           (get-output-stream-string out-stream)))))

#+nil ;; too noisy, and less important
(def-health-check sentry-logger-for-warnings ()
  (let ((out-stream (make-string-output-stream)))
    (with-sentry (:dry-run t)
      (warn "warning health-check for sdk"))))
