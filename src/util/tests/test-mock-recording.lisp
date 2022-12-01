;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(uiop:define-package :util/tests/test-mock-recording
    (:use #:cl
          #:fiveam
          #:alexandria)
  (:import-from #:util/mock-recording
                #:response
                #:arguments
                #:with-recording))
(in-package :util/tests/test-mock-recording)

(util/fiveam:def-suite)

(defvar *ans* nil)

(defun foo (x)
  (or
   *ans*
   (+  1 x)))

(test recording-mode
  (uiop:with-temporary-file (:pathname p)
    (is (eql 3 (with-recording (foo p :record t)
                 (foo 2))))
    (is (eql 10 (with-recording (foo p :record t)
                  (foo 3)
                  (foo 9))))
    (let ((recording (cl-store:restore p)))
      (is (equal
           `(((3) . 4)
             ((9) . 10))
           (loop for function-call in recording
                 collect (cons
                          (arguments function-call)
                          (response function-call))))))))

(test replay-mode
  (uiop:with-temporary-file (:pathname p)
    (with-recording (foo p :record t)
      (let ((*ans* 9))
        (foo 3)))
    (with-recording (foo p)
      (is (eql 9 (foo 3))))))

(test skip-args
  (uiop:with-temporary-file (:pathname p)
    (with-recording (foo p :record t
                     :skip-args (list 0))
      (foo 3))
    (with-recording (foo p :skip-args (list 0))
      (is (eql 4 (foo 30))))))
