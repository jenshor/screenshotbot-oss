;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/dashboard/api-keys
  (:use #:cl
        #:alexandria
        #:nibble
        #:screenshotbot/user-api
        #:screenshotbot/api-key-api)
  (:import-from #:screenshotbot/server
                #:defhandler)
  (:import-from #:screenshotbot/template
                #:mdi
                #:dashboard-template)
  (:import-from #:screenshotbot/ui
                #:confirmation-page)
  (:import-from #:core/ui/simple-card-page
                #:simple-card-page)
  (:import-from #:screenshotbot/server
                #:with-login)
  (:import-from #:screenshotbot/taskie
                #:taskie-row
                #:taskie-page-title
                #:taskie-list)
  (:import-from #:screenshotbot/model/api-key
                #:api-key-description)
  (:import-from #:easy-macros
                #:def-easy-macro))
(in-package :screenshotbot/dashboard/api-keys)

(markup:enable-reader)

(def-easy-macro with-description (&binding final-description &key description (action "Create Key") &fn fn)
  <simple-card-page form-action= (nibble (description) (fn description)) >
    <div class= "card-header">
      <h3>Describe this key</h3>
    </div>

      <label class= "form-label" for= "#description">
        This human-readable description let's you distinguish keys on the API keys dashboard.
      </label>
      <textarea name= "description" class= "form-control" placeholder= "Enter text here" id= "description" >,(progn description)</textarea>

    <div class= "card-footer">
      <input type= "submit" class= "btn btn-primary" value= action />
      <a href= "/api-keys" class= "btn btn-secondary" >Cancel</a>
    </div>
  </simple-card-page>)

(defun %create-api-key (user company)
  (with-description (description)
   (let ((api-key (make-instance 'api-key
                                 :user user
                                 :description description
                                 :company company)))
     <simple-card-page max-width= "80em" >
     <div class= "card-header">
     <h3>New API Key</h3>
     </div>
     <p>Please copy paste the API secret, you won't have access to it again. But you will be able to create new API keys as needed.</p>

     <div>
     <b>API Key</b>: ,(api-key-key api-key)<br />
     <b>API Secret</b>: ,(api-key-secret-key api-key)
     </div>

     <div class= "card-footer">
     <a href= "/api-keys">Go back</a>
     </div>

     </simple-card-page>)))

(defun %confirm-delete (api-key)
  (confirmation-page
   :yes (nibble ()
          (delete-api-key api-key)
          (hex:safe-redirect "/api-keys"))
   :no (nibble ()
         (hex:safe-redirect "/api-keys"))
   <p>Are you sure you want to delete API Key ,(api-key-key api-key)</p>))

(defun edit-api-key (api-key)
  (with-description (description :description (api-key-description api-key)
                     :action "Update description")
    (setf (api-key-description api-key) description)
    (hex:safe-redirect "/api-keys")))

(defun %api-key-page (&key (user (current-user))
                        (company (current-company))
                        (script-name "/api-keys"))
  (declare (ignore script-name))
  (let* ((api-keys (user-api-keys user company))
         (create-api-key (nibble ()
                           (%create-api-key user company))))
    <dashboard-template title= "Screenshotbot: API Keys" >
      <taskie-page-title title="API keys" >
            <form method= "post">
              <input type= "submit" formaction=create-api-key formmethod= "post"
                     class= "btn btn-success btn-sm" value= "New API Key" />
            </form>
      </taskie-page-title>

      ,(taskie-list
        :items api-keys
        :headers (list "API Key" "Secret" "Description" "Actions")
        :empty-message "You haven't created an API Key yet"
        :checkboxes nil
        :row-generator (lambda (api-key)
                         (let* ((coded-secret (format nil
                                                      "~a~a"
                                                      (str:repeat 36 "*")
                                                      (str:substring  36 nil (api-key-secret-key api-key))))
                                (delete-api-key (nibble ()
                                                  (%confirm-delete api-key))))

                           <taskie-row>
                             <span class= "" >,(api-key-key api-key)</span>
                             <span>,(progn coded-secret)</span>
                               <span class= "d-inline-block text-truncate" style= "max-width: 20em" title= (api-key-description api-key) >
                                 ,(or (api-key-description api-key) "")
                                </span>

                             <span>
                               <a href= (nibble () (edit-api-key api-key)) >
                                 <mdi name= "edit" />
                               </a>
                               <form style="display:inline-block" class= "ml-4" method= "post" >
                                 <button type= "submit" formaction=delete-api-key
                                        formmethod= "post"
                                        class= "btn btn-link"
                                        value= "Delete" >
                                   <mdi name="delete" class= "text-danger" />
                                 </button>
                               </form>
                             </span>
                           </taskie-row>)))
    </dashboard-template>))

(defhandler (api-keys :uri "/api-keys") ()
  (with-login ()
   (%api-key-page)))
