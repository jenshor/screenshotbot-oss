;; Copyright 2018-Present Modern Interpreters Inc.
;;
;; This Source Code Form is subject to the terms of the Mozilla Public
;; License, v. 2.0. If a copy of the MPL was not distributed with this
;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defsystem :build-utils
  :serial t
  :depends-on (:tmpdir
               :alexandria
               :parenscript ;; for js-package
               :str)
  :components ((:file "wild-module")
               (:file "common")
               (:file "remote-file")
               (:file "jar-file")
               (:file "js-package")
               (:file "css-package")
               (:file "all")))

(defsystem :build-utils/deliver-script
  :serial t
  :depends-on (:tmpdir
               :alexandria
               :trivial-features
               :str)
  :components ((:file "deliver-script")))
