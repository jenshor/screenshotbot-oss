;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/sdk/finalized-commit
  (:use #:cl)
  (:import-from #:screenshotbot/sdk/git
                #:current-commit
                #:git-repo)
  (:local-nicknames (#:flags #:screenshotbot/sdk/flags)
                    (#:sdk #:screenshotbot/sdk/sdk)
                    (#:version-check #:screenshotbot/sdk/version-check)
                    (#:dto #:screenshotbot/api/model)))
(in-package :screenshotbot/sdk/finalized-commit)

(defun finalize-commit ()
  (when (< version-check:*remote-version* 7)
    (error "The remote Screenshotbot server does not support --mark-unchanged-from"))

  (let ((repo (git-repo)))
    (sdk:request "/api/unchanged-run"
                 :method :post
                 :content
                 (make-instance 'dto:finalized-commit
                                :commit (current-commit repo)))))