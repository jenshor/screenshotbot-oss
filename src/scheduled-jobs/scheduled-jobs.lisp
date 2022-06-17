;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :scheduled-jobs
  (:use #:cl)
  (:import-from #:scheduled-jobs/model
                #:tz-offset
                #:cronexpr
                #:wrapper
                #:job
                #:%at
                #:%update-queue
                #:*lock*
                #:at
                #:periodic
                #:priority-queue
                #:scheduled-job-args
                #:scheduled-job-function
                #:scheduled-job)
  (:import-from #:priority-queue
                #:pqueue-empty-p
                #:pqueue-pop
                #:pqueue-front-key
                #:pqueue-front)
  (:import-from #:bknr.indices
                #:object-destroyed-p)
  (:import-from #:bknr.datastore
                #:delete-object)
  (:import-from #:bknr.datastore
                #:with-transaction)
  (:import-from #:util/cron
                #:def-cron)
  (:import-from #:scheduled-jobs/bindings
                #:cron-next
                #:cron-parse-expr)
  (:local-nicknames (#:a #:alexandria))
  (:export
   #:make-scheduled-job
   #:now
   #:at
   #:bad-argument-error
   #:call-job))
(in-package :scheduled-jobs)


(defclass threaded-executor ()
  ())

(defvar *executor* (make-instance 'threaded-executor))

(defun now ()
  (get-universal-time))

(define-condition bad-argument-error (error)
  ((argument :initarg :argument)))

(defun is-valid-arg (arg)
  "A sanity check on the argument, to make sure the argument is
serializable. This does not gurrantee serializability though, since
we're not looking in to what the object references."
  (or
   (null arg)
   (stringp arg)
   (symbolp arg)
   (arrayp arg)
   (listp arg)
   (typep arg 'bknr.datastore:store-object)))

(defmethod (setf cronexpr) ((val string) (self scheduled-job))
  (let ((parsed (cron-parse-expr val)))
    (with-transaction ()
      (setf (%at self) (cron-next parsed :now (now)
                                         :timezone (tz-offset self))))))

(defun make-scheduled-job (&key at
                             cronexpr
                             tzname
                             (function (error "must provide :function"))
                             (args (error "must provide :args"))
                             periodic)
  (unless (or at cronexpr)
    (error "must provide at least one of :at or :cronexpr"))
  (when (and at cronexpr)
    (error "Don't provide both :at and :cronexpr"))

  (when cronexpr
    (let ((parsed (cron-parse-expr cronexpr)))
      (setf at (cron-next parsed :now (now)
                          :timezone (tz-offset tzname)))))

  (loop for arg in args
        unless (is-valid-arg arg)
          do (error 'bad-argument-error :argument arg))
  (make-instance 'scheduled-job
                  :at at
                  :cronexpr cronexpr
                  :tzname tzname
                  :function function
                  :args args
                  :periodic periodic))


(defvar *call-pending-scheduled-jobs-lock* (bt:make-lock "call-pending-scheduled-job"))

(defun %call-pending-scheduled-jobs ()
  (let ((queue (priority-queue))
        (now (now)))
    (multiple-value-bind (next-wrapper next-at)
        (bt:with-lock-held (*lock*)
          (unless (pqueue-empty-p queue)
            (pqueue-pop queue)))
      (let ((next (when next-wrapper
                    (job next-wrapper))))
       (unwind-protect
            (cond
              ((null next)
               :no-more)
              ((or
                (object-destroyed-p next)
                ;; If (setf at) was called on the object, then
                ;; this could be a stale reference in the
                ;; priority queue.
                (not (eql next-wrapper (wrapper next))))
               (%call-pending-scheduled-jobs))
              ((> next-at now)
               ;; We're done. But we need to push this object back on to the
               ;; queue. If an error happens here, we'll lose this job
               ;; forever, so fingers crossed.
               (bt:with-lock-held (*lock*)
                 (%update-queue next)))
              (t
               (unwind-protect
                    (call-job *executor* (scheduled-job-function next)
                              (scheduled-job-args next))
                 (flet ((schedule-at (at)
                          (with-transaction ()
                            ;; the queue will be updated in the unwind-protect
                            (setf (%at next) at))
                          (bt:with-lock-held (*lock*)
                            (%update-queue next))))
                   (cond
                     ((cronexpr next)
                      ;; Figure out the next run time based on the cronexpr
                      (let ((cron-expr (ignore-errors
                                        (cron-parse-expr (cronexpr next)))))
                        (when cron-expr
                          (schedule-at (cron-next cron-expr :now (now)
                                                  :timezone (tz-offset next))))))
                     ((periodic next)
                      (schedule-at (+ (periodic next) now)))
                     (t
                      (delete-object next)))))
               (%call-pending-scheduled-jobs))))))))

(defun call-pending-scheduled-jobs ()
  (bt:with-lock-held (*call-pending-scheduled-jobs-lock*)
    (%call-pending-scheduled-jobs)))

(defmethod call-job ((executor t) fn args)
  (apply fn args))

(defmethod call-job ((executor threaded-executor) fn args)
  (util/threading:make-thread
   (lambda ()
     ;; I don't know if call-next-method will work reliably across
     ;; implementations. But it's not really needed for this.
     (call-job nil fn args))
   :name "schedule-job"))

(def-cron call-pending-scheduled-job ()
  (call-pending-scheduled-jobs))