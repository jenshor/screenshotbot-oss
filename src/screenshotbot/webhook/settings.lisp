;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/webhook/settings
  (:use #:cl)
  (:import-from #:screenshotbot/settings-api
                #:settings-template
                #:defsettings)
  (:import-from #:nibble
                #:nibble)
  (:import-from #:util/form-errors
                #:with-error-builder
                #:with-form-errors)
  (:import-from #:screenshotbot/model/company
                #:company-admin-p)
  (:import-from #:screenshotbot/user-api
                #:current-user
                #:current-company)
  (:import-from #:bknr.datastore
                #:delete-object
                #:deftransaction)
  (:import-from #:screenshotbot/webhook/model
                #:enabledp
                #:signing-key
                #:endpoint
                #:webhook-company-config
                #:webhook-config-for-company)
  (:import-from #:alexandria
                #:when-let)
  (:import-from #:util/misc
                #:?.))
(in-package :screenshotbot/webhook/settings)

(named-readtables:in-readtable markup:syntax)

(defun post-webhook-settings (endpoint signing-key enabled)
  (with-error-builder (:check check :errors errors
                       :form-builder (get-webhook-settings)
                       :form-args (:endpoint endpoint
                                   :signing-key signing-key
                                   :enabled enabled)
                       :success
                       (update-config
                        :company (current-company)
                        :endpoint endpoint
                        :signing-key signing-key
                        :enabled (string-equal "on" enabled)))
    (check :endpoint
           (ignore-errors (quri:parse-uri endpoint))
           "The URL must be valid")
    (check :signing-key
           (>= (length signing-key) 8)
           "Insecure signing key, must be at least 8 characters long.")
    (check nil (company-admin-p
                (current-company)
                (current-user))
           "You must be an admin to update this setting")))

(defvar *lock* (bt:make-lock))

(defun update-config (&key company endpoint signing-key enabled)
  (bt:with-lock-held (*lock*)
    (when-let ((prev (webhook-config-for-company company)))
      (delete-object prev))
    (make-instance 'webhook-company-config
                   :company company
                   :endpoint endpoint
                   :signing-key signing-key
                   :enabledp enabled)
    (hex:safe-redirect "/settings/webhook")))

(defun get-webhook-settings ()
  (let ((config (webhook-config-for-company (current-company)))
        (post (nibble (endpoint signing-key enable)
                (post-webhook-settings endpoint signing-key enable))))
    <settings-template>
      <form method= "post" action= post >
        <div class= "card mt-3">
          <div class= "card-header">
            <h3>Webhooks</h3>
          </div>
          <div class= "card-body">
            <div class= "form-group mb-3">
              <label for= "endpoint" class= "form-label" >Webhook Endpoint</label>
              <input type= "text" class= "form-control" placeholder= "https://example.com/screenshotbot/webhook" id= "endpoint" name= "endpoint" value= (?. endpoint config) />
            </div>

            <div class= "form-group mb-3">
              <label class= "form-label" for= "signing-key" >Signing Secret Key</label>
              <input type= "password" name= "signing-key" id= "signing-key" class= "form-control mb-3"

                     value= (?. signing-key config) />

              <div class= "text-muted">
                The signing key can be any string. It will be used to compute an SHA256 HMAC which
                will be sent along with the payload to verify that this was generated by Screenshotbot.
              </div>
            </div>

            <div class= "form-group mb-3">
              <input type= "checkbox" name= "enabled" class= "form-check-input" id= "enabled"
                     checked= (if (?. enabledp config) "checked" nil) />
              <label for= "enabled" class= "form-check-label">Enable webhooks</label>
            </div>
          </div>

          <div class= "card-footer">
            <input type= "submit" class= "btn btn-primary" value= "Save" />
          </div>
        </div>
      </form>
    </settings-template>))

(defsettings webhook
  :name "webhook"
  :title "Webhooks"
  :section :developers
  :handler 'get-webhook-settings)
