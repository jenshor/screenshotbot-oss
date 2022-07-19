(defpackage :screenshotbot/hub/server
  (:use #:cl)
  (:import-from #:util/misc
                #:or-setf)
  (:local-nicknames (#:a #:alexandria))
  (:export
   #:hub
   #:relay-session-request
   #:*hub*))
(in-package :screenshotbot/hub/server)

(defclass local-hub ()
  ())


(defparameter +json-content-type+
  "application/json; charset=UTF-8")

(defvar *hub* nil)

(defun hub ()
  (or-setf
   *hub*
   (let ((hub (make-instance 'local-hub)))
     (start-hub hub)
     hub)
   :thread-safe t))

(defmethod start-hub ((self local-hub)))

(auto-restart:with-auto-restart ()
 (defmethod request-session-and-respond ((hub local-hub)
                                         (arguments string))
   (multiple-value-bind (data ret)
       (util/request:http-request
        (format nil "http://localhost:4444/wd/hub/session")
        :method :post
        :want-string t
        :content-type +json-content-type+
        :content arguments
        :external-format-out :utf-8)
     (assert (not (eql ret 500)))
     (setf (hunchentoot:return-code*) ret)
     (setf (hunchentoot:content-type*) +json-content-type+)
     data)))

(auto-restart:with-auto-restart ()
  (defmethod relay-session-request ((hub local-hub)
                                    &key (method (error "provide method"))
                                      (script-name (error "provide-script-name"))
                                      (content (error "provide content"))
                                      (content-type (error "provide-content-type")))
    (log:info "Relaying request for ~a" script-name)
    (multiple-value-bind (data ret headers)
        (util/request:http-request
         (format nil "http://localhost:4444~a"
                 script-name)
         :method method
         :want-string t
         :content-type content-type
         :content content)
      (assert (not (eql ret 500)))
      (setf (hunchentoot:return-code*) ret)
      (setf (hunchentoot:content-type*) (a:assoc-value headers :content-type))
      data)))
