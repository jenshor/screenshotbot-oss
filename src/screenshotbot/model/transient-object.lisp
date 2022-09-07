(defpackage :screenshotbot/model/transient-object
  (:use #:cl)
  (:import-from #:util/store
                #:with-class-validation)
  (:import-from #:util/object-id
                #:oid-array
                #:object-with-oid)
  (:local-nicknames (#:a #:alexandria))
  (:export
   #:with-transient-copy))
(in-package :screenshotbot/model/transient-object)

(defun remove-index-args (slot-def)
  (let ((args (cdr slot-def)))
    (list*
     (car slot-def)
     (a:remove-from-plist args
                          :index-type
                          :index-initargs
                          :index-reader
                          :index-values
                          :relaxed-object-reference))))

(defmacro with-transient-copy ((transient-class parent-class)
                               &body (class-def . class-def-rest))
  (assert (not class-def-rest))
  (destructuring-bind (keyword class-name parent-classes slot-defs &rest options)
      class-def
   `(progn
      (defclass ,parent-class ()
        ())

      (defclass ,transient-class (,parent-class)
        (,@ (when (member 'object-with-oid parent-classes)
              `((oid :initarg :oid
                     :accessor oid-array)))
         ,@(mapcar #'remove-index-args slot-defs)))

      (with-class-validation
        (,keyword ,class-name (,@parent-classes ,parent-class)
                  ,slot-defs
                  ,@options)))))
