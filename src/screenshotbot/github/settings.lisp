;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(uiop:define-package :screenshotbot/github/settings
  (:use #:cl
        #:alexandria
        #:markup
        #:screenshotbot/model/company
        #:screenshotbot/model/github
        #:screenshotbot/user-api
        #:screenshotbot/settings-api)
  (:import-from #:screenshotbot/github/plugin
                #:app-name
                #:github-plugin)
  (:import-from #:screenshotbot/server
                #:defhandler
                #:with-login)
  (:import-from
   #:bknr.datastore
   #:with-transaction)
  (:local-nicknames (#:a #:alexandria))
  (:import-from #:screenshotbot/github/webhook
                #:*hooks*)
  (:import-from #:bknr.datastore
                #:class-instances)
  (:import-from #:nibble
                #:nibble)
  (:import-from #:screenshotbot/github/read-repos
                #:read-repo-list)
  (:import-from #:screenshotbot/ui/simple-card-page
                #:simple-card-page))
(in-package :screenshotbot/github/settings)

(markup:enable-reader)


(defun github-app-installation-callback (state installation-id setup-action)
  (restart-case
      (with-login ()
        (let ((config (github-config (current-company))))
          (cond
            ((str:s-member (list "install" "update") setup-action)
             (with-transaction ()
               (setf (installation-id config)
                     (parse-integer installation-id))))
            (t
             (error "unsupported setup-action: ~S" setup-action))))
        (hex:safe-redirect "/settings/github"))
    (retry-app-installation-callback ()
      (github-app-installation-callback state installation-id setup-action))))

(defun installation-delete-webhook (json)
  (let ((installation (a:assoc-value json :installation)))
   (when (and (equal "deleted" (a:assoc-value json :action))
              installation)
     (let ((id (a:assoc-value installation :id)))
       (delete-installation-by-id id)))))

(defun delete-installation-by-id (id)
  (log:info "Deleting by installation by id: ~a" id)
  (loop for github-config in (class-instances 'github-config)
        if (eql id (installation-id github-config))
          do (with-transaction ()
               (setf (installation-id github-config) nil))))

(pushnew 'installation-delete-webhook
          *hooks*)

(defun render-repo-list (access-token)
  (let ((repos (read-repo-list access-token)))
    <simple-card-page>
      <div class= "card-header">
        <h3>Install the Screenshotbot GitHub app</h3>
      </div>

      <div>
        <p>
          In order for Screenshotbot to be able to post build status (or "
          GitHub Checks") to your pull requests, you need to install the app on your repositories.
        </p>

        <p>
          Below we list all the repositories listed on your account.
        </p>

        <ul>
          ,@ (loop for repo in repos collect
                   <li><a href= (format nil "https://github.com/~a" repo)>,(progn repo)</a></li>)
        </ul>
      </div>

      <div class= "card-footer">
        <a href= "/settings/github" class= "btn btn-secondary" >Done</a>
      </div>
    </simple-card-page>))

(defun settings-github-page ()
  (let* ((installation-id (installation-id (github-config (current-company))))
         access-token
         (oauth-link (uiop:call-function
                      ;; TODO: cleanup dependency
                      "screenshotbot/login/github-oauth:make-gh-oauth-link"
                      (uiop:call-function
                       ;; TODO: cleanup dependency
                       "screenshotbot/login/github-oauth:github-oauth-provider")
                      (nibble ()
                        (render-repo-list access-token))
                      :access-token-callback (lambda (token)
                                               (setf access-token token))
                     :scope "user:email")))
    <settings-template>
      <div class= "card mt-3">
        <div class= "card-header">
          <h3>Setup GitHub Checks</h3>
        </div>

        <div class= "card-body">
          <p>In order to enable Build Statuses (called GitHub Checks) you will need to install the Screenshotbot Checks app to your GitHub organization.</p>

          <p>
            This app does <b>not</b> get permissions to access to your repositories, it only needs write access to the Checks API.
          </p>

          <p>
            <a href=oauth-link >Choose repositories</a>
          </p>
        </div>


        <div class= "card-footer">

          <a href= (format nil "https://github.com/apps/~a/installations/new"
                    (app-name (github-plugin)))
             class= (if installation-id "btn btn-secondary" "btn btn-primary") >
            ,(if installation-id
                 "Configure"
                 "Install App on GitHub")
          </a>
        </div>
      </div>
    </settings-template>))

(defsettings settings-github-page
  :name "github"
  :section :vcs
  :title "GitHub"
  :plugin 'github-plugin
  :handler 'settings-github-page)


(defhandler (nil :uri "/github-app-install-callback") (state installation_id setup_action)
  (github-app-installation-callback state installation_id setup_action))
