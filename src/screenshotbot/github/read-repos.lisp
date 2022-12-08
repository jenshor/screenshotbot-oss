(defpackage :screenshotbot/github/read-repos
  (:use #:cl)
  #+ (or ccl lispworks)
  (:import-from #:util/java
                #:java-syntax
                #:read-java-field
                #:java-list->list
                #:new-instance)
  (:import-from #:screenshotbot/github/access-checks
                #:github-api-request
                #:get-repo-id
                #:github-user-service
                #:github-repo-id
                #:github-client)
  (:import-from #:oidc/oidc
                #:access-token-str)
  #+ (or ccl lispworks)
  (:import-from #:util/java/java
                #:*bfalse*
                #:*btrue*
                #:java-equals)
  (:import-from #:screenshotbot/audit-log
                #:with-audit-log)
  (:import-from #:screenshotbot/github/audit-log
                #:check-collaborator)
  (:import-from #:screenshotbot/user-api
                #:current-company)
  (:local-nicknames (#:a #:alexandria))
  (:export
   #:read-repo-list
   #:can-edit-repo))
(in-package :screenshotbot/github/read-repos)

#+ (or ccl lispworks)
(named-readtables:in-readtable java-syntax)

(defun can-edit-repo (access-token repo
                      &key user company)
  #- (or ccl lispworks)
  t
  #+ (or ccl lispworks)
  (let* ((client (github-client :oauth-token
                                (access-token-str access-token)))
         (user-service (github-user-service client))
         (handle (#_getLogin (#_getUser user-service))))

    (with-audit-log (log (make-instance 'check-collaborator :login handle
                                                            :user user
                                                            :company company
                                                            :repo repo))
      (declare (ignore log))
      (multiple-value-bind (response ret)
          (github-api-request (format nil "/repos/~a/collaborators/~a"
                                      (get-repo-id repo)
                                      handle)
                              :access-token access-token)
        (unless (= ret 204)
          (warn "not a collaborator: ~a" response))
        (values
         (= ret 204)
         (a:assoc-value response :message))))))
