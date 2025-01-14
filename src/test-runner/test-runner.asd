(defsystem :test-runner
  :serial t
  ;; Most of these dependencies are because we need these to be loaded
  ;; before we can load any test deps with
  ;; dspect:*redefinition-action*.
  :depends-on (#-jipr
               :jvm
               :trivial-features
               :log4cl
               :fiveam
               #-(or jipr screenshotbot-oss)
               :sentry
               :graphs
               :str
               :util/misc
               :util/threading
               :tmpdir
               :cl-fad)
  :components ((:file "affected-systems")
               (:file "test-runner")))
