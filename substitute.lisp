(in-package #:satori)

(defun substitute* (sub x)
  (cond
    ((symbolp x) (if (assoc x sub)
                     (cdr (assoc x sub))
                     x))
    ((integerp x) x)
    ((case (first x)
       (lambda (let* ((params (second x))
                      (body (rest (rest x)))
                      (sub* (map 'list
                                 #'(lambda (x)
                                     (let ((k (car x)))
                                       (when (not (member k params))
                                         x)))
                                 sub)))
                 `(lambda ,params ,@(substitute* sub* body))))
       (let (let* ((vars (map 'list #'first (second x)))
                   (exps (map 'list #'second (second x)))
                   (sub* (map 'list
                              #'(lambda (x)
                                  (let ((k (car x)))
                                    (when (not (member k vars))
                                      x)))
                              sub))
                   (body (rest (rest x))))
              `(let ,(map 'list #'(lambda (var exp)
                                    `(,var ,(substitute* sub exp))) vars exps)
                 ,@(substitute* sub* body))))
       (lambda* (let* ((params (second x))
                       (body (rest (rest x)))
                       (sub* (map 'list
                                  #'(lambda (x)
                                      (let ((k (car x)))
                                        (when (not (member k params))
                                          x)))
                                  sub)))
                  `(lambda* ,params ,@(substitute* sub* body))))
       (make-closure (let ((lam (second x))
                           (env (third x)))
                       `(make-closure ,(substitute* sub lam) ,(substitute* sub env))))
       (make-env (let ((id (second x))
                       (vs (map 'list #'car (rest (rest x))))
                       (es (map 'list #'cdr (rest (rest x)))))
                   `(make-env ,id ,@(pairlis vs (map 'list
                                                     #'(lambda (x)
                                                         (substitute* sub x))
                                                     es)))))
       (env-ref (let ((env (second x))
                      (v (third x))
                      (idx (fourth x)))
                  `(env-ref ,(substitute* sub env) ,v ,idx)))
       (apply-closure (let ((f (second x))
                            (args (rest (rest x))))
                        `(apply-closure ,@(map 'list
                                               #'(lambda (x)
                                                   (substitute* sub x))
                                               `(,f . ,args)))))
       (let* (let* ((vars (map 'list #'first (second x)))
                    (exps (map 'list #'second (second x)))
                    (sub* (map 'list
                               #'(lambda (x)
                                   (let ((k (car x)))
                                     (when (not (member k vars))
                                       x)))
                               sub))
                    (body (rest (rest x))))
               `(let* ,(map 'list #'(lambda (var exp)
                                      `(,var ,(substitute* sub exp))) vars exps)
                  ,@(substitute* sub* body))))
       (t (let ((f (first x))
                (args (rest x)))
            (map 'list #'(lambda (x) (substitute* sub x)) `(,f . ,args))))))))
