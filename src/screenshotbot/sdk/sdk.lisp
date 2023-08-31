;; Copyright 2018-Present Modern Interpreters Inc.
;;
;; This Source Code Form is subject to the terms of the Mozilla Public
;; License, v. 2.0. If a copy of the MPL was not distributed with this
;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/sdk/sdk
  (:nicknames :screenshotbot-sdk)
  (:use #:cl
        #:alexandria
        #:anaphora
        #:screenshotbot/sdk/flags
        #:screenshotbot/sdk/hostname)
  (:import-from #:dag
                #:add-commit
                #:commit
                #:merge-dag
                #:get-commit
                #:write-to-stream
                #:read-from-stream)
  (:import-from #:screenshotbot/sdk/bundle
                #:image-stream
                #:md5-sum
                #:list-images
                #:close-image
                #:image-name
                #:image-directory
                #:image-directory-with-diff-dir)
  (:import-from #:screenshotbot/sdk/git
                #:current-commit
                #:rev-parse
                #:read-graph
                #:cleanp
                #:merge-base)
  (:import-from #:util/request
                #:http-request)
  (:import-from #:util/misc
                #:?.
                #:or-setf)
  (:import-from #:screenshotbot/sdk/version-check
                #:remote-supports-put-run
                #:remote-supports-basic-auth-p)
  (:import-from #:util/health-check
                #:def-health-check)
  (:import-from #:screenshotbot/api/model
                #:encode-json)
  (:import-from #:util/json-mop
                #:ext-json-serializable-class
                #:json-mop-to-string)
  (:import-from #:screenshotbot/sdk/backoff
                #:backoff)
  (:import-from #:screenshotbot/sdk/api-context
                #:desktop-api-context
                #:api-context)
  (:import-from #:screenshotbot/sdk/run-context
                #:flags-run-context)
  (:local-nicknames (#:flags #:screenshotbot/sdk/flags)
                    (#:dto #:screenshotbot/api/model)
                    (#:e #:screenshotbot/sdk/env)
                    (#:api-context #:screenshotbot/sdk/api-context)
                    (#:android   #:screenshotbot/sdk/android)
                    (#:run-context   #:screenshotbot/sdk/run-context))
  (:export
   #:single-directory-run
   #:*request*
   #:*put*
   #:request
   #:put-file
   #:parse-org-defaults
   #:run-prepare-directory-toplevel
   #:absolute-pathname
   #:update-commit-graph
   #:validate-pull-request))

(in-package :screenshotbot/sdk/sdk)

(defmacro defopt (var &key params
                        default
                        boolean
                        required
                        (help "undocumented"))
  (declare (ignore required))
  (let ((params (or params
                    (unless boolean
                      `(list ,(str:replace-all "*" "" (string var)))))))
    `(list ',var ,default ,help :params ,params)))


(defclass model ()
  (type))

(defclass image (model)
  ((id :type string)
   (upload-url :type string)))

(define-condition api-error (error)
  ((message :initarg :message)))

(defmethod print-object ((e api-error) stream)
  (with-slots (message) e
   (format stream "#<API-ERROR ~a>" message)))

(defun ensure-api-success (result)
  (let ((indent "    "))
   (awhen (assoc-value result :error)
     (log:error "API error: ~a" it)
     (when-let ((stacktrace (assoc-value result :stacktrace)))
      (log:error "Server stack trace: ~%~a~a"
                 indent
                 (str:join (format nil "~%~a" indent)
                           (str:lines stacktrace))))
     (error 'api-error :message it)))
  (assoc-value result :response))


(defmethod %make-basic-auth (api-context)
  (list
   (api-context:key api-context)
   (api-context:secret api-context)))

(defmethod %make-basic-auth ((self desktop-api-context))
  nil)

(auto-restart:with-auto-restart (:retries 3 :sleep #'backoff)
  (defun %request (api-context
                   api &key (method :post)
                         parameters
                         content)
    ;; TODO: we're losing the response code here, we need to do
    ;; something with it.
    (uiop:slurp-input-stream
     'string
     (http-request
      (format-api-url api-context api)
      :method method
      :want-stream t
      :method method
      :basic-authorization (when (remote-supports-basic-auth-p api-context)
                             (%make-basic-auth api-context))
      :content content
      :external-format-out :utf-8
      :parameters (cond
                    ((remote-supports-basic-auth-p api-context)
                     parameters)
                    (t (list*
                        (cons "api-key" (api-context:key api-context))
                        (cons "api-secret-key" (api-context:secret api-context))
                        parameters)))))))

(defmethod request ((api-context api-context:api-context)
                    api &key (method :post)
                          parameters
                          content)
  (log:debug "Making API request: ~S" api)
  (when (and (eql method :get) parameters)
    (error "Can't use :get with parameters"))
  (let ((json (%request api-context
                        api :method method
                            :parameters parameters
                            :content (cond
                                       ((or
                                         (eql :put method)
                                         (typep (class-of content)
                                                'ext-json-serializable-class))
                                        (json-mop-to-string
                                         content))
                                       ((and (eql method :post)
                                             content)
                                        content)))))
    (handler-case
        (let ((result (json:decode-json-from-string json)))
          (ensure-api-success result))
      (json:json-syntax-error (e)
        (error "Could not parse json:"
               json)))))

(defun call-with-file-stream (non-file-stream fn)
  "See doc for with-file-stream"
  (handler-case
      (file-length non-file-stream)
    (type-error ()
      (error "Unimplemented non-file-stream: this is a bug, please ping support@screenshotbot.io")))
  (funcall fn non-file-stream))

(defmacro with-file-stream ((stream non-file-stream) &body body)
  "This actually does nothing: it just calls the body with stream bound to non-file-stream.

However: the intention is that we bind stream to a stream where we can
call file-length. Currently, it appears that the only streams we would
actually call put-file/upload-image with are file streams, so we just
don't implement this behavior for other streams. However, this
analysis was made later, so we're keeping this code here and if we get
a stram on which file-length doesn't work we raise a more parseable
error."
  `(call-with-file-stream
    ,non-file-stream
    (lambda (,stream) ,@body)))

(auto-restart:with-auto-restart (:retries 3 :sleep #'backoff)
  (defun put-file (api-context upload-url stream &key parameters)
    ;; In case we're retrying put-file, let's make sure we reset the
    ;; stream
    (log:debug "put file to: ~a" upload-url)
    (file-position stream 0)
    (with-file-stream (stream stream)
     (let ((file-length (file-length stream)))
       (log:debug "Got file length: ~a" file-length)
       (multiple-value-bind (result code)
         (http-request
          upload-url
          :method :put
          :parameters parameters
          ;; Basic auth for image puts will be supported from API
          ;; level 4, but in previous versions it should just be ignored.
          :basic-authorization (%make-basic-auth api-context)
          :content-type "application/octet-stream"
          :content-length file-length
          :content stream
          :read-timeout 40)

         (log:debug "Got image upload response: ~s" result)
         (unless (eql 200 code)
           (error "Failed to upload image: code ~a" code))
         result)))))

(defun upload-image (api-context key stream hash response)
  (Assert hash)
  (log:debug "Checking to see if we need to re-upload ~a, ~a" key hash)
  (log:debug "/api/screenshot response: ~s" response)
  (let ((upload-url (assoc-value response :upload-url)))
    (when upload-url
      (log:info "Uploading image for `~a`" key)
      (put-file api-context upload-url stream)))
  (setf (assoc-value response :name) key)
  response)

(defun build-screenshot-objects (images metadata-provider)
  (loop for im in images
        collect
        (let ((name (assoc-value im :name)))
          (make-instance 'dto:screenshot
                         :name name
                         :image-id (assoc-value im :id)))))

(defun safe-parse-int (str)
  (cond
    ((not str)
     nil)
    ((stringp str)
     (unless (str:emptyp str)
       (parse-integer str :junk-allowed t)))
    ((numberp str)
     str)
    (t
     (error "Not a type that can be convered to integer: ~s" str))))

(define-condition empty-run-error (error)
  ()
  (:report "No screenshots were detected in this this run"))

(auto-restart:with-auto-restart ()
 (defmethod make-run (api-context
                      images
                      (run-context run-context:run-context)
                      &key
                        (metadata-provider (make-instance 'metadata-provider))
                        periodic-job-p)
   (unless images
     (error 'empty-run-error))
   (let ((screenshots (build-screenshot-objects images metadata-provider)))
     ;;(log:info "screenshot records: ~s" screenshots)
     (let* ((branch-hash (run-context:main-branch-hash run-context))
            (commit (run-context:commit-hash run-context))
            (merge-base (run-context:merge-base run-context))
            (github-repo (run-context:repo-url run-context))
            (run (make-instance 'dto:run
                                :channel (run-context:channel run-context)
                                :screenshots screenshots
                                :main-branch (run-context:main-branch run-context)
                                :work-branch (run-context:work-branch run-context)
                                :main-branch-hash branch-hash
                                :github-repo github-repo
                                :merge-base merge-base
                                :periodic-job-p periodic-job-p
                                :build-url (run-context:build-url run-context)
                                :compare-threshold  (run-context:compare-threshold run-context)
                                :batch (run-context:batch run-context)
                                :pull-request (run-context:pull-request-url run-context)
                                :commit-hash commit
                                :override-commit-hash (run-context:override-commit-hash run-context)
                                :create-github-issue-p (run-context:create-github-issue-p run-context)
                                :cleanp (run-context:repo-clean-p run-context)
                                :gitlab-merge-request-iid (safe-parse-int (run-context:gitlab-merge-request-iid run-context))
                                :phabricator-diff-id (safe-parse-int (run-context:phabricator-diff-id run-context))
                                :trunkp (run-context:productionp run-context))))
       (if (remote-supports-put-run api-context)
           (put-run api-context run)
           (put-run-via-old-api api-context run))))))

(defmethod put-run ((api-context api-context) run)
  (let ((result (request api-context
                         "/api/run" :method :put
                                    :content run)))
    (log:info "Created run: ~a" (assoc-value result :url))))

(defun put-run-via-old-api (api-context run)
  (flet ((bool (x) (if x "true" "false")))
    (request
     api-context
     "/api/run"
     :parameters `(("channel" . ,(dto:run-channel run))
                   ("screenshot-records" . ,(json:encode-json-to-string
                                             (dto:run-screenshots run)))
                   ("branch" . ,(dto:main-branch run))
                   ("branch-hash" . ,(dto:main-branch-hash run))
                   ("github-repo" . ,(dto:run-repo run))
                   ("merge-base" . ,(dto:merge-base run))
                   ("periodic-job-p" . ,(bool (dto:periodic-job-p run)))
                   ("build-url" . ,(dto:build-url run))
                   ("pull-request" . ,(dto:pull-request-url run))
                   ("commit" . ,(dto:run-commit run))
                   ("override-commit-hash" . ,(dto:override-commit-hash run))
                   ("create-github-issue" . ,(bool (dto:should-create-github-issue-p run)))
                   ("is-clean" . ,(bool (dto:cleanp run)))
                   ("gitlab-merge-request-iid" .
                                               ,(dto:gitlab-merge-request-iid run))
                   ("phabricator-diff-id" . ,(dto:phabricator-diff-id run))
                   ("is-trunk" . ,(bool (dto:trunkp run)))))))


(defun $! (&rest args)
  (multiple-value-bind (out error res)
      (uiop:run-program args
                        :error-output :interactive
                        :output :interactive
                        :ignore-error-status t)
    (declare (ignore out error))
    (eql 0 res)))

(defclass basic-directory-run ()
  ((directory :initarg :directory)))

(defclass metadata-provider ()
  ())

(defmethod make-directory-run (api-context dir run-context &rest args)
  (log:debug "Reading images from ~a" dir)
  (let ((images
          (upload-image-directory api-context dir)))
    (log:debug "Creating run")
    (apply #'make-run
           api-context
           images
           run-context
           args)))

(defun keyword-except-md5 (identifier)
  ;; this is bug prone, but I know for a fact we don't have
  ;; 32 character long identifiers in the json :/
  (cond
   ((eql 32 (length identifier))
    (string identifier))
   (t
    (json:camel-case-to-lisp identifier))))

(defmethod upload-image-directory (api-context bundle)
  (let ((images (list-images bundle)))
    (let ((hash-to-response
           (let ((json:*json-identifier-name-to-lisp* 'keyword-except-md5))
             (request
              api-context
              "/api/screenshot"
              :parameters `(("hash-list"
                             . ,(json:encode-json-to-string (mapcar 'md5-sum images))))))))
      (log:debug "got full response: ~s" hash-to-response)
      (loop for im in images
            collect
            (progn
              (with-open-stream (s (image-stream im))
                (unwind-protect
                     (upload-image api-context
                                   (image-name im) s
                                   (md5-sum im)
                                   (assoc-value hash-to-response (md5-sum im)
                                                :test 'string=))
                  (close-image im))))))))


(defun make-bundle (&key (metadata flags:*metadata*)
                      (directory flags:*directory*)
                      (recursivep flags:*recursive*))
  (cond
    (metadata
     (log:info "Looks like an Android run")
     (android:make-image-bundle :metadata metadata))
    ((not (str:emptyp directory))
     (unless (path:-d directory)
       (error "Not a directory: ~a" directory))
     (make-instance 'image-directory :directory directory
                                     :recursivep recursivep))
    (t
     (error "Unknown run type, maybe you missed --directory?"))))



(defun link-to-github-pull-request (repo-url pull-id)
  (let ((key (cond
               ((str:containsp "bitbucket" repo-url)
                "pull-requests")
               (t
                "pulls"))))
   (format nil "~a/~a/~a"
           repo-url
           key
           pull-id)))


(defun recursive-directories (directory)
  (or
   (loop for d in (fad:list-directory directory)
         if (and (not (str:starts-with-p "." (car (last (pathname-directory d)))))
                 (path:-d d))
           appending (recursive-directories d))
   (list directory)))

(defun get-relative-path (dir parent)
  (let ((dir-parts (pathname-directory dir))
        (parent-parts (pathname-directory parent)))
    (log:debug "got parts: ~s ~s" parent-parts dir-parts)
    (assert (equal parent-parts
                   (subseq dir-parts 0 (length parent-parts))))
    (let ((res (make-pathname
                :directory
                `(:relative ,@(subseq dir-parts (length parent-parts)))
                :defaults #P"./")))
      (log:debug "Relative path parts: ~S" (pathname-directory res))
      (log:debug "Relative path is: ~S" res)
      res)))

(defmethod update-commit-graph (api-context repo
                                &key
                                  (repo-url (error "must provide :repo-url")))
  (log:info "Updating commit graph")
  (let* ((dag (read-graph repo))
         (json (with-output-to-string (s)
                 (dag:write-to-stream dag s))))
    (request
     api-context
     "/api/commit-graph"
     :method :post
     :parameters (list
                  (cons "repo-url" repo-url)
                  (cons "graph-json" json)))))

(defun single-directory-run (api-context directory run-context)
  (let ((branch (run-context:main-branch run-context)))
    (when (and
           (run-context:productionp run-context)
           (> flags:*commit-limit* 0))
      (update-commit-graph api-context (run-context:git-repo run-context)
                           :repo-url (run-context:repo-url run-context)))
    (log:info "Uploading images from: ~a" directory)
    (make-directory-run api-context directory
                        run-context)))

(defun chdir-for-bin (path)
  (uiop:chdir path)
  (setf *default-pathname-defaults* (pathname path)))


(defun absolute-pathname (p)
  (fad:canonical-pathname (path:catdir (uiop:getcwd) p)))

(defun run-prepare-directory-toplevel (api-context)
  (let ((directory (make-bundle)))
    (single-directory-run api-context directory
                          (make-instance
                           'flags-run-context
                           :env (e:make-env-reader)))))

(def-health-check verify-https-works ()
  (util/request:http-request "https://screenshotbot.io/api/version"
                             :ensure-success t))
