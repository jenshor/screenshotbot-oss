;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(pkg:define-package :screenshotbot/gitlab/merge-request-promoter
    (:use #:cl
          #:alexandria
          #:screenshotbot/promote-api
          #:screenshotbot/java
          #:screenshotbot/model/channel
          #:screenshotbot/compare
          #:screenshotbot/model/report
          #:screenshotbot/model/recorder-run
          #:./repo
          #:bknr.datastore)
  (:nicknames :screenshotbot/gitlab/merge-request-promoter) ;; for datastore
  (:import-from #:screenshotbot/model/report
                #:base-acceptable)
  (:import-from #:screenshotbot/server
                #:*domain*)
  (:export #:merge-request-promoter
           #:gitlab-acceptable))


(named-readtables:in-readtable java-syntax)

(defclass merge-request-promoter (promoter)
  ((comments :initform nil
             :accessor comments)
   (report :initform nil
           :accessor promoter-report)))

(defun safe-get-mr-id (run)
  (let ((mr-id (gitlab-merge-request-iid run)))
    (unless (str:emptyp mr-id)
     (parse-integer mr-id))))

(defun get-merge-request (run)
  (let ((mr-id (gitlab-merge-request-iid run)))
    (when mr-id
      (let* ((repo (channel-repo (recorder-run-channel run)))
             (api (#_getMergeRequestApi
                   (gitlab-api
                    repo))))
        (let ((project-path (project-path repo))
              (mr-id (safe-get-mr-id run)))
          (when mr-id
           (#_getMergeRequest
            api
            project-path mr-id)))))))

(defmethod maybe-promote ((promoter merge-request-promoter) run)
  (restart-case
      (cond
        ((typep (channel-repo (recorder-run-channel run))
                'gitlab-repo)
         (let* ((mr (get-merge-request run)))
           (when mr
             (maybe-promote-mr promoter run mr))))
        (t
         (log:info "Not promoting, gitlab")))
    (restart-maybe-promote ()
      (maybe-promote promoter run))))

(defun comment (promoter message)
  (push message (comments promoter)))

(defclass gitlab-acceptable (base-acceptable)
  ((report :initarg :report
           :accessor acceptable-report)
   (discussion-id :accessor discussion-id))
  (:metaclass bknr.datastore:persistent-class))

(defmethod (setf acceptable-state) :before (state (acceptable gitlab-acceptable))
  (flet ((not-null! (x) (assert x) x))
   (let* ((run (report-run (acceptable-report acceptable)))
          (repo (channel-repo (recorder-run-channel run)))
          (api (gitlab-api repo)))
     (%resolve-merge-request-discussion
      (#_getDiscussionsApi api)
      (not-null! (project-path repo))
      (not-null! (safe-get-mr-id run))
      (not-null! (discussion-id acceptable))
      (ecase state
        (:accepted
         t)
        (:rejected
         nil))))))

(defun maybe-promote-mr (promoter run mr)
  (let* ((channel (recorder-run-channel run))
         (base-sha (#_getBaseSha (#_getDiffRefs mr)))
         (base-run (production-run-for channel
                                       :commit base-sha)))
    (cond
      ((not base-run)
       (comment promoter "Parent commit not available on master to generate Screenshot report, try rebasing or rerunning"))
      (t
       (let ((diff-report (make-diff-report run base-run)))
         (cond
           ((diff-report-empty-p diff-report)
            (comment promoter "No screenshot changes"))
           (t
            (let ((report (make-instance 'report
                                         :run run
                                         :previous-run base-run
                                         :channel (when run (recorder-run-channel run))
                                         :title (diff-report-title diff-report))))
              (with-transaction ()
                (setf (report-acceptable report)
                      (make-instance 'gitlab-acceptable
                                     :report report)))
              (setf (promoter-report promoter)
                    report)
              (comment promoter
                (format
                 nil
                 "Screenshot changes: ~a ~a/report/~a"
                 (diff-report-title diff-report)
                 *domain*
                 (util:oid report)))))))))))

(screenshotbot/java:define-java-callers "org.gitlab4j.api.DiscussionsApi"
  (%create-merge-request-discussion "createMergeRequestDiscussion")
  (%resolve-merge-request-discussion "resolveMergeRequestDiscussion"))

(defun comment-now (promoter run comment)
  (let* ((channel (recorder-run-channel run))
         (repo (channel-repo channel))
         (api (gitlab-api repo))
         (mr-id (safe-get-mr-id run)))
    (let ((disc (%create-merge-request-discussion
                 (#_getDiscussionsApi api)
                 (project-id repo)
                 mr-id
                 comment ;; body
                 nil     ;; Date
                 nil     ;; positionHash
                 nil     ;; Position
                 )))
      disc)))

(defmethod maybe-send-tasks ((promoter merge-request-promoter) run)
  (restart-case
      (let ((report (promoter-report promoter )))
        (loop for comment in (comments promoter)
              do
                 (let ((disc (comment-now promoter run comment)))
                   (with-transaction ()
                     (setf (discussion-id (report-acceptable report))
                           (#_getId disc))))))
    (retry-maybe-send-tasks ()
      (maybe-send-tasks promoter run))))


(register-promoter 'merge-request-promoter)
