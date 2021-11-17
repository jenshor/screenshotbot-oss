(defpackage :util/emacs
  (:use #:cl)
  (:local-nicknames (#:a #:alexandria))
  (:export
   #:list-packages-for-symbol))
(in-package :util/emacs)

(defun list-packages-for-symbol (name current-package)
  (let ((current-package (if (str:starts-with-p ":" current-package)
                             (str:substring 1 nil current-package)
                             current-package)))
    (log:info "Got package : ~s" current-package)
   (mapcar
    #'package-name
    (sort
     (loop for package in (list-all-packages)
           if (a:when-let (sym (find-symbol (string-upcase name)
                                            package))
                (eql package (symbol-package sym)))
             collect package)
     #'> :key (lambda (package)
                (let ((package-name (package-name package)))
                  (loop for i from 0 below (length current-package)
                        while (and (< i (length package-name))
                                   (char-equal (elt current-package i)
                                               (elt package-name i)))
                        finally
                           (progn
                             (log:info "For ~s, got ~d" package i)
                             (return i)))))))))
