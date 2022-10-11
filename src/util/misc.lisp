;; Copyright 2018-Present Modern Interpreters Inc.
;;
;; This Source Code Form is subject to the terms of the Mozilla Public
;; License, v. 2.0. If a copy of the MPL was not distributed with this
;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :util/misc
  (:use #:cl)
  (:export
   #:funcall-if
   #:?.
   #:or-setf
   #:not-null!
   #:uniq
   #:safe-ensure-directories-exist))
(in-package :util/misc)


(defun funcall-if (fn arg &rest rest)
  "If arg is not nil, then call the function fn with the args (cons arg rest)"
  (when arg
    (apply fn arg rest)))

(defmacro ?. (fn arg &rest rest)
  (alexandria:with-gensyms (arg-val)
    `(let ((,arg-val ,arg))
       (funcall-if (function ,fn)
                   ,arg-val
                   ,@rest))))

(local-time:reread-timezone-repository)

(defvar *lock* (bt:make-lock "or-setf"))

(defmacro or-setf (place expr &key (thread-safe nil)
                                (lock '*lock*))
  (cond
    (thread-safe
     `(or
       ,place
       (bt:with-lock-held (,lock)
         ,place
         (setf ,place ,expr))))
    (t
     `(or
       ,place
       (setf ,place ,expr)))))


(defun %not-null (x expr)
  (cond
    (x x)
    (t (error "Expected ~s to eval to a not null value" expr))))

(defmacro not-null! (x)
  `(%not-null ,x ',x))

(defun %not-null-or-empty (x expr)
  (cond
    ((not (str:emptyp  x)) x)
    (t (error "Expected ~s to eval to a non-empty value" expr))))

(defmacro not-empty! (x)
  `(%not-null-or-empty ,x ',x))

(defun uniq (list &key (test #'eql))
  "Given a sorted list, remove adjacent duplicates"
  (let ((ret nil))
    (loop for x in list
          if (or (null ret)
                 (not (funcall test x (car ret))))
            do (push x ret))
    (nreverse ret)))

(defun safe-ensure-directories-exist (x)
  "cl:ensure-directories-exist is not thread safe. This version is
 thread-safe for all practical purposes, without too much overhead.

In the error case, it's hard to distinguish between a real error (e.g.
 the directory is not writeable"
  (handler-case
      (ensure-directories-exist x)
    (file-error (e)
      (dotimes (i 10)
        ;; The lock isn't doing much here though, the idea is just to
        ;; reduce the possibility of collisions.
        (bt:with-lock-held (*lock*)
          (handler-case
              (return-from safe-ensure-directories-exist
                (ensure-directories-exist x))
            (file-error (next)
              ;; If an error happens, the file-error-pathname is
              ;; filled out. If the second round is tsi
              (when (equal (file-error-pathname e)
                           (file-error-pathname next))
                (error next))
              (setf e next)))))
      (error "Could not not create the directory even after multiple attempts"))))


(defmethod parse-size ((size number))
  size)

(defmethod parse-size ((size string))
  (multiple-value-bind (num suffix-pos)
      (parse-integer size :junk-allowed t)
    (let ((suffix (str:substring suffix-pos nil size)))
     (cond
       ((string-equal "GB" suffix)
        (* num 1024 1024 1024))
       ((string-equal "MB" suffix)
        (* num 1024 1024))
       ((string-equal "kB" suffix)
        (* num 1024))
       ((or
         (string-equal "" suffix)
         (string-equal "b" suffix)
         (string-equal "bytes" suffix))
        num)
       (t
        (error "could not parse size suffix: ~a in ~a" suffix size))))))
