(in-package #:satori)

(defvar *builder*)
(defvar *module*)
(defvar *execution-engine*)

(defun foreign-funcall-ptr (ty main)
  (cond
    (t (let ((ptr (llvm:pointer-to-global *execution-engine* main)))
         (case ty
           (void (progn
                   (if (cffi:pointer-eq main ptr)
                       (llvm:run-function *execution-engine* ptr ())
                       (cffi:foreign-funcall-pointer ptr () :void))
                   nil))
           (i32 (if (cffi:pointer-eq main ptr)
                    (llvm:generic-value-to-int
                     (llvm:run-function *execution-engine* ptr ()) t)
                    (cffi:foreign-funcall-pointer ptr () :int32))))))))

(defun execute (x)
  (llvm:with-objects ((*module* llvm:module "<unknown>")
                      (*builder* llvm:builder)
                      (*execution-engine* llvm:execution-engine *module*))
    (setf *global-environment* nil
          *generics* nil)
    (let* ((inference (infer x '() '()))
           (tenv (second inference))
           (ir1 (third inference))
           (ir2 (flat-closure-convert ir1))
           (retty (or (and (listp x) (eq (first x) 'define) (llvm:void-type))
                      (llvm-type (first inference) tenv)))
           (param-types (make-array 0))
           (ftype (llvm:function-type retty param-types))
           (main (llvm:add-function *module* "" ftype)))
      (llvm:position-builder-at-end *builder*
                                    (llvm:append-basic-block main "entry"))
      (let* ((code (comp-in-main ir2 '() tenv)))
        (if (cffi:pointer-eq retty (llvm:void-type))
            (llvm:build-ret *builder*)
            (llvm:build-ret *builder* code))
        (llvm:verify-module *module*)
        (let* ((result (foreign-funcall-ptr (first inference) main)))
          result)))))

(defun repl ()
  (llvm:with-objects ((*module* llvm:module "<unknown>")
                      (*builder* llvm:builder)
                      (*execution-engine* llvm:execution-engine *module*))
    (setf *global-environment* nil
          *generics* nil)
    (format *error-output* "? ")
    (loop for x = (read *standard-input* nil 'eof nil)
          while (not (equal x 'eof)) do
            (let* ((inference (infer x '() '()))
                   (tenv (second inference))
                   (ir1 (third inference))
                   (ir2 (flat-closure-convert ir1))
                   (retty (llvm-type (first inference) tenv))
                   (param-types (make-array 0))
                   (ftype (llvm:function-type retty param-types))
                   (main (llvm:add-function *module* "" ftype)))
              (llvm:position-builder-at-end *builder*
                                            (llvm:append-basic-block main "entry"))
              (let* ((code (comp-in-main ir2 '() tenv)))
                (if (cffi:pointer-eq retty (llvm:void-type))
                    (llvm:build-ret *builder*)
                    (llvm:build-ret *builder* code))
                (llvm:verify-module *module*)
                (let* ((result (foreign-funcall-ptr (first inference) main)))
                  (format *error-output* "~a~%" result))))
            (format *error-output* "? "))
    (llvm:dump-module *module*)))

(defun compiler ()
  (llvm:with-objects ((*module* llvm:module "<unknown>")
                      (*builder* llvm:builder))
    (setf *global-environment* nil
          *generics* nil)
    (let* ((param-types (make-array 0))
           (ftype (llvm:function-type (llvm:int32-type) param-types))
           (main (llvm:add-function *module* "main" ftype))
           (retval (comp '(i32 0) nil nil)))
      (llvm:position-builder-at-end *builder* (llvm:append-basic-block main "entry"))
      (let ((ret (llvm:build-ret *builder* retval)))
        (loop for x = (read *standard-input* nil 'eof nil)
              while (not (equal x 'eof)) do
                (llvm:position-builder-before *builder* ret)
                (let* ((inference (infer x '() '()))
                       (tenv (second inference))
                       (ir1 (third inference))
                       (ir2 (flat-closure-convert ir1)))
                  (comp-in-main ir2 '() tenv)
                  (llvm:dump-module *module*)
                  (llvm:verify-module *module*)))))))
