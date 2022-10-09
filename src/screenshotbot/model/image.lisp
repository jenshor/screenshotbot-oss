;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(uiop:define-package :screenshotbot/model/image
  (:use #:cl
        #:alexandria
        #:screenshotbot/model/view
        #:screenshotbot/magick
        #:screenshotbot/model/core
        #:screenshotbot/screenshot-api)
  (:import-from #:util
                #:make-url
                #:oid-bytes
                #:oid
                #:object-with-oid)
  (:import-from #:screenshotbot/server
                #:document-root
                #:*root*)
  (:import-from #:screenshotbot/screenshot-api
                #:local-image)
  (:import-from #:screenshotbot/model/company
                #:company
                #:verified-p ;; todo: remove, will cause conflict
                #:image-oid-cache)
  (:import-from #:bknr.datastore
                #:with-transaction
                #:store-object
                #:persistent-class)
  (:import-from #:screenshotbot/magick
                #:ping-image-dimensions
                #:magick
                #:run-magick)
  (:import-from #:bknr.indices
                #:unique-index)
  (:import-from #:bknr.indices
                #:hash-index)
  (:import-from #:util/hash-lock
                #:with-hash-lock-held
                #:hash-lock)
  (:import-from #:bknr.datastore
                #:store-object-id)
  (:import-from #:bknr.datastore
                #:blob-pathname)
  (:import-from #:auto-restart
                #:with-auto-restart)
  (:import-from #:screenshotbot/magick/magick-lw
                #:ping-image-metadata
                #:with-wand)
  (:import-from #:util/object-id
                #:oid-array)
  (:import-from #:util/digests
                #:md5-file)
  (:import-from #:util/store
                #:def-store-local
                #:location-for-oid
                #:with-class-validation)
  (:import-from #:screenshotbot/cdn
                #:make-image-cdn-url)
  (:import-from #:screenshotbot/model/transient-object
                #:cannot-make-transient
                #:make-transient-clone
                #:with-transient-copy)
  (:import-from #:util/misc
                #:?.)
  (:import-from #:screenshotbot/installation
                #:installation
                #:installation-s3-store)
  (:import-from #:screenshotbot/s3/core
                #:s3-store-fetch-remote
                #:s3-store-update-remote)
  ;; classes
  (:export
   #:image
   #:image-blob
   #:mask-rect
   #:local-image)
  ;;methods
  (:export
   #:with-local-image
   #:image=
   #:image-public-url
   #:image-hash
   #:image-blob-get
   #:s3-key
   #:image-blob
   #:verified-p
   #:mask-rect-left
   #:rect-as-list
   #:mask-rect-width
   #:mask-rect-top
   #:mask-rect-height)
  (:export
   #:draw-rects-in-place
   #:draw-masks-in-place
   #:image-dimensions
   #:dimension
   #:dimension-height
   #:dimension-width
   #:image-format
   #:ping-image-dimensions
   #:find-image
   #:make-image
   #:image-filesystem-pathname
   #:update-image
   #:mask=
   #:image-metadata))
(in-package :screenshotbot/model/image)

(hex:declare-handler 'image-blob-get)

(defvar *image-creation-hooks*
  nil)

#+screenshotbot-oss
(with-class-validation
  (defclass image-blob (bknr.datastore:blob)
    ()
    (:metaclass persistent-class)))

(defparameter +image-state-filesystem+ 1
  "Image is saved on the local filesystem")

;; Some of these slots are limited to screenshotbot-oss. This is for
;; backward compatibility in the OSS version, where we don't have a
;; schema migration process.
(with-transient-copy (transient-image abstract-image)
  (defclass image (object-with-oid)
    (#+screenshotbot-oss
     (link :initarg :link)
     (hash :initarg :hash
           :reader image-hash ;; NOTE: Returns a vector!
           :index-type hash-index
           :index-initargs (:test 'equalp)
           :index-reader images-for-original-hash)
     (state :initarg :state
            :initform nil
            :accessor %image-state
            :documentation "The state of the image. We use integers
           because they're cheaper to parse in bknr.datastore, and
           image objects are the largest number of objects in the
           store.")
     #+screenshotbot-oss
     (blob
      :initarg :blob
      :relaxed-object-reference t
      :accessor %image-blob ;; don't access directly!
      :initform nil)
     (company
      :initarg :company
      :accessor company
      :initform nil)
     (verified-p
      :accessor verified-p
      :initform nil
      :initarg :verified-p
      :documentation "If we have verified that this image was uploaded")
     #+screenshotbot-oss
     (content-type :initarg :content-type
                   :reader image-content-type))
    (:metaclass persistent-class)))

#|

(loop for im in (bknr.datastore:class-instances 's3-blob)

       do (bknr.datastore:delete-object im))
|#

(defmethod make-transient-clone ((image image))
  (make-instance 'transient-image
                 :oid (oid-array image)
                 :hash (image-hash image)
                 :state (%image-state image)
                 :company (?. oid (company image))
                 :verified-p (verified-p image)))

(defmethod find-image ((company company) (hash string))
  (loop for image in (append
                      (images-for-original-hash hash)
                      (images-for-original-hash (ironclad:hex-string-to-byte-array hash)))
        if (and
            (eql (company image) company)
            (verified-p image))
          return image))

(defmethod find-image ((company company) (hash array))
  (find-image company
              (ironclad:byte-array-to-hex-string hash)))

(defmethod print-object ((self image) stream)
  (format stream "#<IMAGE ~a>" (store-object-id self)))

(with-transient-copy (transient-mask-rect abstract-mask-rect)
  (defclass mask-rect (store-object)
    ((top :initarg :top
          :accessor mask-rect-top)
     (left :initarg :left
           :accessor mask-rect-left)
     (height :initarg :height
             :accessor mask-rect-height)
     (width :initarg :width
            :accessor mask-rect-width))
    (:metaclass persistent-class)))

(defmethod mask= ((a abstract-mask-rect) (b abstract-mask-rect))
  (or
   (eql a b)
   (every #'identity
    (loop for fn in (list #'mask-rect-top
                          #'mask-rect-left
                          #'mask-rect-height
                          #'mask-rect-width)
          collect
          (eql
           (funcall fn a)
           (funcall fn b))))))

(defmethod make-transient-clone ((self mask-rect))
  (make-instance 'transient-mask-rect
                 :top (mask-rect-top self)
                 :left (mask-rect-left self)
                 :height (mask-rect-height self)
                 :width (mask-rect-width self)))

(defmethod rect-as-list ((rect mask-rect))
  (with-slots (top left height width) rect
    (list top left height width)))

(defmethod image-filesystem-pathname ((image abstract-image))
  "If the image is stored on the current file system, return the
  pathname to the image. If it's stored remotely, raise an error!"
  (cond
    ((eql +image-state-filesystem+ (%image-state image))
     (local-location-for-oid (oid-array image)))
    #+screenshotbot-oss
    ((%image-blob image)
     (bknr.datastore:blob-pathname (%image-blob image)))
    (t
     ;; the file most likely does not exist at this point, but this is
     ;; what you're asking for!
     (local-location-for-oid (oid-array image)))))

(defmethod image-not-uploaded-yet-p ((image image))
  (and
   (eql nil (%image-state image))))

(defmethod image-not-uploaded-yet-p ((image transient-image))
  nil)

(defclass local-image (image)
  ((url :initarg :url
        :accessor local-image-url))
  (:metaclass persistent-class)
  (:documentation "An IMAGE, that's used only for testing purposes locally"))

(defmethod %with-local-image ((image abstract-image) fn)
  (cond
    ((image-not-uploaded-yet-p image)
     (error "no image uploaded yet for ~a" image))
    (t
     (multiple-value-bind (file key) (image-filesystem-pathname image)
       (cond
         ((path:-e file)
          (funcall fn file))
         (t
          (s3-store-fetch-remote
           (installation-s3-store
            (installation))
           file
           key)
          (funcall fn file)))))))

;; todo: remove
(defmethod %with-local-image ((image image) fn)
  (call-next-method))

(defmethod %with-local-image ((image local-image) fn)
  ;; this could be bad if users have a way of creating local-images,
  ;; but they don't. It's always created in code for demo
  ;; purposes. (TODO: We should remove that logic, and use real images
  ;; instead).
  (funcall fn (asdf:system-relative-pathname
               :screenshotbot
               (format nil "static~a" (local-image-url image)))))

(defmacro with-local-image ((file screenshot) &body body)
  `(flet ((body (,file) ,@body))
     (%with-local-image ,screenshot #'body)))

(defun %draw-mask-rect-commands (masks &key color)
  "Imagemagick commands to draw rectangles for the given masks"
  `("-fill" ,color
    "-stroke" ,color
    ,@ (loop for mask in masks
             appending
             (list "-draw" (format nil "rectangle ~d,~d ~d,~d"
                                   (mask-rect-left mask)
                                   (mask-rect-top mask)
                                   (+
                                    (mask-rect-left mask)
                                    (mask-rect-width mask))
                                   (+
                                    (mask-rect-top mask)
                                    (mask-rect-height mask)))))))

(defun draw-masks-in-place (image-file masks &key color)
  (when masks
    (uiop:with-temporary-file (:pathname tmp
                               :directory (cl-fad:pathname-directory-pathname image-file))
      (run-magick `("convert"
                          ,(namestring image-file)
                          ,@(%draw-mask-rect-commands masks :color color)
                          ,(namestring tmp)))
      (uiop:rename-file-overwriting-target
       tmp image-file))))


(defun draw-masks (wand masks)
  (assert (not masks)))

(defun px-in-mask-p (i j mask)
  (declare (optimize (speed 3) (safety 0))
           (type fixnum i j))
  (and
   (<= (mask-rect-top mask)
       i
       (+ (mask-rect-top mask) (mask-rect-height mask) -1))
   (<= (mask-rect-left mask)
       j
       (+ (mask-rect-left mask) (mask-rect-width mask) -1))))

(defclass image-stream ()
  ((width :initarg :width
          :reader width)
   (height :initarg :height
           :reader height)
   (pos-x :initform 0
          :accessor pos-x)
   (pos-y :initform 0
          :accessor pos-y)))

(defclass image-stream-expanded-canvas (image-stream)
  ((delegate :initarg :delegate
             :reader delegate)))

(defmethod has-more-pixels-p ((self image-stream))
  (< (pos-y self)
     (height self)))

(defmethod next-pos ((self image-stream))
  (unless (has-more-pixels-p self)
    (error "Out of bounds for image"))
  (let ((old-x (pos-x self))
        (old-y (pos-y self)))
    (incf (pos-x self))
    (when (>= (pos-x self) (width self))
      (setf (pos-x self) 0)
      (incf (pos-y self)))
    (values old-y old-x)))

(defclass image-array-stream (image-stream)
  ((arr :initarg :arr
        :reader arr)
   (buffer :initarg :buffer
           :reader buffer)))

(defclass image-magick-stream (image-stream)
  ((%stream :accessor %stream)
   (file :initarg :file)
   (buffer :initform (make-array 4 :element-type '(unsigned-byte 8))
           :reader buffer)))

(defmethod initialize-instance :around ((self image-array-stream) &key arr)
  (let ((dims (array-dimensions arr)))
    (call-next-method
     self
     :arr arr
     :width (cadr dims)
     :height (car dims)
     :buffer (make-array (caddr dims)))))

(defmethod read-next-pixel ((image image-array-stream))
  (multiple-value-bind (pos-y pos-x) (next-pos image)
    (let ((buffer (buffer image)))
     (dotimes (j (length buffer))
       (setf (aref buffer j)
             (aref (arr image) pos-y pos-x j)))
      buffer)))

(defmethod read-next-pixel ((image image-stream-expanded-canvas))
  (multiple-value-bind (pos-y pos-x) (next-pos image)
    (let ((delegate (delegate image)))
     (cond
       ((or
         (>= pos-x (width delegate))
         (>= pos-y (height delegate)))
        ;; bad pixel!
        (dotimes (j (length (buffer delegate)))
          (setf (aref (buffer delegate) j) 0))
        (buffer delegate))
       (t
        (read-next-pixel delegate))))))

(defmethod initialize-instance :after ((self image-magick-stream) &key file &allow-other-keys)
  (setf (%stream self)
        (run-magick (list
                     "stream" "-map" "rgba"
                     "-storage-type" "char"
                     file
                     "-")
                    :async t)))

(defmethod cleanup-image-stream ((self image-magick-stream))
  (close (%stream self)))

(defmethod read-next-pixel ((self image-magick-stream))
  ;; we don't need the actual return value here
  (next-pos self)
  (read-sequence (buffer self) (%stream self))
  (buffer self))

(defun map-unequal-pixels-stream (stream1 stream2 fn &key masks)
  "Map unequal pixels assuming both streams refer to images with the same dimensions"
  (loop while (has-more-pixels-p stream1)
        for i = (pos-y stream1)
        for j = (pos-x stream1)
        for pix1 = (read-next-pixel stream1)
        for pix2 = (read-next-pixel stream2)
        if (not (equalp pix1 pix2))
          do
             ;; inefficient way to check if pixel is masked
             (loop for mask in masks
                   if (px-in-mask-p i j mask)
                     do (return nil)
                   finally
                      (funcall fn i j))))

(defun map-unequal-pixels-arr (arr1 arr2 fn &key masks)
  (let* ((dim1 (array-dimensions arr1))
         (dim2 (array-dimensions arr2))
         (height (max (car dim1) (car dim2)))
         (width (max (cadr dim1) (cadr dim2))))

    (flet ((make-expanded (x)
             (make-instance 'image-stream-expanded-canvas
                             :delegate x
                             :width width
                             :height height)))
     (map-unequal-pixels-stream
      (make-expanded
       (make-instance 'image-array-stream
                       :arr arr1))
      (make-expanded
       (make-instance 'image-array-stream
                       :arr arr2))
      fn
      :masks masks))))

(defun map-unequal-pixels (img1 img2 fn &key masks)
  (restart-case
      (with-local-image (file1 img1)
        (with-local-image (file2 img2)
          (map-unequal-pixels-on-file file1 file2 fn :masks masks)))
    (retry-map-unequal-pixels ()
      (map-unequal-pixels img1 img2 fn :masks masks))))

(defun map-unequal-pixels-on-file (file1 file2 fn &key masks)
  (flet ((make-image-stream (file)
           (let ((dim (image-file-dimensions  file1)))
             (make-instance 'image-magick-stream
                             :file file
                             :width (dimension-width dim)
                             :height (dimension-height dim)))))
    (let ((stream1 (make-image-stream file1))
          (stream2 (make-image-stream file2)))
      (unwind-protect
           (map-unequal-pixels-stream
            stream1
            stream2
            fn :masks masks)
        (cleanup-image-stream stream1)
        (cleanup-image-stream stream2)))))

#+screenshotbot-oss
(defmethod maybe-rewrite-image-blob ((image image))
  (restart-case
      (alexandria:when-let ((blob (%image-blob image)))
        (let ((dest (local-location-for-oid (oid-array image)))
              (src (blob-pathname blob)))
          (when (path:-e src)
            (assert (osicat-posix:link
                     src dest)))
          (log:info "Rewriting blob for ~s: ~s" image blob)
          (with-transaction ()
            (setf (%image-blob image) nil)
            (setf (%image-state image) +image-state-filesystem+))))
    (ignore-image ()
      nil)))

#+screenshotbot-oss
(defun rewrite-all-image-blobs ()
  (loop for image in (reverse (bknr.datastore:class-instances 'image))
        do
        (maybe-rewrite-image-blob image)))



(defun local-location-for-oid (oid)
  "Figure out the local location for the given OID"
  (location-for-oid
   #P"image-blobs/"
   oid))

(defun metadata-location-for-oid (oid)
  (location-for-oid
   #P "cl-store/image-metadata/"
   oid))

(defun make-image (&rest args &key hash blob pathname
                   for-tests &allow-other-keys)
  (when blob
    (error "don't specify blob"))
  (unless (or hash pathname)
    (error "Must provide at least one of hash or pathname"))
  (let* ((args (alexandria:remove-from-plist args :pathname :for-tests))
         (oid (mongoid:oid))
         (hash (cond
                 ((stringp hash)
                  (ironclad:hex-string-to-byte-array hash))
                 (t
                  hash))))
    (multiple-value-bind (image-file s3-key) (local-location-for-oid oid)
      ;; TODO: copy-overwriting-target could be a lot more efficient in
      ;; many cases.
      (when pathname
        (assert (path:-e pathname))
        (uiop:copy-file pathname image-file)
        (unless for-tests ;; todo: refactor better
         (s3-store-update-remote
          (installation-s3-store (installation))
          image-file
          s3-key)))

      (apply #'make-instance 'image
               :oid oid
               :state (cond
                        (pathname
                         +image-state-filesystem+))
               :hash (cond
                       (hash hash)
                       (pathname
                        (md5-file image-file))
                       (t (error "must provide hash or pathname")))
               args))))

(defmethod update-image ((image image) &key pathname)
  (assert pathname)
  (with-transaction ()
    (setf (%image-state image)
          +image-state-filesystem+))
  (multiple-value-bind (dest key) (image-filesystem-pathname image)
    (uiop:copy-file pathname dest)
    (when key
      (s3-store-update-remote
       (installation-s3-store
        (installation))
       dest
       key))
    dest))

(with-class-validation
  (defclass content-equal-result (store-object)
    ((image-1 :initarg :image-1
              :index-type hash-index
              :index-reader content-equal-results-for-image-1)
     (image-2 :initarg :image-2
              :reader image-2)
     (masks :initarg :masks
            :reader masks)
     (result :initarg :result
             :reader result))
    (:metaclass persistent-class)
    (:documentation "Comparing two images by content can be slow. This
  caches the result of such comparisons.")))

(defun clear-content-equal-results ()
  (mapc #'bknr.datastore:delete-object
          (bknr.datastore:store-objects-with-class 'content-equal-result)))

(defvar *content-equal-hash-lock* (make-instance 'hash-lock))

(define-condition slow-image-comparison ()
  ())

(defun images-equal-by-magick (img1 img2)
  "Use ImageMagick to check if the two images have identical contents"
  (log:info "Comparing images with magick: ~a ~a" img1 img2)
  (with-local-image (file1 img1)
    (with-local-image (file2 img2)
      (compare-image-files (magick) file1 file2))))

(defun images-equal-by-content-p (img1 img2 &key masks)
  (with-hash-lock-held (img1 *content-equal-hash-lock*)
    (let ((existing-results (content-equal-results-for-image-1 img1)))
      (log:info "existing results: ~S" existing-results)
      (loop for result in existing-results
            if (and (eql img2 (image-2 result))
                    (equal masks (masks result)))
              do (return (result result))
            finally
               (return
                 (flet ((save-result (result)
                          (make-instance 'content-equal-result
                                          :image-1 img1
                                          :image-2 img2
                                          :masks masks
                                          :result result)
                          result))
                   (save-result
                    (cond
                      ((null masks)
                       (images-equal-by-magick img1 img2))
                      (t
                       (let ((resp t))
                         (log:info "[slow-path] checking images ~s, ~s with masks ~s" img1 img2 masks)
                         (signal 'slow-image-comparison)
                         (map-unequal-pixels img1 img2
                                             (lambda (i j)
                                               (declare (optimize (speed 3)
                                                                  (safety 0)))
                                               (declare (ignore i j))
                                               (Setf resp nil))
                                             :masks masks)
                         resp))))))))))

(defun image= (img1 img2 masks)
  "Check if the two images have the same contents. Looks at both file
  hash and image contents"
  (assert (image-hash img1))
  (assert (image-hash img2))
  (or
   (equalp (image-hash img1)
           (image-hash img2))
   ;; if the hash's don't match, check the perceptual hash. This is
   ;; slow, so make sure we're only doing this if absolutely required
   (when (or masks
             ;; A clever hack for allowing us to migrate from PNG to
             ;; WEBP without the user ever noticing. As long as the
             ;; PNG and the WEBP images are both lossless, they should
             ;; result in identical images.
             #+nil
             (not (string= (image-format img1)
                           (image-format img2))))
     (images-equal-by-content-p img1 img2 :masks masks))))

(defmethod image-hash ((image local-image))
  ;; this is probably only used for tests... hopefully doesn't hit in
  ;; prod.
  (with-local-image (im image)
    (md5-file im)))

(defmethod image-public-url ((image abstract-image) &key size type)
  (let ((url
         (let ((args nil))
           (when size
             (setf args `(:size ,(string-downcase size))))
           (when type
             (setf args (list* :type (str:downcase type) args)))
           (apply #'make-url 'image-blob-get :oid (encrypt:encrypt-mongoid (oid-array image))
                    args))))
    (cond
      (type
       (make-image-cdn-url url))
      (t
       ;; the image endpoint needs to guess the type based on Accept:
       ;; headers. So we don't cache this for now.
       url))))

(defmethod image-public-url ((image image) &key size type)
  (call-next-method))

(defmethod image-local-url ((image image))
  (image-public-url image))

(defmethod image-public-url ((image local-image) &key size)
  (hex:make-full-url
   hunchentoot:*request*
   (local-image-url image)))

(defmethod can-view ((image image) user)
  (is-user-id-same image user))

(defclass metadata ()
  ((image-format :initarg :image-format
                 :reader metadata-image-format)
   (dimensions :initarg :dimensions
               :reader metadata-image-dimensions)))

(defclass dimension ()
  ((height :initarg :height
           :reader dimension-height)
   (width :initarg :width
          :reader dimension-width)))

(def-store-local *metadata-cache* (make-hash-table))

(defmethod image-metadata ((image abstract-image))
  (util:or-setf
   (gethash image *metadata-cache*)
   (with-local-image (file image)
     (destructuring-bind (width height type)
         (ping-image-metadata (magick) file)
       (assert (member type '("WEBP" "PNG" "JPEG")
                       :test #'string=))
       (make-instance 'metadata
                      :image-format (intern type "KEYWORD")
                      :dimensions
                      (make-instance 'dimension
                                     :height height
                                     :width width))))))

(defmethod invalidate-image-metadata ((image abstract-image))
  (remhash image *metadata-cache*))

(defmethod image-dimensions (image)
  (metadata-image-dimensions (image-metadata image)))

(defun image-file-dimensions (file)
  (destructuring-bind (width height) (ping-image-dimensions (magick) file)
      (make-instance 'dimension
                      :width width
                      :height height)))

(defun image-format (image)
  "Get the image format of the file. This looks at the magic in the
file content to determine the file type, not the pathname's
type. Example output could be either :PNG or :WEBP. If we can't
recognized the file, we'll return nil."
  (metadata-image-format (image-metadata image)))

(defun convert-all-images-to-webp ()
  "Converts all the images to lossless webp, while maintaining the
  original hashes. This way, any jobs referencing the old hashes will
  still not send a new image, and we can recover a lot of disk
  space."
  (loop for image in (reverse (bknr.datastore:store-objects-with-class 'image))
        for i from 0
        do
           (log:info "Converting image: ~a / ~a" i image)
           (restart-case
               (convert-image-to-webp image)
             (ignore-image ()
               (values)))))

(with-auto-restart ()
  (defun convert-image-to-webp (image)
   (let ((+limit+ 16383))
     (when (and
            (uiop:file-exists-p (image-filesystem-pathname image))
            (eql :png (image-format image))
            (let ((dim (image-dimensions image)))
              (and (< (dimension-height dim) +limit+)
                   (< (dimension-width dim) +limit+))))
       (flet ((%rename-file (from to)
                (log:info "Renaming file from ~a to ~a" from to)
                (rename-file from to)))
         (let ((path (make-pathname :type :unspecific
                                    :defaults (image-filesystem-pathname image))))
           (log:info "will switch image: ~a" path)
           (let ((tmp (make-pathname :type "webp"
                                     :defaults path))
                 (png (make-pathname :type "png"
                                     :defaults path)))
             (sleep 1)
             (invalidate-image-metadata image)
             (convert-to-lossless-webp
              (magick)
              path tmp)
             (invalidate-image-metadata image)
             (uiop:rename-file-overwriting-target tmp path)
             (assert (uiop:file-exists-p path)))))))))

(defun ensure-images-have-hash ()
  "Used as a migration to fix an issue with images having no hash"
  (let ((images (reverse
                 (loop for image in (bknr.datastore:store-objects-with-class 'image)
                       unless (image-hash image)
                         collect image))))
    (loop for image in images
          do
             (log:info "looking at: ~a" image)
             (with-local-image (file image)
               (let ((hash (md5-file file)))
                 (log:info "Got hash: ~a" hash)
                 (with-transaction ()
                   (setf (slot-value image 'hash) hash))
                 hash)))))
