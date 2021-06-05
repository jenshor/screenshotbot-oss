;; Copyright 2018-Present Modern Interpreters Inc.
;;
;; This Source Code Form is subject to the terms of the Mozilla Public
;; License, v. 2.0. If a copy of the MPL was not distributed with this
;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage #:server
  (:use #:cl
        #:bknr.datastore)
  (:export #:main
           #:register-acceptor
           #:swank-loop))
(in-package #:server)

(defvar *shutdown-cv* (bt:make-condition-variable))
(defvar *server-lock* (bt:make-lock))

(defun wait-for-network ()
  (loop while t
       do
       (format t "Waiting for network...~%")
       (multiple-value-bind (output error ret-code) (trivial-shell:shell-command "ping -c1 192.168.1.1")
         (if (eq 0 ret-code)
             (return ret-code)
             (progn
               (format t "Got return code ~a~%" ret-code)
               (format t "~a" output)
               (sleep 3))))))

(defun reset-all-systems ()
  (asdf:clear-system :colada)
  (asdf:clear-system :auth)
  (asdf:clear-system :util)
  (asdf:clear-system :jipr)
  (asdf:clear-system :hightened)
  (asdf:clear-system :scaile)
  (ql:quickload "web.all"))

;; (hightened:start-hightened)

(defvar *port*)
(defvar *swank-port*)
(defvar *verify-store*)
(defvar *socketmaster*)
(defvar *shell*)

(defparameter *options*
  `((*port* "4001" "" :params ("PORT"))
    (*socketmaster* t "" :params ("SOCKETMASTER"))
    (*shell* nil "")
    (*swank-port* "4005" "" :params ("SWANK-PORT"))
    (util:*object-store* "/data/arnold/object-store/" "" :params ("OBJECT-STORE"))
    (*verify-store* nil "")))

(defclass my-acceptor (hunchentoot-multi-acceptor:multi-acceptor)
  ())

#+lispworks
(defmethod hunchentoot:start-listening ((acceptor my-acceptor))
  ;; always listen on the PORT setup on fd 3. Assuming we'll be
  ;; started by socketmaster
  (cond
    (*socketmaster*
     (setf (hunchentoot::acceptor-listen-socket acceptor)
           (usocket::make-stream-server-socket 3 :element-type '(unsigned-byte 8))))
    (t
     (call-next-method))))

(defvar *multi-acceptor*)

(defvar *init-hooks* nil)

(defun register-acceptor (acceptor &rest hostnames)
  (loop for host in hostnames do
    (let ((host host))
     (push
      (lambda ()
        (hunchentoot-multi-acceptor:add-acceptor *multi-acceptor* host acceptor))
      *init-hooks*))))

(defun init-multi-acceptor ()
  (setf *multi-acceptor* (make-instance 'my-acceptor :port (parse-integer *port*) :name 'multi-acceptor))
  (init-sub-acceptors))

(defun init-sub-acceptors ()
  (mapcar 'funcall *init-hooks*))


(defvar *multi-server*)

;; (setf hunchentoot-multi-acceptor:*default-acceptor* jipr:*jipr-acceptor*)

#+nil
(defun init-fiveam ()
  (setq fiveam:*run-test-when-defined* t)
  (setq fiveam:*debug-on-error* t)
  (setq fiveam:*debug-on-failure* t))
;; (init-fiveam)

(defun init-debug-environment ()
  (setq hunchentoot:*show-lisp-errors-p* t))

(defclass utf-8-daily-file-appender (log4cl:daily-file-appender)
  ())

(defmethod slot-unbound (class (appender utf-8-daily-file-appender)
                         (slot-name (eql 'log4cl::stream)))
  (declare (ignore class slot-name))
  (create-appender-file appender))

(defun create-appender-file (appender)
  (let ((filename (log4cl::appender-filename appender)))
    (log4cl::maybe-close-stream appender)
    (setf (slot-value appender 'stream)
          (flexi-streams:make-flexi-stream
           (open (ensure-directories-exist filename)
                 #+ccl :sharing #+ccl :external
                 :direction :output
                 :if-exists :append
                 :element-type '(unsigned-byte 8)
                 :if-does-not-exist :create)
           :external-format :utf-8
           :element-type 'character))))


;; (init-debug-environment)
;; (setf hunchentoot:*catch-errors-p* nil)
;; (setf hunchentoot:*catch-errors-p* t)
(defun main (&optional #+sbcl listen-fd)

  (bt:with-lock-held (*server-lock*)
   (let ((args (progn
                 #+lispworks system:*line-arguments-list*
                 #+sbcl sb-ext:*posix-argv*)))
     (log:info "args is: ~s" args)

     (multiple-value-bind (vars vals matched dispatch rest)
         (cl-cli:parse-cli args
                           *options*)


       (loop for var in vars
          for val in vals
             do (setf (symbol-value var) val))

       (when *verify-store*
         (util:verify-store)
         (uiop:quit 0))


       (log:info "The port is now ~a" *port*)
       (init-multi-acceptor)
       #+lispworks
       (jvm:jvm-init)
       (let ((log-file (path:catfile "log/logs")))
         (log4cl:clear-logging-configuration)
         (log:config :info)
         (log4cl:add-appender log4cl:*root-logger* (make-instance 'utf-8-daily-file-appender
                                                                  :name-format log-file
                                                                  :backup-name-format
                                                                  (format nil "~a.%Y%m%d" log-file)
                                                                  :filter 4
                                                                  :layout (make-instance 'log4cl:simple-layout))))
       (unless util:*delivered-image*
        (wait-for-network))
       #+sbcl
       (progn
         (format t "Using file descriptor ~A~%" listen-fd)
         (setf (hunchentoot-multi-acceptor:listen-fd *multi-acceptor*) listen-fd))

       ;; set this to t for 404 page. :/
       (setf hunchentoot:*show-lisp-errors-p* t)

       (setf hunchentoot:*rewrite-for-session-urls* nil)
       ;;(init-fiveam)

       (util:prepare-store)


       (log:info "starting up swank")
       (cl-cron:start-cron)
       (Server:swank-loop)


       (cond
         (*shell*
          (log:info "Swank has started up, but we're not going to start hunchentoot. Call (QUIT) from swank when done."))
         (t
          (hunchentoot:start *multi-acceptor*)))

       (log:info "Now we wait indefinitely for shutdown notifications")
       (bt:condition-wait *shutdown-cv* *server-lock*))))
  (log:info "Shutting down cron")
  (cl-cron:stop-cron)
  (log:info "Shutting down hunchentoot")
  (hunchentoot:stop *multi-acceptor*)
  (bknr.datastore:snapshot)
  (bknr.datastore:close-store)
  (log:info "Shutting down swank")
  (swank:stop-server (parse-integer *swank-port*))
  (log:info "All services down")
  #+lispworks
  (wait-for-processes)
  (log:info "All threads before exiting: ~s" (bt:all-threads))
  (log4cl:flush-all-appenders)
  (log4cl:stop-hierarchy-watcher-thread))

#+lispworks
(defun wait-for-processes ()
  (dotimes (i 30)
   (let* ((processes
           (set-difference (mp:list-all-processes) mp:*initial-processes*))
          (processes
           (loop for p in processes
              unless (member (mp:process-name p)
                             '("Hierarchy Watcher"
                               "The idle process"
                               "Restart Function Process")
                             :test 'string=)
              collect p)))

     (cond
       (processes
        (log:info "Threads remaining: ~S" processes)
        (log4cl:flush-all-appenders)
        (sleep 1))
       (t
        ;; nothing left!
        (log:info "Should be a safe shutdown!")
        (return-from wait-for-processes nil)))))
  (log:info "We waited for threads to cleanup but nothing happened, so we're going for a force uiop:quit")
  (log4cl:flush-all-appenders)
  (uiop:quit))

(defun swank-loop ()
  (log:info "Using port for swank: ~a" *swank-port*)
  (swank:create-server :port (parse-integer *swank-port*)
                       ;; if non-nil the connection won't be closed
                       ;; after connecting
                       :dont-close t))
