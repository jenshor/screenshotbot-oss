(defpackage :screenshotbot-system
  (:use :cl
   :asdf))

(defclass lib-source-file (c-source-file)
  ())

(defparameter *library-file-dir*
  (make-pathname :name nil :type nil
                 :defaults *load-truename*))

(defun default-foreign-library-type ()
  "Returns string naming default library type for platform"
  #+(or win32 win64 cygwin mswindows windows) "dll"
  #+(or macosx darwin ccl-5.0) "dylib"
  #-(or win32 win64 cygwin mswindows windows macosx darwin ccl-5.0) "so"
)

(defmethod output-files ((o compile-op) (c lib-source-file))
  (let ((library-file-type
          (default-foreign-library-type)))
    (list (make-pathname :name (component-name c)
                         :type library-file-type
                         :defaults *library-file-dir*))))

(defmethod perform ((o load-op) (c lib-source-file))
  t)

(defmethod perform ((o compile-op) (c lib-source-file))
  (uiop:run-program (list "/usr/bin/gcc"
                           "-shared"
                          (namestring
                           (merge-pathnames (format nil "~a.c" (component-name c))
                                            *library-file-dir*))
                          "-I" "/usr/local/include/ImageMagick-7/"
                          "-D" "MAGICKCORE_QUANTUM_DEPTH=8"
                          "-D" "MAGICKCORE_HDRI_ENABLE=0"
                          "-Werror"
                          "-Wall"
                           "-lMagickWand-7.Q8"
                          "-o" (namestring (car (output-files o c))))
                    :output *standard-output*
                    :error-output *error-output*))

(defsystem :screenshotbot
  :serial t
  :author "Arnold Noronha <arnold@screenshotbot.io>"
  :license "Mozilla Public License, v 2.0"
  :depends-on (:util
               :markup
               :gravatar
               (:feature (:not :screenshotbot-oss) :documentation-plugin)
               :cl-store
               :pkg
               #-lispworks
               :util/fake-fli
               :auth
               :jvm
               #-screenshotbot-oss
               :sentry
               :server
               :auto-restart
               :java.libs
               :util/form-state
               :util/hash-lock
               :jose
               :trivial-file-size
               :screenshotbot.js-assets
               :oidc
               :screenshotbot.css-assets
               :screenshotbot/secrets
               :util.java
               :util/phabricator
               :hunchensocket
               :drakma
               :anaphora
               :dag
               #-screenshotbot-oss
               :sentry-client
               :quri
               :clavier
               :cl-cron
               :cl-interpol
               :dns-client
               :random-sample
               :pem
               ;;:cljwt-custom ;; custom comes from clath, for rs-256
               :do-urlencode
               :nibble
               :cl-json)
  :components
  ((:file "injector")
   (:file "ignore-and-log-errors")
   (:file "analytics" :depends-on ("ignore-and-log-errors"))
   (:file "plugin")
   (:file "mailer")
   (:file "magick")
   (lib-source-file "magick-native")
   (:file "magick-lw")
   (:file "installation")
   (:file "server" :depends-on ("analytics"))
   (:file "cdn")
   (:file "google-fonts")
   (:file "user-api")
   (:file "notice-api")
   (:file "api-key-api")
   (:file "report-api")
   (:file "promote-api")
   (:file "screenshot-api")
   (:file "settings-api")
   (:file "task-integration-api")
   (:file "plan")
   (:file "template")
   (:file "left-side-bar")
   (:file "taskie")
   (:module "ui"
    :components ((:file "core")
                 (:file "simple-card-page")
                 (:file "confirmation-page")
                 (:file "all")))
   (:file "artifacts")
   (:file "assets")
   (:file "git-repo")
   (:module "model"
    :serial t
    :components ((:file "core")
                 (:file "company")
                 (:file "user")
                 (:file "invite")
                 (:file "github")
                 (:file "view")
                 (:file "recorder-run")
                 (:file "report" :depends-on ("recorder-run"))
                 (:file "image")
                 (:file "channel")
                 (:file "screenshot")
                 (:file "api-key")
                 (:file "commit-graph")
                 (:file "test-object")
                 (:file "note")
                 (:file "all")))
   (:file "impersonation")
   (:file "diff-report")
   (:module "dashboard"
    :serial t
    :components ((:file "explain")
                 (:file "home")
                 (:file "paginated")
                 (:file "numbers")
                 (:file "run-page")
                 (:file "image")
                 (:file "compare")
                 (:file "notes")
                 (:file "recent-runs")
                 (:file "notices")
                 (:file "new-compare")
                 (:file "api-keys")
                 (:file "channels")
                 (:file "reports")
                 (:file "history")
                 (:file "mask-builder")
                 (:file "site-admin")))
   (:file "invite")
   (:file "image-comparison")
   (:module "github"
    :serial t
    :components ((:file "plugin")
                 (:file "github-installation")
                 (:file "marketplace")
                 (:file "webhook")
                 (:file "jwt-token")
                 (:file "access-checks")
                 (:file "pr-checks" :depends-on ("access-checks"))
                 (:file "pull-request-promoter")
                 (:file "settings")
                 (:file "task-integration")
                 (:file "all")))
   (:module "phabricator"
    :serial t
    :components ((:file "plugin")
                 (:file "commenting-promoter")
                 (:file "diff-promoter")
                 (:file "settings")
                 (:file "all")))
   (:module "gitlab"
    :serial t
    :components ((:file "repo")
                 (:file "plugin")
                 (:file "merge-request-promoter")
                 (:file "all")))
   (:module "api"
    :serial t
    :components ((:file "core")
                 (:file "image")
                 (:file "promote")
                 (:file "recorder-run" :depends-on ("promote"))
                 (:file "commit-graph")))
   (:module "login"
    :serial t
    :components ((:file "common")
                 (:file "oidc")
                 (:file "github-oauth")
                 (:file "github-oauth-ui")
                 (:file "google-oauth")
                 (:file "login")
                 (:file "populate")
                 (:file "signup")
                 (:file "forgot-password")))
   (:module "company"
    :serial t
    :components ((:file "new")
                 (:file "members")))
   #+ (or ccl lispworks)
   (:module "slack"
    :serial t
    :components ((:file "plugin")
                 (:file "core")
                 (:file "task-integration")
                 (:file "settings")
                 (:file "all")))
   (:module "email-tasks"
    :components ((:file "settings")
                 (:file "task-integration")))
   (:module "settings"
    :serial t
    :components ((:file "settings-template")
                 (:file "general")
                 (:file "security")))
   (:module "admin"
    :serial t
    :components ((:file "core")
                 (:file "index")))
   (:module "tasks"
    :serial t
    :components ((:file "common")))
   (:file "config")
   (:file "package")
   (:file "cleanup")))


(defsystem :screenshotbot/tests
  :serial t
  :depends-on (:fiveam
               :util
               :util/fiveam
               :fiveam-matchers
               :screenshotbot/utils
               :screenshotbot/replay
               :tmpdir
               :screenshotbot)
  :components ((:file "testing")
               (:file "factory")
               (:file "test-ignore-and-log-errors")
               (:file "test-server")
               (:file "test-diff-report")
               (:file "test-mailer")
               (:file "test-magick-lw")
               (:file "test-installation")
               (:file "test-assets")
               (:file "test-template")
               (:file "test-taskie")
               (:module "dashboard"
                :components ((:file "test-recent-runs")
                             (:file "test-api-keys")
                             (:file "test-image")
                             (:file "test-channels")
                             (:file "test-history")))
               (:module "login"
                :components ((:file "test-github-oauth")
                             (:file "test-signup")))
               (:module "model"
                :components ((:file "test-screenshot")
                             (:file "test-user")
                             (:file "test-channel")
                             (:file "test-company")
                             (:file "test-image")
                             (:file "test-commit-graph")
                             (:file "test-acceptable")))
               (:module "github"
                :components ((:file "test-jwt-token")
                             (:file "test-plugin")
                             (:file "test-access-checks")
                             (:file "test-pull-request-promoter")
                             (:file "test-webhook")))
               (:module "replay"
                :components ((:file "test-core")))
               #+ (or ccl lispworks)
               (:module "slack"
                :components ((:file "test-settings")))
               (:module "email-tasks"
                :components ((:file "test-task-integration")))
               (:module "api"
                :components ((:file "test-image")
                             (:file "test-promote")
                             (:file "test-send-tasks")
                             (:file "test-recorder-runs")))))

(defsystem :screenshotbot/secrets
  :serial t
  :depends-on (:alexandria
               :pkg)
  :components ((:file "secret")
               (:file "artifacts-secrets")))


(defsystem :screenshotbot/store-tests
  :serial t
  :depends-on (:screenshotbot
               :util/testing
               :fiveam)
  :components ((:file "test-store")))


(defsystem :screenshotbot/utils
  :serial t
  :depends-on (:drakma
               :flexi-streams
               :ironclad
               :screenshotbot/secrets
               :md5
               :log4cl
               :cl-fad
               :alexandria)
  :components ((:file "utils")))

(asdf:defsystem :screenshotbot/replay
  :serial t
  :depends-on (:plump
               :lquery
               :uuid
               :cl-store
               :util/misc
               :util/request
               :cl+ssl
               :auto-restart
               :dexador
               :drakma
               :json-mop
               :alexandria)
  :components ((:module "replay"
                :serial t
                :components ((static-file "replay-regex" :type "txt")
                             (:file "core")
                             (:file "browser-config")))))
