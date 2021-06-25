;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(pkg:define-package :screenshotbot/login/oidc
    (:use #:cl
          #:alexandria
          #:nibble
          #:./common)
  (:import-from #:../user-api
                #:current-user)
  (:export #:client-id
           #:client-secret
           #:oidc-provider
           #:issuer
           #:scope
           #:discover
           #:authorization-endpoint
           #:token-endpoint
           #:userinfo-endpoint
           #:access-token-class
           #:access-token-str
           #:oidc-callback
           #:prepare-oidc-user))

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

(defclass oidc-provider (abstract-oauth-provider)
  ((oauth-name :initform "Generic OIDC")
   (client-id :initarg :client-id
              :accessor client-id)
   (client-secret :initarg :client-secret
                  :accessor client-secret)
   (issuer :initarg :issuer
           :accessor issuer
           :documentation "The issuer URL, such as
           https://accounts.google.com. We'll use OpenID discovery to
           discover the rest.")
   (scope :initarg :scope
          :accessor scope
          :initform "openid"
          :documentation "The default scope used for authorization")
   (cached-discovery :initform nil
                     :accessor cached-discovery)))

(defmethod discover ((oidc oidc-provider))
  "Returns an alist of all the fields in the discovery document"
  (or
   (cached-discovery oidc)
   (setf (cached-discovery oidc)
    (let ((url (format nil "~a/.well-known/openid-configuration"
                       (issuer oidc))))
      (json:decode-json-from-string (dex:get url))))))


(defmethod authorization-endpoint ((oidc oidc-provider))
  (assoc-value (discover oidc) :authorization--endpoint))

(defmethod token-endpoint ((oidc oidc-provider))
  (assoc-value (discover oidc) :token--endpoint))

(defmethod userinfo-endpoint ((oidc oidc-provider))
  (assoc-value (discover oidc) :userinfo--endpoint))

(defgeneric oidc-callback (auth code redirect))

;; (token-endpoint (make-instance 'oidc-provider :issuer "https://accounts.google.com"))

(defun make-oidc-auth-link (oauth redirect)
  (let* ((auth-uri (quri:uri (authorization-endpoint oauth)))
         (redirect (nibble (code)
                     (oidc-callback oauth code redirect))))

    (setf (quri:uri-query-params auth-uri)
          `(("redirect_uri" . ,(hex:make-full-url hunchentoot:*request* 'oauth-callback))
            ("client_id" . ,(client-id oauth))
            ("state" . ,(format nil "~d" (nibble:nibble-id redirect)))
            ("response_type" . "code")
            ("scope" . ,(scope oauth))))
    (quri:render-uri auth-uri)))

(defmethod oauth-signin-link ((auth oidc-provider) redirect)
  (make-oidc-auth-link auth redirect))

(defmethod oauth-signup-link ((auth oidc-provider) redirect)
  (make-oidc-auth-link auth redirect))

(defun oauth-get-access-token (token-url &key client_id client_secret code
                                                      redirect_uri)
  (with-open-stream (stream (dex:post token-url
                                      :want-stream t
                                      :headers `(("Accept" . "application/json"))
                                      :content `(("client_id" . ,client_id)
                                                 ("client_secret" . ,client_secret)
                                                 ("code" . ,code)
                                                 ("grant_type" . "authorization_code")
                                                 ("redirect_uri" . ,redirect_uri))))
    (let ((resp
            (json:decode-json stream)))
      (log:info "Got response ~s" resp)
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
          access-token)))))



(defun make-json-request (url &rest args)
  (multiple-value-bind (stream status-code)
      (apply 'dex:request url
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


(defmethod oidc-callback ((auth oidc-provider) code redirect)
  (let ((token (oauth-get-access-token
                (token-endpoint auth)
                :client_id (client-id auth)
                 :client_secret (client-secret auth)
                 :code code
                 :redirect_uri (hex:make-full-url
                                hunchentoot:*request*
                                'oauth-callback))))
    (let ((user-info
            (make-json-request (userinfo-endpoint auth)
                               :method :post
                               :content `(("access_token"
                                           .
                                           ,(access-token-str token))
                                          ("alt" . "json")))))
      (let ((user (prepare-oidc-user
                   auth
                   :user-id (assoc-value user-info :sub)
                   :email (assoc-value user-info :email)
                   :full-name (assoc-value user-info :name)
                   :avatar (assoc-value user-info :picture))))
        (setf (current-user) user)
        (hex:safe-redirect redirect)))))

(defgeneric prepare-oidc-user (auth &key user-id email full-name avatar)
  (:documentation "Once we have all the information about the user
  that just logged in, convert this into a user in Screenshotbot. You
  may have to look up existing users to figure out which user this is
  mapped to."))

(defmethod prepare-oidc-user ((auth oidc-provider) &key user-id email full-name avatar)
  (declare (ignore user-id email full-name avatar))
  (error "unimplemented"))
