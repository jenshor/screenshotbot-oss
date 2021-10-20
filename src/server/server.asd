;; Copyright 2018-Present Modern Interpreters Inc.
;;
;; This Source Code Form is subject to the terms of the Mozilla Public
;; License, v. 2.0. If a copy of the MPL was not distributed with this
;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defsystem "server"
  :depends-on ("cl-cli"
               "util"
               "cl-cron"
               #+ (or ccl lispworks)
               "jvm"
               "trivial-shell"
               #-sbcl
               "slynk"
               #-sbcl
               "slynk/arglists"
               #-sbcl
               "slynk/fancy-inspector"
               #-sbcl
               "slynk/package-fu"
               #-sbcl
               "slynk/mrepl"
               #-sbcl
               "slynk/trace-dialog"
               #-sbcl
               "slynk/profiler"
               #-sbcl
               "slynk/stickers"
               #-sbcl
               "slynk/indentation"
               #-sbcl
               "slynk/retro"
               "bordeaux-threads"
               "bknr.datastore"
               "hunchentoot-multi-acceptor")
  :serial t
  :components ((:file "setup")))

(defsystem :server/tests
    :depends-on (:server))
