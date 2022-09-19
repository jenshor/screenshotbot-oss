(defpackage :screenshotbot/sdk/firebase
  (:use #:cl)
  (:import-from #:util/macros
                #:def-easy-macro)
  (:local-nicknames (#:a #:alexandria)
                    (#:flags #:screenshotbot/sdk/flags))
  (:export
   #:parse-firebase-output
   #:with-firebase-output))
(in-package :screenshotbot/sdk/firebase)

(defclass firebase-output ()
  ((bucket
    :initarg :bucket
    :reader firebase-output-bucket)
   (location :initarg :location
             :reader firebase-output-location)))


(defun parse-firebase-output (output)
  (flet ((oops ()
           (error "Could not parse the firebase output file! Please reach out to support@screenshotbot.io")))
   (let ((lines (str:lines output)))
     (loop for line in lines
           if (str:containsp "Raw results will be stored in" line)
             return
             (multiple-value-bind (full parts)
                 (cl-ppcre:scan-to-strings
                  "\\[https://console.developers.google.com/storage/browser/(.*)/(.*)/\\]"
                  line)
               (unless full
                 (oops))
               (make-instance 'firebase-output
                               :bucket (elt parts 0)
                               :location (elt parts 1)))
           finally
              (oops)))))

(defun artifact-dir-p (dir)
  (equal "artifacts" (car (last (pathname-directory dir)))))

(defun find-artifacts-directory (dir)
  (cond
    ((artifact-dir-p dir)
     dir)
    (t
     (loop for child in (fad:list-directory dir)
           for artifact = (find-artifacts-directory child)
           if artifact
             return artifact))))


(def-easy-macro with-firebase-output (filename &fn fn)
  (let ((firebase-output (parse-firebase-output (uiop:read-file-string filename))))
    (tmpdir:with-tmpdir (dir)
      (let ((cloud-location (format nil "gs://~a/~a/"
                                    (firebase-output-bucket firebase-output)
                                    (firebase-output-location firebase-output))))
        (log:info "Downloading screenshots from Google Cloud: ~a" cloud-location)
        (uiop:run-program
         (list "gcloud" "alpha" "storage" "cp" "-r"
               cloud-location
               (namestring dir))
         :output *standard-output*
         :error-output *standard-output*)
        (log:info "Cleaning up the Google cloud directory before we continue")
        (uiop:run-program
         (list "gcloud" "alpha" "storage" "rm" "-r"
               cloud-location)
         :output *standard-output*
         :error-output *standard-output*))

      (log:info "Downloaded screenshots, processing it locally")
      (let ((artifacts (find-artifacts-directory dir)))
        (let ((flags:*directory* (namestring (path:catfile artifacts "screenshot_bundle.zip")))
              (flags:*metadata* (namestring (path:catfile artifacts "metadata.xml"))))
          (funcall fn))))))
