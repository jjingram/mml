;; See: http://matt.might.net/articles/closure-conversion/

(in-package #:satori)

(defvar *global-environment*)

(defun closure-convert (x)
  (case (first x)
    (i32 x)
    (variable x)
    (lambda% (let* ((params (second x))
                    (env-var (first params))
                    (retty (third x))
                    (body (rest (rest (rest x))))
                    (fv (set-difference (sort-symbols< (free x))
                                        `(%callee . ,*global-environment*)))
                    (env (pairlis fv fv))
                    (idx 0)
                    (sub (map 'list
                              #'(lambda (x)
                                  (let ((sub `(,x . (env-ref ,env-var ,x ,idx))))
                                    (setf idx (1+ idx))
                                    sub))
                              fv))
                    (body* (substitute* sub body)))
               `(make-closure (lambda* ,params ,retty ,@body*)
                              (make-env ,env-var ,@env))))
    (let% x)
    (define% x)
    (if% x)
    (eq% x)
    ((add% sub% mul% sdiv% srem%) x)
    (cons% x)
    (arity% x)
    (nth% x)
    (quote% x)
    (cast% x)
    (lambda* x)
    (make-closure x)
    (make-env x)
    (env-ref x)
    (apply-closure x)
    (let* x)
    (define* x)
    (if* x)
    (eq* x)
    (cons* x)
    ((add* sub* mul* sdiv* srem*) x)
    (arity* x)
    (nth* x)
    (quote* x)
    (cast* x)
    (t (cond
         ((integerp (first x)) x)
         (t (let ((f (first x))
                  (args (rest x)))
              `(apply-closure ,f ,@args)))))))

(defun free (x)
  (cond
    ((integerp x) nil)
    ((symbolp x) (list x))
    ((case (first x)
       (nil nil)
       (i32 nil)
       (lambda (let* ((params (second x))
                      (body (rest (rest x))))
                 (set-difference (free body) params)))
       (let (let* ((vars (second x))
                   (vars* (map 'list #'first vars))
                   (body (rest (rest x))))
              (set-difference (free body) vars*)))
       (variable (list (free (second x))))
       (lambda% (let* ((params (second x))
                       (body (rest (rest (rest x))))
                       (params* (map 'list #'second params)))
                  (set-difference (free body) params*)))
       (let% (let* ((vars (map 'list #'first (second x)))
                    (vars* (map 'list #'second vars))
                    (body (rest (rest x))))
               (set-difference (free body) vars*)))
       (if% (let* ((pred (second x))
                   (true (fifth x))
                   (false (sixth x)))
              (delete-duplicates (flatten (append (free pred) (free true) (free false))))))
       (define% (let ((name (second (second x)))
                      (exp (third x)))
                  (set-difference (free exp) (list name))))
       (eq% (let ((lhs (third x))
                  (rhs (fourth x)))
              (delete-duplicates (flatten (append (free lhs) (free rhs))))))
       ((add% sub% mul% sdiv% srem%)
        (let ((lhs (third x))
              (rhs (fourth x)))
          (delete-duplicates (flatten (append (free lhs) (free rhs))))))
       (cons% (let ((elements (second x)))
                (delete-duplicates (flatten (map 'list #'free elements)))))
       (arity% nil)
       (nth% (let ((cons (second x)))
               (free cons)))
       (quote% nil)
       (cast% (let* ((union (third x))
                     (union-exp (first union))
                     (clauses (fifth x))
                     (bodies (map 'list #'second clauses)))
                (delete-duplicates (flatten (cons (free (second union-exp))
                                                  (map 'list #'free bodies))))))
       (lambda* (let* ((params (second x))
                       (body (rest (rest (rest x))))
                       (params* (map 'list #'second params)))
                  (set-difference (free body) params*)))
       (make-closure (let ((proc (second x))
                           (env (third x)))
                       (union (free proc) (free env))))
       (make-env (let ((es (mapcar #'cdr (rest (rest x)))))
                   (delete-duplicates (flatten (map 'list #'free es)))))
       (env-ref nil)
       (apply-closure (let ((f (second x))
                            (args (rest (rest x))))
                        (delete-duplicates (flatten (map 'list #'free `(,f . ,args))))))
       (let* (let* ((vars (map 'list #'first (second x)))
                    (vars* (map 'list #'second vars))
                    (body (rest (rest x))))
               (set-difference (free body) vars*)))
       (define* (let ((name (second (second x)))
                      (exp (third x)))
                  (set-difference (free exp) (list name))))
       (if* (let* ((pred (second x))
                   (true (fifth x))
                   (false (sixth x)))
              (delete-duplicates (flatten (append (free pred) (free true) (free false))))))
       (eq* (let ((lhs (third x))
                  (rhs (fourth x)))
              (delete-duplicates (flatten (append (free lhs) (free rhs))))))
       ((add* sub* mul* sdiv* srem*)
        (let ((lhs (third x))
              (rhs (fourth x)))
          (delete-duplicates (flatten (append (free lhs) (free rhs))))))
       (cons* (let ((elements (second x)))
                (delete-duplicates (flatten (map 'list #'free elements)))))
       (arity* nil)
       (nth* (let ((cons (second x)))
               (free cons)))
       (quote* nil)
       (cast* (let* ((union (third x))
                     (union-exp (first union))
                     (clauses (fifth x))
                     (bodies (map 'list #'second clauses)))
                (delete-duplicates (flatten (cons (free (second union-exp))
                                                  (map 'list #'free bodies))))))
       (t (let ((f (first x))
                (args (rest x)))
            (delete-duplicates (flatten (map 'list #'free `(,f . ,args))))))))))


(defun transform-bottom-up (f x)
  (defun transform (x*) (unless (null x*) (transform-bottom-up f x*)))
  (let ((x*
          (case (first x)
            (i32 x)
            (variable x)
            (lambda% (let ((params (second x))
                          (retty (third x))
                          (body (rest (rest (rest x)))))
                      `(lambda% ,params ,retty ,@(map 'list #'transform body))))
            (let% (let ((vars (map 'list #'first (second x)))
                        (exps (map 'list #'second (second x)))
                        (body (rest (rest (rest x)))))
                    `(let* ,(map 'list #'(lambda (var exp)
                                           `(,var ,(transform exp))) vars exps)
                       ,@(map 'list #'transform body))))
            (define% (let ((var (second x))
                           (exp (third x)))
                       (setf *global-environment* `(,(second var) . ,*global-environment*))
                       `(define* ,var ,(transform exp))))
            (if% (let ((pred (second x))
                       (pred-type (third x))
                       (body-type (fourth x))
                       (true (fifth x))
                       (false (sixth x)))
                   `(if* ,(transform pred) ,pred-type ,body-type ,(transform true)
                                                                  ,(transform false))))
            (eq% (let ((type (second x))
                       (lhs (third x))
                       (rhs (fourth x)))
                   `(eq* ,type ,(transform lhs) ,(transform rhs))))
            ((add% sub% mul% sdiv% srem%)
             (let ((op (intern (substitute #\* #\% (string (first x)))))
                   (lhs (second x))
                   (rhs (third x)))
               `(,op ,(transform lhs) ,(transform rhs))))
            (cons% (let ((elements (second x))
                         (types (third x)))
                     `(cons* ,(map 'list #'transform elements) ,types)))
            (arity% (let ((type (second x)))
                       `(arity* ,type)))
            (nth% (let ((idx (second x))
                        (cons (third x)))
                    `(nth* ,idx ,(transform cons))))
            (quote% (let ((const (second x))
                          (type (third x)))
                      `(quote* ,const ,type)))

            (cast% (let* ((rettype (second x))
                          (union (third x))
                          (union-exp (first union))
                          (union-type (second union))
                          (variable (fourth x))
                          (clauses (fifth x))
                          (types (map 'list #'first clauses))
                          (bodies (map 'list #'second clauses)))
                     `(cast* ,rettype (,(transform union-exp) ,union-type) ,variable
                             (,@(map 'list #'list types (map 'list #'transform bodies))))))
            (lambda* (let ((params (second x))
                           (retty (third x))
                           (body (rest (rest (rest x)))))
                       `(lambda* ,params ,retty ,@(map 'list #'transform body))))
            (make-closure (let ((lam (second x))
                                (env (third x)))
                            `(make-closure ,(transform lam) ,(transform env))))
            (make-env (let ((id (second x))
                            (vs (map 'list #'car (rest (rest x))))
                            (es (map 'list #'cdr (rest (rest x)))))
                        `(make-env ,id ,@(pairlis vs (map 'list #'transform es)))))
            (env-ref (let ((env-var (second x))
                           (v (third x)))
                       `(env-ref ,env-var ,v)))
            (apply-closure (let ((f (second x))
                                 (args (rest (rest x))))
                             `(apply-closure ,(transform f)
                                             ,@(map 'list #'transform args))))
            (let* (let ((vars (map 'list #'first (second x)))
                        (exps (map 'list #'second (second x)))
                        (body (rest (rest x))))
                    `(let* ,(map 'list
                                 #'(lambda (var exp)
                                     `(,var ,(transform exp))) vars exps)
                       ,@(map 'list #'transform body))))
            (define* (let ((var (second x))
                           (exp (third x)))
                       (setf *global-environment* `(,(second var) . ,*global-environment*))
                       `(define* ,var ,(transform exp))))
            (if* (let ((pred (second x))
                       (pred-type (third x))
                       (body-type (fourth x))
                       (true (fifth x))
                       (false (sixth x)))
                   `(if* ,(transform pred) ,pred-type ,body-type ,(transform true)
                                                                  ,(transform false))))
            (eq* (let ((type (second x))
                       (lhs (third x))
                       (rhs (fourth x)))
                   `(eq* ,type ,(transform lhs) ,(transform rhs))))
            ((add* sub* mul* sdiv* srem*)
             (let ((op (first x))
                   (lhs (second x))
                   (rhs (third x)))
               `(,op ,(transform lhs) ,(transform rhs))))
            (cons* (let ((elements (second x))
                         (types (third x)))
                     `(cons* ,@(map 'list #'transform elements) ,types)))
            (arity* (let ((type (second x)))
                       `(arity* ,type)))
            (nth* (let ((idx (second x))
                        (cons (third x)))
                    `(nth* ,idx ,(transform cons))))
            (quote* (let ((const (second x))
                          (type (third x)))
                      `(quote* ,const ,type)))
            (cast* (let* ((rettype (second x))
                          (union (third x))
                          (union-exp (first union))
                          (union-type (second union))
                          (variable (fourth x))
                          (clauses (fifth x))
                          (types (map 'list #'first clauses))
                          (bodies (map 'list #'second clauses)))
                     `(cast* ,rettype (,(transform union-exp) ,union-type) ,variable
                             (,@(map 'list #'list types (map 'list #'transform bodies))))))
            (t (let ((f (first x))
                     (args (rest x)))
                 `(,(transform f) ,@(map 'list #'transform args)))))))
    (funcall f x*)))

(defun flat-closure-convert (x)
  (setf *global-environment* nil)
  (transform-bottom-up #'closure-convert x))
