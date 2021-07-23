(pkg:define-package :util/fiveam
    (:use #:cl
          #:alexandria)
  (:export #:def-suite))


(defun %def (parts)
  (cond
    (parts
     (%def (butlast parts))
     (let ((name (intern (str:join "/" parts)
                         (symbol-package :foo))))
      (or
       (let ((suite (fiveam::get-test name)))
         (when suite
           (check-type suite fiveam::test-suite)
           suite))
       (fiveam:make-suite name
                          :in
                          (when (butlast parts)
                            (intern (str:join "/" (butlast parts))
                                    (symbol-package :foo)))))))))

(defun def-suite-recursive (name)
  (let ((parts (str:split "/" (string name))))
    (%def parts)))

(defmacro def-suite ()
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (let ((suite-name ,(guess-suite-name)))
       (def-suite-recursive suite-name)
       (eval `(fiveam::%in-suite ,suite-name)))))

(defun guess-suite-name ()
  (intern (string (package-name *package*))
          (symbol-package :foo)))
