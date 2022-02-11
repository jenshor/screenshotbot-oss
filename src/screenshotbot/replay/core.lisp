;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/replay/core
  (:use #:cl)
  (:local-nicknames (#:a #:alexandria))
  (:export
   #:rewrite-css-urls
   #:*replay-logs*
   #:tmpdir
   #:asset-file
   #:snapshot-urls
   #:root-asset
   #:asset-file
   #:asset-response-headers
   #:asset-status
   #:load-url
   #:root-assets))
(in-package :screenshotbot/replay/core)

(defclass marshablable ()
  ())

(defvar *replay-logs* *terminal-io*)

(defclass asset (marshablable)
  ((file :initarg :file
         :reader asset-file)
   (url :initarg :url
        :reader url)
   (status :initarg :status
           :reader asset-status)
   (stylesheetp :initarg :stylesheetp
                :initform nil
                :reader stylesheetp)
   (response-headers :initarg :response-headers
                     :reader asset-response-headers)))

(defmethod initialize-instance :after ((self asset) &key url &allow-other-keys)
  (assert (stringp url)))

(defmethod class-persistent-slots ((self asset))
  '(file status stylesheetp response-headers))

(defclass snapshot (marshablable)
  ((urls :initform nil
         :accessor snapshot-urls)
   (tmpdir :initarg :tmpdir
           :reader tmpdir)
   (root-asset :accessor root-asset)
   (root-assets :accessor root-assets
                :initform nil)))

(defmethod class-persistent-slots ((self snapshot))
  '(urls tmpdir root-asset))

(defmethod process-node (node snapshot url)
  (values))

(defun fix-asset-headers (headers)
  "Fix some bad headers"
  (loop for k being the hash-keys of headers
        if (string-equal "Access-Control-Allow-Origin" k)
          do (setf (gethash k headers) "*")
        if (string-equal "Cache-control" k)
          do (Setf (gethash k headers) "no-cache")))

(defun call-with-fetch-asset (fn type tmpdir &key url)
  (multiple-value-bind (remote-stream status response-headers)
      (funcall fn)
    ;; dex:get should handle redirects, but just in case:
    (assert (not (member status `(301 302))))
    (fix-asset-headers response-headers)

    (uiop:with-temporary-file (:pathname p :stream out :directory tmpdir :keep t
                               :element-type '(unsigned-byte 8)
                               :direction :io)
      (with-open-stream (input remote-stream)
        (uiop:copy-stream-to-stream input out :element-type '(unsigned-byte 8))
        (file-position out 0))
      (finish-output out)

      (write-asset p type
                   :tmpdir tmpdir
                   :url url
                   :response-headers response-headers
                   :status status))))

(defun hash-file (file)
  (ironclad:digest-file :sha256 file))

(defun write-asset (p type &key tmpdir
                             url
                             response-headers
                             stylesheetp
                             status)
  (let ((hash (ironclad:byte-array-to-hex-string (hash-file p))))
    (uiop:rename-file-overwriting-target
     p (make-pathname
        :name hash
        :type type
        :defaults tmpdir))
    (make-instance
     'asset
     :file (format nil
                   "/assets/~a"
                   (make-pathname :name hash :type type
                                  :directory `(:relative)))
     :url (cond
            ((stringp url)
             url)
            (t
             (quri:render-uri url)))
     :response-headers (loop for k being the hash-keys in response-headers
                                             using (hash-value v)
                                           collect (cons k v))
     :stylesheetp stylesheetp
     :status status)))

(defun http-get-without-cache (url &key (force-binary t))
  (multiple-value-bind (remote-stream status response-headers)
        (handler-case
      (progn
        (log:info "Fetching: ~a" url)
        (format *replay-logs* "Fetching: ~a~%" url)
        (finish-output *replay-logs*)
        (dex:get url :want-stream t :force-binary force-binary))
    (dex:http-request-failed (e)
      (values
       (make-string-input-stream "")
       (dex:response-status e)
       (dex:response-headers e))))
    (setf (gethash "X-Original-Url" response-headers) (quri:render-uri url))
    (values remote-stream status response-headers)))

(let ((cache-dir))
 (defun http-cache-dir ()
   (util:or-setf
    cache-dir
    (tmpdir:mkdtemp))))

(defun read-file (file)
  (with-open-file (s file :direction :input)
    (read s)))

(defun write-to-file (form file)
  (with-open-file (s file :direction :output :if-exists :supersede)
    (write form :stream s)))

(defun http-get (url &key (force-binary t)
                       (cache t))
  (let ((cache-key (format
                    nil "~a-~a-v4"
                    (ironclad:byte-array-to-hex-string (ironclad:digest-sequence :sha256 (flexi-streams:string-to-octets  (quri:render-uri url))))
                    force-binary)))
    (let* ((output (make-pathname :name cache-key :type "data" :defaults (http-cache-dir)))
           (status (make-pathname :type "status" :defaults output))
           (headers (make-pathname :type "headers" :defaults output)))
      (flet ((read-cached ()
               (values
                (open output :element-type (if force-binary
                                               '(unsigned-byte 8)
                                               'character))
                (read-file status)
                (a:alist-hash-table
                 (read-file headers))))
             (good-cache-p (file)
               (and
                (uiop:file-exists-p file)
                (> (file-write-date file)
                   (- (get-universal-time) 3600)))))
        (cond
          ((and cache (every #'good-cache-p (list output status headers)))
           (format *replay-logs* "Using cached asset for ~a~%" url)
           (read-cached))
         (t
          ;; we're not cached yet
          (multiple-value-bind (stream %status %headers)
              (http-get-without-cache url :force-binary t)
            (with-open-file (output output :element-type '(unsigned-byte 8)
                                           :if-exists :supersede
                                           :direction :output)
              (uiop:copy-stream-to-stream stream output :element-type '(unsigned-byte 8)))
            (write-to-file %status status)
            (write-to-file (a:hash-table-alist %headers) headers))
          (read-cached)))))))

(defmethod fetch-asset (url tmpdir)
  "Fetches the url into a file <hash>.<file-type> in the tmpdir."
  (let ((pathname (ignore-errors (quri:uri-file-pathname url))))
   (restart-case
       (call-with-fetch-asset
        (lambda ()
          (http-get url))
        (cond
          (pathname
           (pathname-type pathname))
          (t
           nil))
        tmpdir
        :url url)
     (retry-fetch-asset ()
       (fetch-asset url tmpdir)))))

(defun regexs ()
  ;; taken from https://github.com/callumlocke/css-url-rewriter/blob/master/lib/css-url-rewriter.js
  (uiop:read-file-lines
   (asdf:system-relative-pathname :screenshotbot.pro "replay-regex.txt")))

(defun rewrite-css-urls (css fn)
  (destructuring-bind (property-matcher url-matcher) (regexs)
    (declare (ignore property-matcher))
    (let ((url-scanner (cl-ppcre:create-scanner url-matcher)))
      (cl-ppcre:regex-replace-all
       url-scanner
       css
       (lambda (match start end match-start match-end reg-starts reg-ends)
         (let ((url (subseq match (elt reg-starts 0)
                            (elt reg-ends 0))))
           (cond
             ((str:starts-with-p "data:" url)
              ;; we never wan't to rewrite data urls
              url)
             (t
              (format nil "url(~a)" (funcall fn url))))))))))


(defmethod fetch-css-asset ((snapshot snapshot) url tmpdir)
  (multiple-value-bind (remote-stream status response-headers) (http-get url :force-binary nil)
    (with-open-stream (remote-stream remote-stream)
     (uiop:with-temporary-file (:stream out :pathname p :type "css"
                                :directory (tmpdir snapshot))
       (flet ((rewrite-url (this-url)
                (let ((full-url (quri:merge-uris this-url url)))
                  (asset-file
                   (push-asset snapshot full-url nil)))))
         (let* ((css (uiop:slurp-stream-string remote-stream))
                (css (rewrite-css-urls css #'rewrite-url)))
           (write-string css out)
           (finish-output out)))
       (write-asset p "css"
                    :tmpdir (tmpdir snapshot)
                    :url url
                    :status status
                    :stylesheetp t
                    :response-headers response-headers)))))

(defmethod push-asset ((snapshot snapshot) url stylesheetp)
  (let ((stylesheetp (or stylesheetp (str:ends-with-p ".css" (quri:render-uri url)))))
   (symbol-macrolet ((cache (a:assoc-value (snapshot-urls snapshot)
                                           (quri:render-uri url)
                                           :test #'string=)))
     (or
      cache
      (let ((new-val (cond
                       (stylesheetp
                        (fetch-css-asset snapshot url (tmpdir snapshot)))
                       (t
                        (fetch-asset url (tmpdir snapshot))))))
        (setf cache new-val))))))

(defun read-srcset (srcset)
  (flet ((read-spaces (stream)
           (loop while (let ((ch (peek-char nil stream nil)))
                         (and ch
                              (str:blankp ch)))
                     do (read-char stream nil))))
   (let ((stream (make-string-input-stream srcset)))
     (read-spaces stream)
     (loop while (peek-char nil stream nil)
           collect
           (cons
            (str:trim
             (with-output-to-string (url)
               (loop for ch = (read-char stream nil)
                     while (and ch
                                (not (str:blankp ch)))
                     do
                        (write-char ch url))
               (read-spaces stream)))
            (str:trim
             (with-output-to-string (width)
               (loop for ch = (read-char stream nil)
                     while (and ch
                                (not (eql #\, ch)))
                     do
                        (write-char ch width))
               (read-spaces stream))))))))

(defmethod process-node ((node plump:element) snapshot root-url)
  (let ((name (plump:tag-name node)))
    (labels ((? (test-name)
               (string-equal name test-name))
             (safe-replace-attr (name fn)
               "Replace the attribute if it exists with the output from the function"
               (let ((val (plump:attribute node name)))
                 (when (and val
                            (not (str:starts-with-p "data:" val)))
                   (let* ((ref-uri val)
                          (uri (quri:merge-uris ref-uri root-url)))
                    (setf (plump:attribute node name) (funcall fn uri))))))
             (replace-attr (name &optional stylesheetp)
               (safe-replace-attr
                name
                (lambda (uri)
                  (let* ((asset (push-asset snapshot uri stylesheetp))
                         (res (asset-file asset)))
                    res))))
             (parse-intrinsic (x)
               (parse-integer (str:replace-all "w" "" x)))
             (replace-srcset (name)
               (ignore-errors
                (let ((srcset (plump:attribute node name)))
                  (when srcset
                    (let* ((data (read-srcset srcset))
                           (smallest-width
                             (loop for (nil . width) in data
                                   minimizing (parse-intrinsic width)))
                           (max-width (max 500 smallest-width)))

                      (let ((final-attr
                              (str:join
                               ","
                               (loop for (url . width) in  data
                                     for uri = (quri:merge-uris url root-url)
                                     if (<= (parse-intrinsic width) max-width)
                                       collect
                                       (let ((asset (push-asset snapshot uri nil)))
                                         (str:join " "
                                                   (list
                                                    (asset-file asset)
                                                    width)))))))
                        (setf (plump:attribute node name)
                              final-attr))))))))
      (cond
       ((or (? "img")
            (? "source"))
        (replace-attr "src")
        (replace-srcset "srcset")
        ;; webpack? Maybe?
        ;;(replace-attr "data-src")
        ;;(replace-srcset "data-srcset")
        (plump:remove-attribute node "decoding")
        (plump:remove-attribute node "loading")
        (plump:remove-attribute node "data-gatsby-image-ssr"))
       ((? "picture")
        (replace-srcset "srcset"))
       ((? "iframe")
        (setf (plump:attribute node "src")
              "/iframe-not-supported"))
       ((? "video")
        ;; autoplay videos mess up screenshots
        (plump:remove-attribute node "autoplay"))
       ((? "link")
        (let ((rel (plump:attribute node "rel")))
         (cond
           ((string-equal "canonical" rel)
            ;; do nothing
            (values))
           (t
            (replace-attr "href" (string-equal "stylesheet" rel))))))
       ((? "script")
        (replace-attr "src")))))
  (call-next-method))

(defmethod process-node ((node plump:nesting-node) snapshot root-url)
  (loop for child across (plump:children node)
        do (process-node child snapshot root-url))
  (call-next-method))

(defmethod process-node :before (node snapshot root-url)
  ;;(log:info "Looking at: ~S" node)
  )

(defun add-css (html)
  "Add the replay css overrides to the html"
  (let* ((head (elt (lquery:$ html "head") 0))
         (link (plump:make-element
                head "link")))
    (setf (plump:attribute link "href") "/css/replay.css")
    (setf (plump:attribute link "rel") "stylesheet")))

(defun load-url-into (snapshot url tmpdir)
  (let* ((content (dex:get url))
         (html (plump:parse content)))
    (process-node html snapshot url)
    (add-css html)

    #+nil(error "got html: ~a"
                (with-output-to-string (s)
                  (plump:serialize html s)))
    (uiop:with-temporary-file (:direction :io :stream tmp :element-type '(unsigned-byte 8))
      (let ((root-asset (call-with-fetch-asset
                         (lambda ()
                           (plump:serialize html (flexi-streams:make-flexi-stream tmp :element-type 'character :external-format :utf-8))
                           (file-position tmp 0)
                           (let ((headers (make-hash-table)))
                             (setf (gethash "content-type" headers)
                                   "text/html; charset=UTF-8")
                             (values tmp 200 headers)))
                         "html"
                         tmpdir
                         :url url)))
        (push (cons url root-asset)
              (root-assets snapshot))
        (setf (a:assoc-value (snapshot-urls snapshot) url)
              root-asset)
        (setf (root-asset snapshot)
              root-asset)))
     snapshot))

(defun load-url (url tmpdir)
  (let ((snapshot (make-instance 'snapshot :tmpdir tmpdir)))
    (error "old, unimplemented because it started breaking")
    #+nil
    (load-url-info snapshot url)))

;; (render "https://www.rollins.edu/college-of-liberal-arts")
