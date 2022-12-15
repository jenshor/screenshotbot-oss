;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(defpackage :screenshotbot/magick/test-magick-lw
  (:use #:cl
        #:fiveam
        #:fiveam-matchers)
  (:import-from #:screenshotbot/magick/magick-lw
                #:magick-new-image
                #:with-pixel-wand
                #:compare-wands
                #:magick-set-size
                #:verify-magick
                #:load-magick-native
                #:screenshotbot-verify-magick
                #:with-image-comparison
                #:ping-image-metadata
                #:map-non-alpha-pixels
                #:magick-exception-message
                #:magick-read-image
                #:new-magick-wand
                #:magick-exception
                #:with-wand
                #:check-boolean
                #:compare-images
                #:magick-native)
  (:import-from #:screenshotbot/magick/magick
                #:convert-to-lossless-webp)
  (:import-from #:util/digests
                #:md5-file)
  (:import-from #:fiveam-matchers/described-as
                #:described-as)
  (:import-from #:easy-macros
                #:def-easy-macro)
   (:local-nicknames (#:a #:alexandria)))
(in-package :screenshotbot/magick/test-magick-lw)


(util/fiveam:def-suite)

(def-fixture state ()
  (tmpdir:with-tmpdir (tmpdir)
    (let ((rose (asdf:system-relative-pathname :screenshotbot.magick "../fixture/rose.png"))
          (rose-webp (asdf:system-relative-pathname :screenshotbot.magick "../fixture/rose.webp"))
          (wizard (asdf:system-relative-pathname :screenshotbot.magick "../fixture/wizard.png"))
          (transparent (asdf:system-relative-pathname :screenshotbot.magick "../fixture/point.png")))
      (&body))))

(test simple-file-load-save
  (with-fixture state ()
   (with-wand (wand :file rose)
     (pass))))

(test compare-nil
  (with-fixture state ()
    (with-wand (wand1 :file rose)
      (with-wand (wand2 :file wizard)
        (is-false (compare-images wand1 wand2))))))

(test compare-is-true
  (with-fixture state ()
    (with-wand (wand1 :file rose)
      (with-wand (wand2 :file rose-webp)
        (is-true (compare-images wand1 wand2))))))

(test convert-to-webp
  (with-fixture state ()
    (uiop:with-temporary-file (:pathname out :type "webp")
      (convert-to-lossless-webp
       (make-instance 'magick-native)
       rose out)
      (with-wand (rose1 :file rose)
        (with-wand (out1 :file out)
          (is-true (compare-images rose1 out1)))))))

(test ensure-convert-to-webp-is-deterministic
  (with-fixture state ()
    (uiop:with-temporary-file (:pathname out :type "webp")
      (convert-to-lossless-webp (make-instance 'magick-native)
                                rose out)
      (uiop:with-temporary-file (:pathname out2 :type "webp")
        (convert-to-lossless-webp (make-instance 'magick-native)
                                  rose out2)
        (is (equalp (md5-file out)
                    (md5-file out2)))))))

(test raises-magick-exception
  (with-fixture state ()
    (uiop:with-temporary-file (:pathname p)
      (with-wand (wand)
        (handler-case
            (let ((code (magick-read-image wand (namestring p))))
              (check-boolean code wand)
              (fail "Excepted exception"))
          (magick-exception (e)
            (is (str:containsp "decode delegate for"
                               (magick-exception-message e)))))))))


(test raises-magick-exception-message-is-not-corrupted
  ;; Just ensuring that magick-relinquish-memory is the right thing to
  ;; do.
  (with-fixture state ()
    (uiop:with-temporary-file (:pathname p)
      (with-wand (wand)
        (let ((messages
                (loop for x from 0 to 100
                      collect
                      (handler-case
                          (let ((code (magick-read-image wand (namestring p))))
                            (check-boolean code wand)
                            (fail "Excepted exception"))
                        (magick-exception (e)
                          (magick-exception-message e))))))
          (assert-that messages
                       (every-item
                        (starts-with "no decode delegate for"))))))))

(test find-first-non-transparent
  (handler-bind ((error (lambda (E)
                          (trivial-backtrace:print-backtrace e))))
   (with-fixture state ()
     (let ((transparent-pixel-for-null
             (block top
               (with-wand (wand :file transparent)
                 (map-non-alpha-pixels wand
                                       (lambda (i j)
                                         (return-from top (cons i j))))))))
       (is
        (equal (cons 20 30)
               transparent-pixel-for-null)))
     (is
      (equal (cons 0 0)
             (block top
               (with-wand (wand :file rose)
                 (map-non-alpha-pixels wand
                                       (lambda (i j)
                                         (return-from top (cons i j)))))))))))
(test ping-image-metadata
  (with-fixture state ()
    (is (equal '(70 46 "PNG")
               (ping-image-metadata (make-instance 'magick-native)
                                    rose)))
    (is (equal '(70 46 "WEBP")
               (ping-image-metadata (make-instance 'magick-native)
                                    rose-webp)))))

(test no-background-in-compare
  (with-fixture state ()
    (with-wand (one :file rose)
      (with-wand (two :file rose)
        (with-image-comparison (one two :result result :same-p same-p)
          (is-true same-p)
          (let ((non-alphas 0))
            (map-non-alpha-pixels result
                                  (lambda (x y)
                                    (incf non-alphas)))
            (assert-that non-alphas
                         (described-as "We shouldn't have a background image in the comparison"
                           (equal-to 0)))))))))

(test verify-magick-native
  (load-magick-native)
  (with-fixture state ()
    (finishes
      (verify-magick))))

(test force-reload-magick-native
  (load-magick-native)
  (finishes
   (load-magick-native :force t)))

;; Dummy test to look at the test output in builds to see which
;; version of magick is being used.
(test #+magick-6 using-magick-6 #+magick-7 using-magick7
  (pass))

(def-easy-macro with-large-wand (&binding wand &key (height 16385)  &fn fn)
  (with-wand (wand)
    (with-pixel-wand (pwand)
      (check-boolean
       (magick-new-image wand
                         1 height
                         pwand)
       wand))
    (funcall fn wand)))

#-screenshotbot-oss
(test large-image
  "If this test fails, definitely look at the global policy.xml for the
 given ImageMagick version. Currently, we can't override the
 resource:height policy, which by default is set to 16KP, at least on
 ImageMagick 6. On IM7, it appears to be set to 300KP, which I'm not
 sure if I changed myself in my local instance. On the docker
 instances it doesn't look like the height policy is set, and I'm too
 lazy to figure out what the default is. "
  (with-large-wand (before)
    (with-large-wand (after)
      (uiop:with-temporary-file (:pathname output :type "webp")
        ;; This does not work in Magick-6. I don't know why. Ideally
        ;; I'd like to make it work, but for now I'll just disable
        ;; this test. Essentially, expect compare-wands to fail on
        ;; large images in magic-6.
        (finishes
         (compare-wands before after output))))))

(test small-image-comparison-happy-path
  (with-large-wand (before :height 20)
    (with-large-wand (after :height 20)
      (uiop:with-temporary-file (:pathname output :type "webp")
        (finishes
         (compare-wands before after output))))))
