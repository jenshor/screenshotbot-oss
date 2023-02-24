;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/azure/request
  (:use #:cl)
  (:import-from #:util/json-mop
                #:ext-json-serializable-class)
  (:import-from #:util/request
                #:http-request))
(in-package :screenshotbot/azure/request)

#|
Documentation
https://learn.microsoft.com/en-us/rest/api/azure/devops/build/status/get?view=azure-devops-rest-7.0
|#


(defclass devops-build ()
  ((uri :initarg :uri
        :json-key "uri"
        :json-type :string)
   (build-result :initarg :build-result
                 :json-key "result"
                 :json-type :string))
  (:metaclass ext-json-serializable-class))

(defclass build-definition-reference ()
  ((name :json-key "name"
         :json-type :string
         :initarg :name
         :reader name)
   (id :json-key "id"
       :json-type :number
       :reader id)
   (description :json-key "description"
                :json-type (or null :string)
                :initarg :description)
   (repository :json-key "repository"
               :json-type (or null build-repository)
               :initarg :repository))
  (:metaclass ext-json-serializable-class))

(defclass git-status-context ()
  ((genre :initform "screenshotbot"
          :json-key "genre"
          :json-type :string)
   (name :initarg :name
         :json-key "name"
         :json-type :string))
  (:metaclass ext-json-serializable-class))

(defclass pull-request-status ()
  ((description :json-key "description"
                :json-type :string
                :initarg :description)
   (state :json-key "state"
          :json-type :string
          :initarg :state)
   (context :initarg :context
            :json-key "context"
            :json-type git-status-context)
   (target-url :initarg :target-url
               :json-key "targetUrl"
               :json-type :string))
  (:metaclass ext-json-serializable-class))

(defclass build-repository ()
  ((name :json-type :string
         :json-key "name"
         :initarg :name))
  (:metaclass ext-json-serializable-class))


(defvar *token* nil)

(defclass azure ()
  ((token :initarg :token
          :reader token)
   (organization :initarg :organization
                 :reader organization)
   (project :initarg :project
            :reader project)))

(defvar *test-azure* (make-instance 'azure :token *token*
                                           :organization "testsbot"
                                           :project "fast-example"))

(define-condition azure-error (simple-error)
  ((headers :initarg :headers)))

(defun azure-request (azure url &key
                                  method
                                  response-type
                                  parameters
                                  content)
  (declare (optimize (speed 0) (debug 3)))
  (let ((content (with-output-to-string (out)
                   (yason:encode content out))))
    (log:info "Sending body: ~a" content)
    (multiple-value-bind (response code headers)
       (http-request
        (format nil "https://dev.azure.com/~a/~a/_apis/~a?api-version=7.0"
                (organization azure)
                (project azure)
                url)
        :content content
        :content-type "application/json"
        :basic-authorization (list "" (token azure))
        :accept "application/json"
        :parameters parameters
        :method method
        :want-string t)
     (cond
       ((<= 400 code 510)
        (error 'azure-error
               :headers headers
               :format-control "Got failure: ~a"
               :format-arguments (list response)))
       (t
        (json-mop:json-to-clos response response-type))))))

(defun queue-build (azure &key
                      uri
                      result)
  (let ((body (make-instance 'devops-build
                             :uri "https://screenshotbot.io/runs"
                             :build-result "succeeded")))
    (azure-request
     azure
     "build/builds"
     :method :post
     :content body
     :parameters `(("sourceBuildId" . "5")))))

(defclass list-definitions-response ()
  ((value :json-type (:list build-definition-reference)
          :json-key "value"
          :reader build-definitions))
  (:metaclass ext-json-serializable-class))

(defun list-definitions (azure)
  (azure-request
   azure
   "build/definitions"
   :method :get
   :response-type 'list-definitions-response))

(defun create-definition (azure build-definition)
  (azure-request
   azure
   "build/definitions"
   :method :post
   :response-type 'build-definition-reference
   :content build-definition))

(defmethod create-pull-request-status (azure status
                                       &key repository-id
                                         pull-request-id)
  (declare (optimize (speed 0) (debug 3)))
  (azure-request
   azure
   (format nil
           "git/repositories/~a/pullRequests/~a/statuses"
           repository-id
           pull-request-id)
   :method :post
   :response-type 'pull-request-status
   :content status))

#|
https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies?view=azure-devops&tabs=browser#build-validation
|#

#+nil
(queue-build *test-azure*)

#+nil
(create-pull-request-status
 *test-azure*
 (make-instance 'pull-request-status
                :description "some stuff"
                :state "failed"
                :target-url "https://screenshotbot.io/runs"
                :context (make-instance 'git-status-context
                                        :name "foobar"))
 :repository-id "fast-example"
 :pull-request-id 1)

#+nil
(create-definition *test-azure*
                   (make-instance 'build-definition-reference
                                  :name "test-foo"
                                  :description "this is a sample job"
                                  :))
#+nil
(format t "~a"(list-definitions *test-azure*))
