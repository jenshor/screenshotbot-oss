;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(pkg:define-package :oidc/oidc
    (:use #:cl
          #:alexandria)
  (:import-from #:nibble
                #:nibble)
  (:import-from #:util/request
                #:http-request)
  (:export #:oidc
           #:issuer
           #:discover
           #:authorization-endpoint
           #:token-endpoint
           #:userinfo-endpoint
           #:end-session-endpoint
           #:client-id
           #:client-secret
           #:scope
           #:oauth-access-token
           #:access-token-str
           #:oauth-get-access-token
           #:oidc-callback
           #:on-successful-oauth
           #:after-authentication
           #:make-oidc-auth-link
           #:logout-link))

(defclass oauth-access-token ()
  ((access-token :type (or null string)
                 :initarg :access-token
                 :accessor access-token-str)
   (expires-in :type (or null integer)
               :initarg :expires-in)
   (refresh-token :type (or null string)
                  :initarg :refresh-token)
   (refresh-token-expires-in :type (or null integer)
                             :initarg :refresh-token-expires-in)
   (scope :type (or null string)
          :initarg :scope)
   (token-type :type (or null string)
               :initarg :token-type)))

(defclass oidc ()
  ((issuer :initarg :issuer
           :accessor issuer
           :documentation "The issuer URL, such as
           https://accounts.google.com. We'll use OpenID discovery to
           discover the rest.")
   (oauth-callback
    :initarg :callback-endpoint
    :reader oauth-callback
    :documentation "A handler that will always be used as the redirect
    endpoint. This handler should look at the actual state parameter,
    and treat it as a nibble id, and execute the said nibble (or
    redirect to the nibble)")
   (client-id :initarg :client-id
              :accessor client-id)
   (client-secret :initarg :client-secret
                  :accessor client-secret)
   (scope :initarg :scope
          :accessor scope
          :initform "openid"
          :documentation "The default scope used for authorization")
   (cached-discovery :initform nil
                     :accessor cached-discovery)))

(defmethod logout-link ((self oidc))
  "RP initiated logout link: https://openid.net/specs/openid-connect-rpinitiated-1_0.html.

  In theory, this should should be implemented using the end_session_endpoint, but for now we're only implementing it for AWS Cognito."
  (error "logout link not implemented for this"))

(defun check-https (url)
  "Our OpenID Connect implementation does not do id-token
  verification. But to still ensure security we have to make sure all
  our calls to the Auth server go ever HTTPS"
  (when url
   (unless (equal "https" (quri:uri-scheme (quri:uri url)))
     (error "Using non https endpoint ~a for authentication" url)))
  url)

(defmethod discover ((oidc oidc))
  "Returns an alist of all the fields in the discovery document"
  (or
   (cached-discovery oidc)
   (setf (cached-discovery oidc)
         (let ((url (format nil "~a/.well-known/openid-configuration"
                            (check-https
                             (issuer oidc)))))
      (json:decode-json-from-string (dex:get url))))))


(defmethod authorization-endpoint ((oidc oidc))
  (check-https
   (assoc-value (discover oidc) :authorization--endpoint)))

(defmethod token-endpoint ((oidc oidc))
  (check-https
   (assoc-value (discover oidc) :token--endpoint)))

(defmethod userinfo-endpoint ((oidc oidc))
  (check-https
   (assoc-value (discover oidc) :userinfo--endpoint)))

(defmethod end-session-endpoint ((oidc oidc))
  (check-https
   (assoc-value (discover oidc) :end--session--endpoint)))

(defun oauth-get-access-token (token-url &key client_id client_secret code
                                           redirect_uri)
  (assert code)
  (let* ((resp (http-request token-url
                             :method :post
                             :want-string t
                             :accept "application/json"
                             :parameters
                             `(("client_id" . ,client_id)
                               ("client_secret" . ,client_secret)
                               ("code" . ,code)
                               ("grant_type" . "authorization_code")
                               ("redirect_uri" . ,redirect_uri))))
         (resp (json:decode-json-from-string resp)))
    (when (assoc-value resp :error)
      (error "oauth error: ~s" (assoc-value resp :error--description)))
    (flet ((v (x) (assoc-value resp x)))
      (let ((access-token (make-instance 'oauth-access-token
                                         :access-token (v :access--token)
                                         :expires-in (v :expires--in)
                                         :refresh-token (v :refresh--token)
                                         :refresh-token-expires-in (v :refresh--token--expires--in)
                                         :scope (v :scope)
                                         :token-type (v :token--type))))
        access-token))))

(defun make-json-request (url &rest args)
  (multiple-value-bind (stream status-code)
      (apply 'util/request:http-request url
             :want-stream t
             args)
    (with-open-stream (stream stream)
     (case status-code
       (200
        (values
         (json:decode-json stream)
         status-code))
       (otherwise
        (error "Failed to make json request, status code ~a" status-code))))))

(define-condition authentication-error (error)
  ((message :initarg :message
            :reader authentication-error-message)))

(defmethod user-info ((auth oidc) token)
  (make-json-request (userinfo-endpoint auth)
                     :method :post
                     :parameters `(("alt" . "json"))
                     :additional-headers `(("Authorization".
                                                           ,(format nil "Bearer ~a"
                                                                    (Access-token-str token))))))

(defmethod oidc-callback ((auth oidc) code redirect
                          &key error
                            (error-redirect "/"))
  (cond
    (code
     (let ((token (oauth-get-access-token
                   (token-endpoint auth)
                   :client_id (client-id auth)
                   :client_secret (client-secret auth)
                   :code code
                   :redirect_uri (hex:make-full-url
                                  hunchentoot:*request*
                                  (oauth-callback auth)))))
       (let ((user-info
               (user-info auth token)))
         (log:debug "Got user info ~S" user-info)
         (verify-userinfo auth user-info)
         (handler-case
             (after-authentication
              auth
              :user-id (assoc-value user-info :sub)
              :email (assoc-value user-info :email)
              :full-name (assoc-value user-info :name)
              :avatar (assoc-value user-info :picture))
           (authentication-error (e)
             (hex:safe-redirect error-redirect :error (authentication-error-message e)))))))
    (t
     ;; error the OAuth flow, most likely
     (warn "Oauth failed: ~a" error)
     (hex:safe-redirect error-redirect :error error))))

(defmethod verify-userinfo (oidc user-info))

(defgeneric after-authentication (oidc &key
                                         user-id
                                         email
                                         full-name
                                         avatar))

(defmethod oidc-callback :after ((auth oidc) code redirect &key &allow-other-keys)
  (declare (ignore code))
  (hex:safe-redirect redirect))

(defmethod make-oidc-auth-link ((oauth oidc) redirect
                                &key (error-redirect "/"))
  (let* ((auth-uri (quri:uri (authorization-endpoint oauth)))
         (redirect (nibble (code error)
                     (oidc-callback oauth code redirect
                                    :error error
                                    :error-redirect error-redirect))))
    (setf (quri:uri-query-params auth-uri)
          `(("redirect_uri" . ,(hex:make-full-url hunchentoot:*request* (oauth-callback oauth)))
            ("client_id" . ,(client-id oauth))
            ("state" . ,(format nil "~d" (nibble:nibble-id redirect)))
            ("response_type" . "code")
            ("scope" . ,(scope oauth))))
    (quri:render-uri auth-uri)))
