;; See: http://matt.might.net/articles/closure-conversion/

(in-package #:satori)

(defun closure-convert (x)
  (cond
    ((symbolp x) x)
    ((integerp x) x)
    ((case (first x)
       (lambda (let* ((params (second x))
                      (body (rest (rest x)))
                      (id (gensym))
                      (params* (cons id params))
                      (fv (sort-symbols< (free x)))
                      (env (pairlis fv fv))
                      (idx 0)
                      (sub (map 'list
                                #'(lambda (x)
                                    (let ((sub `(,x . (env-ref ,id ,x ,idx))))
                                      (setf idx (1+ idx))
                                      sub))
                                fv))
                      (body* (substitute* sub body)))
                 `(make-closure (lambda* ,params* ,@body*)
                                (make-env ,id ,@env))))
       (let x)
       (lambda* x)
       (make-closure x)
       (make-env x)
       (env-ref x)
       (apply-closure x)
       (let* x)
       (t (let ((f (first x))
                (args (rest x)))
            `(apply-closure ,f . ,args)))))))

(defun free (x)
  (cond
    ((symbolp x) (list x))
    ((integerp x) '())
    ((case (first x)
       (lambda (let ((params (second x))
                     (body (rest (rest x))))
                 (set-difference (free body) params)))
       (let (let ((vars (map 'list #'first (second x)))
                  (body (rest (rest x))))
              (set-difference (free body) vars)))
       (lambda* (let ((params (second x))
                      (body (rest (rest x))))
                  (set-difference (free body) params)))
       (make-closure (let ((proc (second x))
                           (env (third x)))
                       (union (free proc) (free env))))
       (make-env (let ((es (mapcar #'cdr (rest (rest x)))))
                   (delete-duplicates (flatten (map 'list #'free es)))))
       (env-ref (let ((env (second x)))
                  (free env)))
       (apply-closure (let ((f (second x))
                            (args (rest (rest x))))
                        (delete-duplicates (flatten (map 'list #'free `(,f . ,args))))))
       (let* (let ((vars (map 'list #'first (second x)))
                  (body (rest (rest x))))
              (set-difference (free body) vars)))
       (t (let ((f (first x))
                (args (rest x)))
            (delete-duplicates (flatten (map 'list #'free `(,f . ,args))))))))))


(defun transform-bottom-up (f x)
  (defun transform (x*) (transform-bottom-up f x*))
  (let ((x* (cond
              ((symbolp x) x)
              ((integerp x) x)
              ((case (first x)
                 (lambda (let ((params (second x))
                               (body (rest (rest x))))
                           `(lambda ,params ,@(map 'list #'transform body))))
                 (let (let ((vars (map 'list #'first (second x)))
                            (exps (map 'list #'second (second x)))
                            (body (rest (rest x))))
                        `(let* ,(map 'list #'(lambda (var exp)
                                               `(,var ,(transform exp))) vars exps)
                           ,@(map 'list #'transform body))))
                 (lambda* (let ((params (second x))
                                (body (rest (rest x))))
                            `(lambda* ,params ,@(map 'list #'transform body))))
                 (make-closure (let ((lam (second x))
                                     (env (third x)))
                                 `(make-closure ,(transform lam) ,(transform env))))
                 (make-env (let ((id (second x))
                                 (vs (map 'list #'car (rest (rest x))))
                                 (es (map 'list #'cdr (rest (rest x)))))
                             `(make-env ,id ,@(pairlis vs
                                                       (map 'list
                                                            #'transform
                                                            es)))))
                 (env-ref (let ((env (second x))
                                (v (third x)))
                            `(env-ref ,(transform env) ,v)))
                 (apply-closure (let ((f (second x))
                                      (args (rest (rest x))))
                                  `(apply-closure ,(transform f)
                                                  ,@(map 'list #'transform args))))
                 (let* (let ((vars (map 'list #'first (second x)))
                             (exps (map 'list #'second (second x)))
                             (body (rest (rest x))))
                         `(let* ,(map 'list #'(lambda (var exp)
                                                `(,var ,(transform exp))) vars exps)
                            ,@(map 'list #'transform body))))
                 (t (let ((f (first x))
                          (args (rest x)))
                      `(,(transform f) ,@(map 'list #'transform args)))))))))
    (funcall f x*)))

(defun flat-closure-convert (x)
  (transform-bottom-up #'closure-convert x))
