;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :util/tests/test-lparallel
  (:use #:cl
        #:fiveam)
  (:import-from #:util/lparallel
                #:bind-future)
  (:import-from #:util/testing
                #:with-global-kernel)
  (:import-from #:lparallel.promise
                #:future)
  (:import-from #:lparallel.promise
                #:force))
(in-package :util/tests/test-lparallel)

(util/fiveam:def-suite)

(test simple-bind-fn
  (with-global-kernel ()
    (let ((f1 (future 2)))
      (is (equal 3 (force (bind-future f1 (lambda (x) (+ 1 x)))))))))
