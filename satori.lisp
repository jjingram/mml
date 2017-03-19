(in-package #:satori)

(defvar *builder*)
(defvar *module*)
(defvar *environments*)

(defun compiler ()
  (llvm:with-objects ((*module* llvm:module "<unknown>")
                      (*builder* llvm:builder))
    (setf *environments* (make-hash-table :test #'equal))
    (llvm:with-objects ((*builder* llvm:builder))
      (let* ((param-types (make-array 0))
             (ftype (llvm:function-type (llvm:int32-type) param-types))
             (main (llvm:add-function *module* "main" ftype))
             (retval (comp '(<integer> 0) nil nil)))
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
                    (llvm:verify-module *module*))))))))
