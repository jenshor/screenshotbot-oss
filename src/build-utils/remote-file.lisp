(defpackage :build-utils/remote-file
  (:use #:cl
        #:asdf)
  (:local-nicknames (#:a #:alexandria))
  (:export
   #:remote-file))
(in-package :build-utils/remote-file)

(defclass remote-file (asdf:system)
  ((url :initarg :url
        :reader url)
   (version :initarg :version
            :reader version)
   (remote-file-type :initarg :remote-file-type
		     :initform nil
		     :reader remote-file-type)))

(defmethod perform ((o compile-op) (s remote-file))
  (unless (version s)
    (error "Provide a version for remote-jar-file for caching purposes"))
  (let ((output (output-file o s)))
    (unless (uiop:file-exists-p output)
      (uiop:with-staging-pathname (output)
        (format t "Downloading asset: ~a~%" (url s))
        (with-open-stream (in (dex:get (url s) :want-stream t :force-binary t))
          (with-open-file (out output :element-type '(unsigned-byte 8) :direction :output
                               :if-exists :supersede)
           (uiop:copy-stream-to-stream in out :element-type '(unsigned-byte 8))))))))

(defmethod output-files ((o compile-op) (s remote-file))
  (list
   (format nil "~a-~a.~a" (component-name s)
           (version s)
           (remote-file-type s))))
