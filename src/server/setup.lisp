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
           #:slynk-loop))
(in-package #:server)

(defvar *shutdown-cv* (bt:make-condition-variable))
(defvar *server-lock* (bt:make-lock))

(defun wait-for-network ()
  "If you start Screenshotbot with cron @reboot, you might encounter a
situation where the Screenshotbot starts before the network is
ready. This is a quick hack around it. I'm sure there are better
ways."
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

(defvar *port*)
(defvar *slynk-port*)
(defvar *verify-store*)
(defvar *verify-snapshots*)
(defvar *socketmaster*)
(defvar *shell*)
(defvar *start-slynk*)

(defparameter *options*
  `((*port* #+screenshotbot-oss "4091"
            #-screenshotbot-oss "4001" "" :params ("PORT"))
    (*socketmaster* nil "")
    (*shell* nil "")
    (*slynk-port* #+screenshotbot-oss "4095"
                  #-screenshotbot-oss "4005"
                  "" :params ("SLYNK-PORT"))
    (*slynk-loopback-interface* "localhost" "The interface on which we bind the slynk port"
                                :params ("SLYNK-LOOPBACK-INTERFACE"))
    (*start-slynk* #+screenshotbot-oss nil
                   #-screenshotbot-oss t
                   "")
    (util:*object-store* #+screenshotbot-oss "~/.config/screenshotbot/object-store/"
                         #-screenshotbot-oss "/data/arnold/object-store/" "" :params ("OBJECT-STORE"))
    (*verify-store* nil "")
    (*verify-snapshots* nil "")
    #-sbcl
    (jvm:*libjvm* nil "Location of libjvm.so" :params ("LIBJVM"))))

(defclass my-acceptor (hunchentoot-multi-acceptor:multi-acceptor)
  ())

;; When using socketmaster to restart the server without downtime, we
;; don't open a brand new socket, instead using the socket on file
;; descriptor 3. Currently this is only tested on Lispworks, and we
;; only use this for the non-OSS port. If you want to try this out,
;; try remove this feature check and see if it works.
#+(and lispworks (not screenshotbot-oss))
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
        (log:info "Adding acceptor ~a" acceptor)
        (hunchentoot-multi-acceptor:add-acceptor *multi-acceptor* host acceptor))
      *init-hooks*)
      ;; Immediately register the acceptor if we're executing this live
      (when (boundp '*multi-acceptor*)
        (init-sub-acceptors)))))

(defun init-multi-acceptor ()
  (setf *multi-acceptor* (make-instance 'my-acceptor :port (parse-integer *port*) :name 'multi-acceptor))
  (init-sub-acceptors))

(defun init-sub-acceptors ()
  (mapc 'funcall *init-hooks*)
  (setf *init-hooks* nil))


(defvar *multi-server*)

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

(defun setup-appenders (&key clear)
  (let ((log-file (path:catfile "log/logs")))
    (when clear
     (log4cl:clear-logging-configuration))
    (log:config :info)
    (log4cl:add-appender log4cl:*root-logger*
                         (make-instance 'utf-8-daily-file-appender
                                         :name-format log-file
                                         :backup-name-format
                                         "logs.%Y%m%d"
                                         :filter 4
                                         :layout (make-instance 'log4cl:simple-layout)))))

(defun setup-log4cl-debugger-hook ()
  (when util:*delivered-image*
    ;; assume this is production: Lispworks by default uses a shitty
    ;; cl:*debugger-hook* in delivered images. It's actually pretty
    ;; buggy and doesn't work very well in low-disk situations.
    (setf cl:*debugger-hook* #'util/debugger-hook:log4cl-debugger-hook)))


(defun main (&optional #+sbcl listen-fd)
  "Called from launch scripts, either web-bin or launch.lisp"

  (bt:with-lock-held (*server-lock*)
    (let ((args #-lispworks (cons "<arg0>"(uiop:command-line-arguments))
                #+lispworks sys:*line-arguments-list*))
     (log:info "args is: ~s" args)

     (multiple-value-bind (vars vals matched dispatch rest)
         (cl-cli:parse-cli args
                           *options*)

       (loop for var in vars
          for val in vals
             do (setf (symbol-value var) val))

       (when *verify-store*
         (log:config :info)
         (util:verify-store)
         (log:info "Done verifying store")
         (uiop:quit 0))

       #+nil
       (when *verify-snapshots*
         (log:config :info)
         (util:verify-snapshots)
         (uiop:quit 0))

       (log:info "The port is now ~a" *port*)
       (init-multi-acceptor)
       #+lispworks
       (jvm:jvm-init)
       (setup-appenders)

       (setup-log4cl-debugger-hook)

       #-screenshotbot-oss
       (unless util:*delivered-image*
        (wait-for-network))

       #+sbcl
       (progn
         (format t "Using file descriptor ~A~%" listen-fd)
         (setf (hunchentoot-multi-acceptor:listen-fd *multi-acceptor*) listen-fd))

       ;; set this to t for 404 page. :/
       (setf hunchentoot:*show-lisp-errors-p* t)

       (setf hunchentoot:*rewrite-for-session-urls* nil)

       (util:prepare-store)

       (cl-cron:start-cron)

       #-sbcl
       (when *start-slynk*
         (log:info "starting up slynk")
         (Server:slynk-loop))

       (cond
         (*shell*
          (log:info "Slynk has started up, but we're not going to start hunchentoot. Call (QUIT) from slynk when done."))
         (t
          (hunchentoot:start *multi-acceptor*)))

       (log:info "The web server is live at port ~a. See logs/logs for more logs~%"
                 *port*)

       (setup-appenders :clear t)

       (log:info "Now we wait indefinitely for shutdown notifications")
       (bt:condition-wait *shutdown-cv* *server-lock*))))
  (log:info "Shutting down cron")
  (cl-cron:stop-cron)
  (log:info "Shutting down hunchentoot")
  (hunchentoot:stop *multi-acceptor*)
  (bknr.datastore:snapshot)
  (bknr.datastore:close-store)
  (log:info "Shutting down slynk")
  #-sbcl
  (slynk:stop-server (parse-integer *slynk-port*))
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

#-sbcl
(defun slynk-loop ()
  (log:info "Using port for slynk: ~a" *slynk-port*)
  (setf slynk:*loopback-interface* *slynk-loopback-interface*)
  (slynk:create-server :port (parse-integer *slynk-port*)
                       ;; if non-nil the connection won't be closed
                       ;; after connecting
                       :dont-close t))
