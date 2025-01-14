;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(in-package #:auth)

(defgeneric auth-get-user-class (acceptor)
  (:documentation "Gets the class used to store the user data"))

(defindex +sessions-index+ 'fset-set-index
  :slot-name 'session-token)

(defindex +expiry-index+ 'fset-set-index
  :slot-name 'expiry-ts)

(with-class-validation
 (defclass user-session-value (store-object)
   ((session-key-and-prop-key
     :accessor session-key-and-prop-key
     :documentation "This is an older mechanism used to find the cookies. Deprecated. It's only here for OSS support.")
    (prop-key :initarg :prop-key
              :accessor prop-key
              :documentation "The property key. e.g. :USER, or :COMPANY.")
    (session-token :initarg :session-token
                   :accessor  session-token
                   :index +sessions-index+
                   :index-reader values-for-session-token
                   :documentation "Just the session token, as a string.")
    (session-domain :initarg :session-domain
                    :accessor session-domain
                    :documentation "The domain associated with this session")
    (value
     :initarg :value
     :relaxed-object-reference t
     :accessor value)
    (last-update-ts
     :initarg :last-update-ts
     :initform (get-universal-time) #| migration |#
     :accessor last-update-ts)
    (expiry-ts
     :initarg :expiry-ts
     :initform nil
     :accessor expiry-ts
     :index +expiry-index+))
   (:metaclass persistent-class)
   (:default-initargs :last-update-ts (get-universal-time))))

(defmethod initialize-instance :after ((uv user-session-value)
                                       &key session-key #| deprecated |#
                                         prop-key
                                         value
                                         session-token
                                         session-domain)
  (declare (ignore value session-token session-domain))
  (setf (session-key-and-prop-key uv)
        (cons session-key prop-key)))

(defun find-user-session-value (token domain prop-key)
  (let ((usvs (values-for-session-token token)))
    (fset:do-set (usv usvs)
      (when (and
             (eql prop-key (prop-key usv))
             (equal domain (session-domain usv)))
        (return-from find-user-session-value usv)))))

(defvar *hash-cache* (make-hash-table :test #'equal))

(defun find-user-session-value-by-hash (session-key-hash prop-key)
  "This is used for analytics purposes since we don't want to store the
 session key itself in plain text in many places."
  (let* ((session-key-hash (ironclad:hex-string-to-byte-array session-key-hash))
         (cache-key (cons session-key-hash prop-key)))
    (util/misc:or-setf
     (gethash cache-key *hash-cache*)
     (loop for user-session-value in (bknr.datastore:store-objects-with-class 'user-session-value)
           for session-key = (car (session-key-and-prop-key user-session-value))
           if (and
               (equalp session-key-hash
                       (ironclad:digest-sequence
                        :sha256
                        (flexi-streams:string-to-octets
                         (car session-key))))
               (equal prop-key
                      (cdr session-key)))
             do
                (return (value user-session-value))))))


(defclass user-session-transient ()
  ((session-key
    :reader %session-token
    :initarg :token)
   (domain
    :reader session-domain
    :initform (host-without-port))))

(defmethod session-key ((session user-session-transient))
  (cons (%session-token session)
        (session-domain session)))


(defvar *secure-cookie-p* t)

(defparameter *cookie-name* "s2")

(defun host-without-port ()
  (car (str:split ":" (host))))

(defun set-session-cookie (token &optional domain)
  (let ((domain (or domain (host-without-port))))
    (set-cookie *cookie-name*
                :value token :domain domain :expires (+ (get-universal-time) (* 365 2600 24))
                :path "/" :secure (and
                                   *secure-cookie-p*
                                   (string=
                                    "https"
                                    (hunchentoot:header-in* :x-forwarded-proto))))))

(defun has-session? ()
  (let ((s (cookie-in *cookie-name*)))
    (and s (not (equal s "")))))

(defun drop-session (&optional domain)
  (set-session-cookie "" domain))

(defun %current-session ()
  (let ((token (cookie-in *cookie-name*)))
    (and
     token
     (not (equal "" token))
     (make-instance 'user-session-transient
                    :token token))))


(defvar *session-token-generator*)

(defvar *lock* (bt:make-lock "auth-lock"))

#+windows
(defun read-windows-seed ()
  (cl-store:restore (path:catfile (asdf:system-source-directory :auth) "dummy-init-key.out")))

(defun init-session-token-generator ()
  (setf *session-token-generator* (session-token:make-generator
                                   #+windows
                                   :initial-seed
                                   #+windows
                                   (progn
                                     (log:warn "Using insecure seed, only use on Windows")
                                     (read-windows-seed)))))

(init-session-token-generator)

#+lispworks
(lw:define-action "When starting image" "re-initialize token generator"
  #'init-session-token-generator)


(defun set-session (session &optional domain)
  (set-session-cookie (car (session-key session)) domain))

(defun set-session-user-id (user-id &optional domain)
  (assert user-id)
  (setf (session-value :user-id) user-id))

(defun generate-session-token ()
  (bt:with-lock-held (*lock*)
    (funcall *session-token-generator*)))

(defun %make-session ()
  "Only creates the session, does not do anything else with it"
  (let ((session (make-instance 'user-session-transient
                                :token
                                (generate-session-token))))

    session))

(defvar *current-session*)

(defvar *iterations* 20000)

(defun session= (session1 session2)
  (and
   (string= (%session-token session1)
            (%session-token session2))
   (string= (session-domain session1)
            (session-domain session2))))

(defun %with-sessions (body)
  (cond
    ((boundp '*current-session*)
     (funcall body))
    (t
     (let ((*current-session* (%current-session)))
       (unless *current-session*
         (setf *current-session* (%make-session))
         (set-session *current-session*)
         (assert *current-session*))
       (funcall body)))))

(defmacro with-sessions (() &body body)
  "Inside of this macro CURRENT-SESSION will always return a non-nil
value."
  `(%with-sessions (lambda () ,@body)))

(defun current-session ()
  *current-session*)

(defun session-value (key &key (session (current-session)))
  (let ((x (find-user-session-value (%session-token session)
                                    (session-domain session)
                                    key)))
    (and x
         (value x))))


(defun (setf session-value) (value key &key (session (current-session))
                                         expires-in)
  (let ((expiry-ts (when expires-in (+ (get-universal-time) expires-in))))
    (bt:with-lock-held (*lock*)
      (let ((x (find-user-session-value (%session-token session)
                                        (session-domain session)
                                        key)))
        (cond
          (x
           (bknr.datastore:with-transaction ()
             (setf (last-update-ts x) (get-universal-time))
             (when expiry-ts
               (setf (expiry-ts x) expiry-ts))
             (setf (value x) value)))
          (t
           (make-instance 'user-session-value
                          :session-token (%session-token session)
                          :session-domain (session-domain session)
                          :session-key (session-key session) #| deprecated |#
                          :expiry-ts expiry-ts
                          :value value
                          :prop-key key)))
        value))))

(defgeneric password-hash (user)
  (:documentation "password hash for the user"))

(defmethod csrf-token ()
  (util/misc:or-setf
   (session-value :csrf-token)
   (generate-session-token)
   :thread-safe t))


(defmethod check-password (user password)
  (and user
   (cl-pass:check-password password (auth:password-hash user))))

(defmethod (setf user-password) (password user)
  (setf (auth:password-hash user)
        (cl-pass:hash password :iterations *iterations*)))

(defclass login-controller ()
  ((login-page
    :initarg :login-page)))

(defmacro safe-setf (place val)
  (alexandria:with-gensyms (xval)
    `(let ((,xval ,val))
       (unless (equal (ignore-errors ,place) ,xval)
         (with-transaction ()
           (setf ,place ,xval))))))

(def-store-migration ("auth: Set individual slots from keys" :version 5)
  (dolist (usv (class-instances 'user-session-value))
    (when (session-key-and-prop-key usv)
     (destructuring-bind ((token . domain) . prop-key) (session-key-and-prop-key usv)
       (safe-setf (session-token usv) token)
       (safe-setf (session-domain usv) domain)
       (safe-setf (prop-key usv) prop-key)))))

(defun clean-session-values (&optional (ts (get-universal-time)))
  (let ((smallest (index-least +expiry-index+)))
    (when (and
           smallest
           (< (expiry-ts smallest) ts))
      (delete-object smallest)
      (clean-session-values ts))))

(def-cron clean-session-values (:minute 5 :step-hour 1)
  (clean-session-values))
