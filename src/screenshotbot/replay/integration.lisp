;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/replay/integration
  (:use #:cl)
  (:nicknames :screenshotbot/pro/replay/integration)
  (:import-from #:screenshotbot/replay/frontend
                #:width
                #:dimensions
                #:browser-type
                #:*default-browser-configs*
                #:screenshot-file-key
                #:screenshot-title
                #:screenshots
                #:job)
  (:import-from #:screenshotbot/sdk/sdk
                #:make-directory-run)
  (:import-from #:screenshotbot/sdk/git
                #:null-repo)
  (:import-from #:screenshotbot/sdk/flags
                #:*hostname*
                #:*api-secret*
                #:*api-key*)
  (:import-from #:screenshotbot/sdk/bundle
                #:local-image
                #:list-images)
  (:import-from #:screenshotbot/sdk/git
                #:make-instance)
  (:import-from #:util
                #:or-setf)
  (:import-from #:screenshotbot/replay/sitemap
                #:parse-sitemap)
  (:import-from #:screenshotbot/replay/core
                #:context
                #:write-replay-log
                #:uuid
                #:root-asset
                #:asset-file
                #:load-url-into
                #:snapshot)
  (:import-from #:screenshotbot/replay/replay-acceptor
                #:call-with-hosted-snapshot)
  (:import-from #:screenshotbot/webdriver/impl
                #:call-with-webdriver)
  (:import-from #:screenshotbot/webdriver/screenshot
                #:full-page-screenshot)
  (:import-from #:screenshotbot/magick
                #:run-magick)
  (:import-from #:webdriver-client
                #:window-resize)
  (:import-from #:auto-restart
                #:with-auto-restart)
  (:import-from #:screenshotbot/model/api-key
                #:api-key-secret
                #:make-transient-key)
  (:import-from #:screenshotbot/api-key-api
                #:api-key-secret-key
                #:api-key-key)
  (:import-from #:screenshotbot/replay/services
                #:squid-proxy
                #:selenium-port
                #:selenium-host
                #:selenium-server
                #:selenium-server-url)
  (:import-from #:screenshotbot/replay/run-builder
                #:record-screenshot
                #:all-screenshots)
  (:import-from #:util/threading
                #:safe-interrupt-checkpoint)
  (:local-nicknames (#:a #:alexandria)
                    (#:frontend #:screenshotbot/replay/frontend)
                    (#:integration #:screenshotbot/replay/integration)
                    (#:replay #:screenshotbot/replay/core)
                    (#:flags #:screenshotbot/sdk/flags))
  (:export
   #:sitemap
   #:run
   #:original-request))
(in-package :screenshotbot/replay/integration)

(with-auto-restart ()
 (defun get-local-addr (host port)
   (let ((socket (usocket:socket-connect host port)))
     (unwind-protect
          (str:join "." (loop for i across (usocket:get-local-name socket)
                              collect (format nil "~d" i)))
       (usocket:socket-close socket)))))

(defun get-local-name (service)
  "Not currently in use. Mostly because we're hardcoding names in the
squid config, so if we do this we'd have to dynamically update squid
too."
  (typecase service
    (local-client
     "localhost")
    #+lispworks
    (t
     (get-local-addr (host service) (port service)))))

(defclass run ()
  ((company :initarg :company
            :reader company)
   (user :initarg :user
         :reader user)
   (sitemap :initarg :sitemap
            :initform nil
            :reader sitemap
            :documentation "URL to a sitemap. If Provided the list of URLs are picked from the sitemap")
   (sampling :initarg :sampling
             :initform 1
             :reader sampling
             :documentation "Sampling rate from the list of URLs. Works when providing sitemap too.")
   (channel :initarg :channel
            :reader channel)
   (max-width :initarg :max-width
              :reader max-width
              :initform 640)
   (host :initarg :host
         :initform "https://api.screenshotbot.io"
         :reader host)
   (browser-configs :initarg :browser-configs
                    :initform *default-browser-configs*
                    :reader browser-configs)

   (request :initarg :request
            :initform nil
            :reader original-request)
   (urls :initarg :urls
         :initform nil
         :accessor %urls)
   (custom-css :initarg :custom-css
               :initform nil
               :accessor custom-css)
   (sleep :initarg :sleep
          :initform 1
          :reader sleep-time)))

(define-condition config-error (simple-error)
  ())

(defmethod initialize-instance :after ((self run) &key urls sitemap &allow-other-keys)
  (when (and urls sitemap)
    (error "Can't provide both urls and sitemap")))

(defmethod remove-base-url ((url string))
  (let ((uri (quri:uri url)))
    (setf (quri:uri-scheme uri) nil)
    (setf (quri:uri-host uri) nil)
    (quri:render-uri uri)))


(defmethod urls ((run run))
  (or-setf
   (%urls run)
   (and (sitemap run)
        (loop for url in (parse-sitemap (sitemap run))
              collect
              (cons
               (remove-base-url url)
               url)))))

(defmethod sampled-urls ((run run))
  "Determistically sample the list of URLS from run. Any
screenshotting operation should use this method instead of directly
accessing the urls or sitemap slot."
  (let ((urls (urls run))
        (sampling (* 256 (sampling run))))
    (loop for (name . url) in urls
          for hash = (elt (md5:md5sum-string url) 0)
          if (<= hash sampling)
            collect (cons name url))))

(defun process-results (run results)
  ;; The SDK has an ugly API when used from a non-SDK world

  (restart-case
      (let* ((api-key (make-transient-key :user (user run)
                                          :company (company run)))
             (request (integration:original-request run))
             (flags:*api-key* (api-key-key api-key))
             (flags:*api-secret* (api-key-secret-key api-key))
             (flags:*hostname* (host run))
             (flags:*pull-request* (when request (replay:pull-request request)))
             (flags:*main-branch* (when request (replay:main-branch request)))
             (flags:*repo-url* (when request (replay:repo-url request))))
        (make-directory-run
         results
         :repo (make-instance 'null-repo)
         :branch "master"
         :commit (when request (replay:commit request))
         :merge-base (when request (replay:merge-base request))
         :branch-hash (when request (replay:branch-hash request))
         :github-repo (when request (replay:repo-url request))
         :periodic-job-p (or (not request) (str:emptyp (replay:commit request)) t)
         :is-trunk t
         :channel (channel run)))
    (retry-process-results ()
      (process-results run results))))

(defun run-replay-on-urls (&key (snapshot (error "provide snapshot"))
                             (urls (error "provide urls"))
                             (logger (lambda (url actual-url) (declare (ignore url actual-url))))
                             (hosted-url (error "provide hosted-url"))
                             (driver (error "provide driver"))
                             (config (error "provide config"))
                             (run (error "provide run"))
                             (tmpdir (error "provide tmpdir"))
                             (results (error "provide results")))
  (let ((files-to-resize nil))
   (loop for (title . url) in urls
         for i from 0 do
           (progn
             (safe-interrupt-checkpoint)
             (loop for root-asset in (replay:assets snapshot)
                   until (string= (replay:url root-asset) url)
                   finally
                      (let ((actual-url (quri:render-uri
                                         (quri:merge-uris
                                          (asset-file root-asset)
                                          hosted-url))))

                        (funcall logger url actual-url)

                        (a:when-let (dimension (frontend:dimensions config))
                          (window-resize :width (frontend:width dimension)
                                         :height (frontend:height dimension)))
                        (setf (webdriver-client:url)
                              actual-url)))

             ;; a temporary screenshot, I think this
             ;; will prime the browser to start loading
             ;; any assets that might be missing
             ;;(full-page-screenshot driver nil)

             (wait-for-zero-requests
              :hosted-url hosted-url
              :uuid (uuid snapshot)
              :sleep-time (sleep-time run))


             (uiop:with-temporary-file (:pathname file
                                        :directory tmpdir
                                        :type (best-image-type config)
                                        ;; will be cleared by the tmpdir
                                        :keep t)
               (delete-file file)
               (full-page-screenshot driver file)
               (push file files-to-resize)
               (record-screenshot
                results
                :pathname file
                :title (format nil "~a--~a"
                               title (frontend:browser-config-name config))))))))

(defun wait-for-zero-requests (&key hosted-url uuid sleep-time)
  (safe-interrupt-checkpoint)
  (let ((initial-timeout 1))
    (dex:get (quri:merge-uris
              (format nil "/wait-for-zero-requests?uuid=~a&timeout=~a"
                      uuid
                      initial-timeout)
              (quri:uri hosted-url)))
    (let ((remaining-time (max 0 (- sleep-time initial-timeout))))
      (when (> remaining-time 0)
        (write-replay-log "Waiting for ~a seconds now" remaining-time)
        (log:info "Waiting for ~a seconds now..." remaining-time)
        (sleep remaining-time)))))

(defun call-with-batches (list fn &key (batch-size 10))
  (labels ((call-next (list ctr)
             (multiple-value-bind (batch rest)
                 (util/lists:head list batch-size)
               (when batch
                 (restart-case
                     (funcall fn batch ctr)
                   (restart-batch ()
                     (call-next list ctr)))
                 (call-next rest (+ ctr (length batch)))))))
    (call-next list 0)))

(with-auto-restart ()
 (defun replay-job-from-snapshot (&key snapshot urls run tmpdir)
   (let* ((results (make-instance 'all-screenshots
                                   :company (company run)))
          (url-count  (length urls)))
     (prog1
         results
       (let ((configs (browser-configs run)))
         (dolist (config configs)
           (let ((selenium-server (selenium-server
                                   :type (browser-type config))))
            (call-with-hosted-snapshot
             snapshot
             (lambda (hosted-url)
               (let ((webdriver-client::*uri*
                       (selenium-server-url selenium-server)))
                 (write-replay-log "Waiting for Selenium worker of type ~a" (browser-type config))
                 (call-with-batches
                  urls
                  (lambda (urls idx)
                    (call-with-webdriver
                     (lambda (driver)
                       ;; We have our browser and our hosted snapshots, let's go through this
                       (write-replay-log "Selenium worker is ready")
                       (run-replay-on-urls
                        :snapshot snapshot
                        :urls urls
                        :hosted-url hosted-url
                        :driver driver
                        :logger (lambda (url actual-url)
                                  (write-replay-log "[~a/~a] Running url: ~a / ~a"
                                                    (incf idx)
                                                    url-count  url actual-url))
                        :config config
                        :run run
                        :tmpdir tmpdir
                        :results results))
                     :proxy (squid-proxy selenium-server)
                     :browser (frontend:browser-type config)
                     :dimensions (when (frontend:dimensions config)
                                   (cons
                                    (frontend:width (dimensions config))
                                    (frontend:height (dimensions config))))
                     :mobile-emulation (frontend:mobile-emulation config))))))
             :hostname (get-local-addr
                        (selenium-host selenium-server)
                        (selenium-port selenium-server))))))))))


(defun best-image-type (config)
  (cond
    ((string-equal "firefox" (browser-type config))
     "png")
    (t
     "png")))

(with-auto-restart ()
 (defun schedule-replay-job (run)
   (tmpdir:with-tmpdir (tmpdir)
     (handler-bind ((dex:http-request-failed
                      (lambda (e)
                        (write-replay-log "HTTP request failed: ~a~%" (type-of e))))
                    (cl+ssl::hostname-verification-error
                      (lambda (e)
                        (write-replay-log "SSL error: ~S~%" e))))
      (let* ((urls (sampled-urls run))
             (snapshot (make-instance 'snapshot :tmpdir tmpdir))
             (context (make-instance 'context
                                      :custom-css (custom-css run)))
             (count (length urls)))
        (loop for (nil . url) in urls
              for i from 1
              do
                 (restart-case
                     (progn
                       (log:info "Loading ~a/~a" i count)
                       (load-url-into context snapshot url tmpdir))
                   (ignore-this-url ()
                     (values))))
        (let ((results (replay-job-from-snapshot
                        :snapshot snapshot
                        :urls urls
                        :tmpdir tmpdir
                        :run run)))
          (process-results run results)))))))

#+nil
(schedule-replay-job (make-instance 'run
                                    :channel "test-channel"
                                    :urls (list "https://staging.screenshotbot.io")
                                    :api-key "FR7L47QK3YHMZ3Z8TEAX"
                                    :api-secret "F70tzxRVRf2VgkCTZH0j7nb9HABchakx5LEbL9lm"))